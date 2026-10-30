import Foundation
import Synchronization

/// Uploads jobs one at a time, in order, with retry and backoff. A template job's key is reserved
/// with HEAD before its PUT; a fixed-key job PUTs its key as is. A large file goes multipart: its
/// parts are sent a few at a time, each request retried on its own, in one pass of the job. A
/// stored multipart upload resumes from the parts it has, and one the server lost starts again.
/// Reports progress and results through `events`, which runs on the main actor. A job can be
/// cancelled while pending or in flight; it then ends with a single `.cancelled` event.
actor UploadQueue {
    typealias EventHandler = @MainActor @Sendable (UploadEvent) -> Void
    typealias Sleeper = @Sendable (Duration) async throws -> Void
    typealias Logger = @Sendable (String) -> Void

    /// Starts and stops a folder's security-scoped access; a fake in tests.
    nonisolated struct SecurityScope: Sendable {
        /// True when access was started and must be stopped.
        var start: @Sendable (URL) -> Bool
        var stop: @Sendable (URL) -> Void

        static let live = SecurityScope(start: { $0.startAccessingSecurityScopedResource() },
                                        stop: { $0.stopAccessingSecurityScopedResource() })
    }

    /// Keeps progress events to at most one per `interval`: the first fraction passes, then one
    /// per interval, and a fraction of 1 always does.
    nonisolated struct ProgressThrottle: Sendable {
        static let interval: Duration = .milliseconds(100)

        private var lastAdmitted: ContinuousClock.Instant?

        mutating func admits(_ fraction: Double, at instant: ContinuousClock.Instant) -> Bool {
            if fraction >= 1 { return true }
            if let lastAdmitted, instant - lastAdmitted < Self.interval { return false }
            lastAdmitted = instant
            return true
        }
    }

    /// What `cancel(recordID:)` found.
    nonisolated enum CancelResult: Sendable, Equatable {
        /// Nothing pending or in flight had that id: it already finished (its `.uploaded` or
        /// `.failed` event has been delivered) or was never enqueued.
        case notFound
        /// The job has ended and its `.cancelled` event has been delivered. `reservedKey` is the
        /// object key the job had claimed (its fixed key, or one reserved with HEAD-before-PUT),
        /// nil when it was cancelled before that. The PUT for that key may have completed on the
        /// server just as it was cancelled, so a caller that is deleting the capture deletes this
        /// key too.
        case stopped(reservedKey: String?)
    }

    /// How a job's task ended, after its terminal event was delivered.
    private nonisolated enum JobOutcome: Sendable {
        case uploaded
        case failed
        case cancelled(reservedKey: String?)
    }

    /// A part that ran out of tries, or met an error that is not retried. Its description is the
    /// job's failure message.
    private nonisolated struct PartFailure: LocalizedError {
        var number: Int
        var count: Int
        var error: any Error

        var errorDescription: String? { "Part \(number) of \(count): \(error.localizedDescription)" }
    }

    /// Where a multipart job goes next: on with a stored upload, or a new one (at `reusing`, or a
    /// key drawn afresh).
    private nonisolated enum MultipartStep: Sendable {
        case resume(MultipartUploadState)
        case create(reusing: String?)
    }

    /// Why a multipart job drops its upload and creates another (design, Resume).
    private nonisolated struct Restart: Error {
        /// The job's failure when it has no restart left.
        var cause: any Error
        /// The log line's reason, before `, starting again`; nil logs none.
        var reason: String?
        /// The upload to abort first, when it may still exist.
        var abort: (key: String, uploadID: String)?
        /// The key to create under: nil draws a new one.
        var key: String?

        /// The server no longer knows the upload id: nothing to abort, and the same key.
        static func uploadIDGone(key: String) -> Restart {
            Restart(cause: UploadError.noSuchUpload, reason: "upload id gone", abort: nil, key: key)
        }
    }

    /// One upload id and how its file is cut into parts.
    private nonisolated struct MultipartTarget: Sendable {
        var key: String
        var uploadID: String
        var partSize: Int64
        var byteCount: Int64

        var count: Int { MultipartPlan.partCount(byteCount: byteCount, partSize: partSize) }

        /// True when `part` has a number of this upload and the size that number should have.
        func expects(_ part: MultipartPart) -> Bool {
            guard part.number >= 1, part.number <= count else { return false }
            let range = MultipartPlan.range(ofPart: part.number, partSize: partSize, byteCount: byteCount)
            return part.size == range.upperBound - range.lowerBound
        }
    }

    /// What every step of one multipart job shares.
    private nonisolated struct MultipartPass: Sendable {
        var job: UploadJob
        /// For the log: the file's name.
        var name: String
        var file: URL
        var source: MultipartSource
        var store: MultipartStore
        /// The job's throttled `.progress` events.
        var report: @Sendable (Double) -> Void
    }

    static let maxKeyAttempts = 5

    private let destination: any Destination
    private let keyNamer: ObjectKeyNamer
    /// For `.data` jobs.
    private let policy: RetryPolicy
    /// For `.file` jobs.
    private let filePolicy: RetryPolicy
    private let scope: SecurityScope
    private let sleep: Sleeper
    private let plan: MultipartPlan
    /// Where a multipart job keeps its parts; with none, every job uses the single PUT.
    private let store: MultipartStore?
    private let now: @Sendable () -> Date
    private let log: Logger
    private let events: EventHandler
    private var pending: [UploadJob] = []
    private var isDraining = false
    /// The job being processed and the task running it, so `cancel` can stop it and wait for it.
    private var current: (id: UUID, task: Task<JobOutcome, Never>)?
    private var cancelledIDs: Set<UUID> = []
    /// The in-flight job's key (its fixed key, or one reserved with HEAD), reported in its
    /// `.cancelled` event if it is cancelled.
    private var reservedKeys: [UUID: String] = [:]

    init(destination: any Destination,
         keyNamer: ObjectKeyNamer,
         policy: RetryPolicy = .default,
         filePolicy: RetryPolicy = .file,
         scope: SecurityScope = .live,
         sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
         plan: MultipartPlan = .standard,
         store: MultipartStore? = nil,
         now: @escaping @Sendable () -> Date = { Date() },
         log: @escaping Logger = { NSLog("%@", $0) },
         events: @escaping EventHandler) {
        self.destination = destination
        self.keyNamer = keyNamer
        self.policy = policy
        self.filePolicy = filePolicy
        self.scope = scope
        self.sleep = sleep
        self.plan = plan
        self.store = store
        self.now = now
        self.log = log
        self.events = events
    }

    var isIdle: Bool { pending.isEmpty && !isDraining }

    func enqueue(_ job: UploadJob) {
        pending.append(job)
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    /// Stops the job for `recordID`. A pending job is dropped and reports `.cancelled` at once. An
    /// in-flight job has its task cancelled, which makes the HEAD, the PUT, or the backoff sleep
    /// throw; the job then reports `.cancelled` instead of `.failed`, and this call returns once
    /// that event has been delivered. If the job ends some other way first (its PUT finished, or
    /// it had already reported `.uploaded` or `.failed`), this returns `.notFound`. Later jobs
    /// continue.
    func cancel(recordID: UUID) async -> CancelResult {
        if let index = pending.firstIndex(where: { $0.id == recordID }) {
            pending.remove(at: index)
            await events(.cancelled(id: recordID, reservedKey: nil))
            return .stopped(reservedKey: nil)
        }
        guard let current, current.id == recordID else { return .notFound }
        cancelledIDs.insert(recordID)
        current.task.cancel()
        let outcome = await current.task.value
        cancelledIDs.remove(recordID)
        reservedKeys[recordID] = nil
        // The job's own outcome decides the result, so concurrent cancels agree on it.
        if case .cancelled(let key) = outcome { return .stopped(reservedKey: key) }
        return .notFound
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            let task = Task { await process(job) }
            current = (job.id, task)
            _ = await task.value
            current = nil
        }
        isDraining = false
    }

    /// Runs `job` to its end, delivers the terminal event, and returns how it ended.
    private func process(_ job: UploadJob) async -> JobOutcome {
        if let store, let source = job.multipartSource, plan.uses(payload: job.payload, byteCount: source.byteCount),
           case .file(let url, let folder) = job.payload {
            return await processMultipart(job, file: url, holding: folder, source: source, store: store)
        }
        let policy: RetryPolicy
        switch job.payload {
        case .data: policy = self.policy
        case .file: policy = filePolicy
        }
        // A start over whose new file is under the threshold goes as one PUT, and the stored
        // upload is aborted here, once, as `processMultipart` does (best effort).
        if let ref = job.abortFirst {
            await abortUpload(key: ref.key, uploadID: ref.uploadID, name: Self.fileName(of: job.payload))
            if cancelledIDs.contains(job.id) {
                return await deliverCancelled(job.id)
            }
        }
        var attempt = 1
        while true {
            await events(.started(id: job.id, attempt: attempt, fraction: 0))
            do {
                let key = try await objectKey(for: job, retryingHEADs: false)
                reservedKeys[job.id] = key
                let progress = throttledProgress(for: job.id)
                switch job.payload {
                case .data(let data):
                    try await destination.upload(data, key: key, contentType: job.contentType,
                                                 cacheControl: job.cacheControl, progress: progress)
                case .file(let url, let folder):
                    try await uploadFile(at: url, holding: folder, key: key, job: job, progress: progress)
                }
                let url = try destination.publicURL(for: key)
                reservedKeys[job.id] = nil
                await events(.uploaded(id: job.id, url: url, key: key))
                return .uploaded
            } catch {
                if cancelledIDs.contains(job.id) {
                    return await deliverCancelled(job.id)
                }
                if UploadError.isRetryable(error), attempt < policy.maxAttempts {
                    attempt += 1
                    do {
                        try await sleep(policy.delay(beforeAttempt: attempt))
                    } catch {
                        if cancelledIDs.contains(job.id) {
                            return await deliverCancelled(job.id)
                        }
                        // A backoff sleep that fails on its own ends the job instead of retrying.
                        reservedKeys[job.id] = nil
                        await events(.failed(id: job.id, message: error.localizedDescription))
                        return .failed
                    }
                    continue
                }
                reservedKeys[job.id] = nil
                await events(.failed(id: job.id, message: error.localizedDescription))
                return .failed
            }
        }
    }

    /// A multipart job's one pass, holding `folder`'s scope throughout. A fresh job creates its
    /// upload; a job with `resume` carries on with the stored one. Each request retries on its own
    /// under `filePolicy`; the job as a whole is not retried. A cause in `Restart` drops the upload
    /// and creates another, at most `MultipartPlan.restartLimit` times. The sidecar is rewritten
    /// after each part, and marks Complete as sent before it goes; a sidecar that cannot be written
    /// fails the job with the write's error.
    private func processMultipart(_ job: UploadJob, file url: URL, holding folder: URL?,
                                  source: MultipartSource, store: MultipartStore) async -> JobOutcome {
        let name = url.lastPathComponent
        let accessing = folder.map(scope.start) ?? false
        defer {
            if accessing, let folder { scope.stop(folder) }
        }
        let pass = MultipartPass(job: job, name: name, file: url, source: source, store: store,
                                 report: throttledProgress(for: job.id))
        // A resume starts its bar once it knows the parts done.
        if job.resume == nil {
            await events(.started(id: job.id, attempt: 1, fraction: 0))
        }
        do {
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                throw UploadError.fileUnreadable(name)
            }
            if let ref = job.abortFirst {
                await abortUpload(key: ref.key, uploadID: ref.uploadID, name: name)
                try Task.checkCancellation()
            }
            var step: MultipartStep = job.resume.map { .resume($0) } ?? .create(reusing: nil)
            var restarts = 0
            var rejectedOnce = false
            while true {
                do {
                    let key: String
                    switch step {
                    case .resume(let stored):
                        key = try await resumeUpload(stored, pass, rejectedOnce: &rejectedOnce)
                    case .create(let reusing):
                        key = try await createUpload(pass, reusing: reusing, rejectedOnce: &rejectedOnce)
                    }
                    let publicURL = try destination.publicURL(for: key)
                    reservedKeys[job.id] = nil
                    await events(.uploaded(id: job.id, url: publicURL, key: key))
                    return .uploaded
                } catch let restart as Restart {
                    if cancelledIDs.contains(job.id) { return await deliverCancelled(job.id) }
                    guard restarts < MultipartPlan.restartLimit else { throw restart.cause }
                    restarts += 1
                    reservedKeys[job.id] = nil
                    if let abort = restart.abort {
                        await abortUpload(key: abort.key, uploadID: abort.uploadID, name: name)
                    }
                    if let reason = restart.reason {
                        log("Upload: \(name) \(reason), starting again")
                    }
                    try Task.checkCancellation()
                    // `attempt` counts restarts.
                    await events(.started(id: job.id, attempt: restarts + 1, fraction: 0))
                    step = .create(reusing: restart.key)
                }
            }
        } catch {
            // The task group has awaited every part by now, so a cancel's event comes after the last.
            if cancelledIDs.contains(job.id) {
                return await deliverCancelled(job.id)
            }
            reservedKeys[job.id] = nil
            await events(.failed(id: job.id, message: error.localizedDescription))
            return .failed
        }
    }

    /// A new upload: the key (drawn and reserved, or `reusing` HEADed again), Create, the state
    /// and an empty sidecar, then every part and Complete. Returns the key the object landed at.
    private func createUpload(_ pass: MultipartPass, reusing: String?, rejectedOnce: inout Bool) async throws -> String {
        let job = pass.job
        // The coordinator refuses a file over the plan's limit, so a nil part size cannot happen.
        guard let partSize = plan.partSize(for: pass.source.byteCount) else {
            throw UploadError.fileUnreadable(pass.name)
        }
        let key = if let reusing { try await reserveAgain(reusing, for: job) } else {
            try await objectKey(for: job, retryingHEADs: true)
        }
        reservedKeys[job.id] = key
        let uploadID: String
        do {
            uploadID = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                try await self.destination.createMultipartUpload(key: key, contentType: job.contentType,
                                                                 cacheControl: job.cacheControl)
            }
        } catch {
            if !cancelledIDs.contains(job.id) {
                log("Upload: \(pass.name) create failed: \(error.localizedDescription)")
            }
            throw error
        }
        let source = pass.source
        let state = MultipartUploadState(uploadID: uploadID, key: key, location: source.location,
                                         partSize: partSize, byteCount: source.byteCount,
                                         sourceModified: source.modified, sourcePath: source.path,
                                         startedAt: now())
        let target = MultipartTarget(key: key, uploadID: uploadID, partSize: partSize, byteCount: source.byteCount)
        var sidecar = MultipartSidecar(uploadID: uploadID, completeSent: false, parts: [])
        try pass.store.writeSidecar(sidecar, id: job.id)
        await events(.multipartStarted(id: job.id, state: state))
        log("Upload: \(pass.name) multipart, \(target.count) parts of \(Self.mebibytes(partSize)) MiB, upload id \(uploadID)")
        try await sendParts(Array(1..<(target.count + 1)), of: target, sidecar: &sidecar, pass)
        try await complete(target, sidecar: &sidecar, pass, rejectedOnce: &rejectedOnce)
        return key
    }

    /// Carries on with a stored upload, at its key, id and part size. A template key is HEADed
    /// first: absent goes on, the stored size means an earlier Complete landed, and another size
    /// means another capture took the key, which restarts under a new one. Then the parts the
    /// sidecar (or ListParts) lacks, and Complete. Returns the key the object landed at.
    private func resumeUpload(_ stored: MultipartUploadState, _ pass: MultipartPass,
                              rejectedOnce: inout Bool) async throws -> String {
        let target = MultipartTarget(key: stored.key, uploadID: stored.uploadID, partSize: stored.partSize,
                                     byteCount: stored.byteCount)
        if case .template = pass.job.key {
            let size = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                try await self.destination.objectSize(key: stored.key)
            }
            if size == stored.byteCount { return stored.key }
            if size != nil {
                // A resume's first step, so never a third cause.
                throw Restart(cause: UploadError.keyCollisionsExhausted, reason: "key taken",
                              abort: (stored.key, stored.uploadID), key: nil)
            }
        }
        reservedKeys[pass.job.id] = stored.key
        var sidecar = try await partList(of: target, pass)
        let numbers = Set(sidecar.parts.map(\.number))
        let missing = (1..<(target.count + 1)).filter { !numbers.contains($0) }
        let doneBytes = sidecar.parts.reduce(0) { $0 + $1.size }
        await events(.started(id: pass.job.id, attempt: 1,
                              fraction: MultipartPlan.fraction(doneBytes: doneBytes, inFlightBytes: 0, total: target.byteCount)))
        log("Upload: \(pass.name) resumes at \(sidecar.parts.count) of \(target.count) parts")
        try await sendParts(missing, of: target, sidecar: &sidecar, pass)
        try await complete(target, sidecar: &sidecar, pass, rejectedOnce: &rejectedOnce)
        return stored.key
    }

    /// The stored sidecar, or one rebuilt from ListParts when it is missing, unreadable or for
    /// another upload id. A listed part is trusted when its size is the one its number should have.
    private func partList(of target: MultipartTarget, _ pass: MultipartPass) async throws -> MultipartSidecar {
        if let sidecar = pass.store.readSidecar(id: pass.job.id, uploadID: target.uploadID) {
            return sidecar
        }
        log("Upload: \(pass.name) part list missing, listing parts")
        var trusted: [Int: MultipartPart] = [:]
        for part in try await listParts(of: target, pass) where target.expects(part) {
            trusted[part.number] = part
        }
        let sidecar = MultipartSidecar(uploadID: target.uploadID, completeSent: false,
                                       parts: trusted.values.sorted { $0.number < $1.number })
        try pass.store.writeSidecar(sidecar, id: pass.job.id)
        return sidecar
    }

    /// ListParts, retried. A gone upload id, or any other failure left after the retries (a 403
    /// for a key without `s3:ListMultipartUploadParts`), restarts the job under the same key.
    private func listParts(of target: MultipartTarget, _ pass: MultipartPass) async throws -> [MultipartPart] {
        do {
            return try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                try await self.destination.listParts(key: target.key, uploadID: target.uploadID)
            }
        } catch UploadError.noSuchUpload {
            throw Restart.uploadIDGone(key: target.key)
        } catch {
            throw Restart(cause: error, reason: "part list unavailable", abort: (target.key, target.uploadID),
                          key: target.key)
        }
    }

    /// Sends `numbers` of `target`'s parts, at most `plan.inFlight` at a time and added in order as
    /// each finishes, putting each in the sidecar (rewritten) as it lands. Progress starts at the
    /// sidecar's bytes. A part whose upload id is gone restarts the job under the same key.
    private func sendParts(_ numbers: [Int], of target: MultipartTarget, sidecar: inout MultipartSidecar,
                           _ pass: MultipartPass) async throws {
        guard !numbers.isEmpty else { return }
        let doneBytes = sidecar.parts.reduce(0) { $0 + $1.size }
        let sender = PartSender(destination: destination, policy: filePolicy, sleep: sleep, log: log,
                                name: pass.name, file: pass.file, key: target.key, uploadID: target.uploadID,
                                partSize: target.partSize, byteCount: target.byteCount, count: target.count,
                                progress: MultipartProgress(total: target.byteCount, done: doneBytes),
                                report: pass.report)
        do {
            try await withThrowingTaskGroup(of: MultipartPart.self) { group in
                var next = numbers.startIndex
                while next < numbers.endIndex, next - numbers.startIndex < plan.inFlight {
                    let number = numbers[next]
                    group.addTask { try await sender.send(number) }
                    next += 1
                }
                while let part = try await group.next() {
                    sidecar.parts.removeAll { $0.number == part.number }
                    sidecar.parts.append(part)
                    sidecar.parts.sort { $0.number < $1.number }
                    try pass.store.writeSidecar(sidecar, id: pass.job.id)
                    sender.report(sender.progress.finish(part: part.number, size: part.size))
                    if next < numbers.endIndex {
                        let number = numbers[next]
                        group.addTask { try await sender.send(number) }
                        next += 1
                    }
                }
            }
        } catch let failure as PartFailure where (failure.error as? UploadError) == .noSuchUpload {
            throw Restart.uploadIDGone(key: target.key)
        }
    }

    /// Complete, retried, once the sidecar says it was sent. A gone upload id restarts the job,
    /// unless a Complete was sent for it before (before a quit, or a try whose answer was lost)
    /// and the object has the upload's size. The first rejected part list in the job is listed
    /// again and the parts that differ are resent; a second one restarts.
    private func complete(_ target: MultipartTarget, sidecar: inout MultipartSidecar, _ pass: MultipartPass,
                          rejectedOnce: inout Bool) async throws {
        while true {
            var sentBefore = sidecar.completeSent
            // Complete never goes before the sidecar says it was sent.
            sidecar.completeSent = true
            try pass.store.writeSidecar(sidecar, id: pass.job.id)
            let parts = sidecar.parts
            do {
                try await Self.withRetries(policy: filePolicy, sleep: sleep, onRetry: { _, _ in sentBefore = true }) {
                    try await self.destination.completeMultipartUpload(key: target.key, uploadID: target.uploadID,
                                                                       parts: parts)
                }
            } catch UploadError.noSuchUpload {
                guard sentBefore else { throw Restart.uploadIDGone(key: target.key) }
                let size = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                    try await self.destination.objectSize(key: target.key)
                }
                guard size == target.byteCount else { throw Restart.uploadIDGone(key: target.key) }
            } catch let error as UploadError {
                guard case .partsRejected = error else { throw error }
                guard !rejectedOnce else {
                    throw Restart(cause: error, reason: nil, abort: (target.key, target.uploadID), key: target.key)
                }
                rejectedOnce = true
                log("Upload: \(pass.name) part list rejected, listing parts")
                let listed = Set(try await listParts(of: target, pass))
                sidecar.parts.removeAll { !listed.contains($0) }
                try pass.store.writeSidecar(sidecar, id: pass.job.id)
                let kept = Set(sidecar.parts.map(\.number))
                try await sendParts((1..<(target.count + 1)).filter { !kept.contains($0) }, of: target,
                                    sidecar: &sidecar, pass)
                continue
            }
            log("Upload: \(pass.name) multipart completed")
            return
        }
    }

    /// Aborts an upload the job no longer uses, in one try. A failure is logged and the job goes on;
    /// the bucket's lifecycle rule removes what is left.
    private func abortUpload(key: String, uploadID: String, name: String) async {
        do {
            _ = try await destination.abortMultipartUpload(key: key, uploadID: uploadID)
            log("Upload: \(name) multipart aborted")
        } catch {
            guard !Task.isCancelled else { return }
            log("Upload: \(name) multipart abort failed: \(error.localizedDescription)")
        }
    }

    /// The file's name for a log line; empty for data.
    private static func fileName(of payload: UploadPayload) -> String {
        if case .file(let url, _) = payload { url.lastPathComponent } else { "" }
    }

    /// `key` again for a restart: a fixed key as is; a template key HEADed again, and kept when
    /// free, else a new one drawn and reserved.
    private func reserveAgain(_ key: String, for job: UploadJob) async throws -> String {
        guard case .template(let context) = job.key else { return key }
        let taken = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
            try await self.destination.exists(key: key)
        }
        return taken ? try await reserveKey(ext: job.fileExtension, context: context, retryingHEADs: true) : key
    }

    /// `bytes` in MiB for the log: whole for every real part size, decimal for a test's.
    private static func mebibytes(_ bytes: Int64) -> String {
        let mib: Int64 = 1_048_576
        return bytes % mib == 0 ? "\(bytes / mib)" : "\(Double(bytes) / Double(mib))"
    }

    /// Runs `operation` until it succeeds, it throws an error `UploadError.isRetryable` refuses,
    /// or `policy` runs out of tries, sleeping with `sleep` between tries. `onRetry` gets the try
    /// about to be made (2 for the first retry) and the error that caused it.
    private nonisolated static func withRetries<T>(policy: RetryPolicy, sleep: Sleeper,
                                           onRetry: (Int, any Error) -> Void = { _, _ in },
                                           _ operation: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch {
                guard UploadError.isRetryable(error), attempt < policy.maxAttempts else { throw error }
                attempt += 1
                onRetry(attempt, error)
                try await sleep(policy.delay(beforeAttempt: attempt))
                try Task.checkCancellation()
            }
        }
    }

    /// The bytes of `range` in the file at `url`, read off the caller's actor. A file that cannot
    /// be opened or read, or that holds fewer bytes than the range (it shrank), throws
    /// `UploadError.fileUnreadable`.
    @concurrent nonisolated static func readPart(of url: URL, range: Range<Int64>) async throws -> Data {
        let expected = Int(range.upperBound - range.lowerBound)
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(range.lowerBound))
            data = try handle.read(upToCount: expected) ?? Data()
        } catch {
            throw UploadError.fileUnreadable(url.lastPathComponent)
        }
        guard data.count == expected else { throw UploadError.fileUnreadable(url.lastPathComponent) }
        return data
    }

    /// One attempt at a file upload, holding `folder`'s scope from before the readability check
    /// until `upload(fileAt:)` returns or throws: one hold covers the hash and the streamed PUT,
    /// and a job waiting in the queue or in backoff holds nothing.
    private func uploadFile(at url: URL, holding folder: URL?, key: String, job: UploadJob,
                            progress: @escaping @Sendable (Double) -> Void) async throws {
        let accessing = folder.map(scope.start) ?? false
        defer {
            if accessing, let folder { scope.stop(folder) }
        }
        guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
            throw UploadError.fileUnreadable(url.lastPathComponent)
        }
        try await destination.upload(fileAt: url, key: key, contentType: job.contentType,
                                     cacheControl: job.cacheControl, progress: progress)
    }

    /// The progress callback for one attempt. It runs on the transport's thread, so its throttle
    /// is locked; only admitted fractions become events.
    private func throttledProgress(for id: UUID) -> @Sendable (Double) -> Void {
        let throttle = ProgressGate()
        let events = events
        return { fraction in
            guard throttle.admits(fraction) else { return }
            Task { await events(.progress(id: id, fraction: fraction)) }
        }
    }

    /// Delivers `.cancelled` with the key the job reserved (`cancel` clears the entry).
    private func deliverCancelled(_ id: UUID) async -> JobOutcome {
        let key = reservedKeys[id]
        await events(.cancelled(id: id, reservedKey: key))
        return .cancelled(reservedKey: key)
    }

    /// The key for this attempt. A template key is named afresh and reserved with HEAD. A fixed key
    /// is the record's own key at its own location, and no other record points at it (the
    /// coordinator's shared-key rule checks that), so it is PUT as is on every attempt. A HEAD
    /// would find the record's own object and steer away from it. A multipart job retries each
    /// HEAD on its own (`retryingHEADs`), as it does every request; a single PUT retries the attempt.
    private func objectKey(for job: UploadJob, retryingHEADs: Bool) async throws -> String {
        switch job.key {
        case .template(let context):
            return try await reserveKey(ext: job.fileExtension, context: context, retryingHEADs: retryingHEADs)
        case .fixed(let key):
            return key
        }
    }

    /// Generates keys until HEAD reports one unused. Without `retryingHEADs` each HEAD gets one try.
    private func reserveKey(ext: String, context: TemplateContext, retryingHEADs: Bool) async throws -> String {
        let headPolicy = retryingHEADs ? filePolicy : RetryPolicy(maxAttempts: 1, baseDelay: .zero, maxDelay: .zero)
        for _ in 0..<Self.maxKeyAttempts {
            let key = keyNamer.makeKey(ext: ext, context: context)
            let taken = try await Self.withRetries(policy: headPolicy, sleep: sleep) {
                try await self.destination.exists(key: key)
            }
            if !taken {
                return key
            }
        }
        throw UploadError.keyCollisionsExhausted
    }
}

extension UploadQueue {
    /// Sends one multipart job's parts: each reads its bytes, then sends them, retrying under
    /// `policy`. Runs in the job's task group, off the queue's actor.
    private nonisolated struct PartSender: Sendable {
        var destination: any Destination
        var policy: RetryPolicy
        var sleep: Sleeper
        var log: Logger
        /// For the log: the file's name.
        var name: String
        var file: URL
        var key: String
        var uploadID: String
        var partSize: Int64
        var byteCount: Int64
        var count: Int
        var progress: MultipartProgress
        /// The job's throttled `.progress` events.
        var report: @Sendable (Double) -> Void

        /// Part `number`, sent. Any failure is thrown as a `PartFailure`.
        @concurrent func send(_ number: Int) async throws -> MultipartPart {
            do {
                let range = MultipartPlan.range(ofPart: number, partSize: partSize, byteCount: byteCount)
                let data = try await UploadQueue.readPart(of: file, range: range)
                let progress = progress
                let report = report
                let etag = try await UploadQueue.withRetries(policy: policy, sleep: sleep, onRetry: { attempt, error in
                    progress.restart(part: number)
                    log("Upload: \(name) part \(number) failed, retry \(attempt): \(error.localizedDescription)")
                }) {
                    try await destination.uploadPart(key: key, uploadID: uploadID, number: number, data: data,
                                                     progress: { report(progress.sent($0, part: number)) })
                }
                return MultipartPart(number: number, etag: etag, size: Int64(data.count))
            } catch {
                throw PartFailure(number: number, count: count, error: error)
            }
        }
    }
}

/// A `ProgressThrottle` behind a lock, shared by one attempt's (or one multipart job's) progress
/// callbacks.
nonisolated final class ProgressGate: Sendable {
    private let throttle = Mutex(UploadQueue.ProgressThrottle())

    func admits(_ fraction: Double) -> Bool {
        throttle.withLock { $0.admits(fraction, at: .now) }
    }
}

/// A multipart job's progress: the bytes of completed parts plus what each in-flight part has sent
/// so far, over the file's size. Parts report from the transport's threads, so it is locked.
nonisolated final class MultipartProgress: Sendable {
    private struct Counts {
        var done: Int64 = 0
        var inFlight: [Int: Int64] = [:]
    }

    private let counts: Mutex<Counts>
    private let total: Int64

    /// `done` is the bytes of parts already sent, as a resume starts.
    init(total: Int64, done: Int64 = 0) {
        self.total = total
        counts = Mutex(Counts(done: done))
    }

    /// Adds `delta` bytes sent by part `number`, and returns the job's fraction.
    func sent(_ delta: Int64, part number: Int) -> Double {
        counts.withLock { counts in
            counts.inFlight[number, default: 0] += delta
            return fraction(counts)
        }
    }

    /// Forgets what part `number` has sent, before it is sent again.
    func restart(part number: Int) {
        counts.withLock { $0.inFlight[number] = nil }
    }

    /// Counts part `number` as done with `size` bytes, and returns the job's fraction.
    func finish(part number: Int, size: Int64) -> Double {
        counts.withLock { counts in
            counts.inFlight[number] = nil
            counts.done += size
            return fraction(counts)
        }
    }

    private func fraction(_ counts: Counts) -> Double {
        MultipartPlan.fraction(doneBytes: counts.done, inFlightBytes: counts.inFlight.values.reduce(0, +), total: total)
    }
}
