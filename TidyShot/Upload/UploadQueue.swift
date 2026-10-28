import Foundation
import Synchronization

/// Uploads jobs one at a time, in order, with retry and backoff. A template job's key is reserved
/// with HEAD before its PUT; a fixed-key job PUTs its key as is. A large file goes multipart: its
/// parts are sent a few at a time, each request retried on its own, in one pass of the job.
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

    /// A multipart job's one pass, holding `folder`'s scope throughout: the key, Create, the parts
    /// (at most `plan.inFlight` at a time, added in part order as each finishes) and Complete.
    /// Each request retries on its own under `filePolicy`; the job as a whole is not retried. The
    /// sidecar is rewritten after each part, and marks Complete as sent before it goes.
    private func processMultipart(_ job: UploadJob, file url: URL, holding folder: URL?,
                                  source: MultipartSource, store: MultipartStore) async -> JobOutcome {
        let name = url.lastPathComponent
        let accessing = folder.map(scope.start) ?? false
        defer {
            if accessing, let folder { scope.stop(folder) }
        }
        await events(.started(id: job.id, attempt: 1, fraction: 0))
        do {
            // The coordinator refuses a file over the plan's limit, so a nil part size cannot happen.
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)),
                  let partSize = plan.partSize(for: source.byteCount) else {
                throw UploadError.fileUnreadable(name)
            }
            let key = try await objectKey(for: job, retryingHEADs: true)
            reservedKeys[job.id] = key
            let uploadID: String
            do {
                uploadID = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                    try await self.destination.createMultipartUpload(key: key, contentType: job.contentType,
                                                                     cacheControl: job.cacheControl)
                }
            } catch {
                if !cancelledIDs.contains(job.id) {
                    log("Upload: \(name) create failed: \(error.localizedDescription)")
                }
                throw error
            }
            let state = MultipartUploadState(uploadID: uploadID, key: key, location: source.location,
                                             partSize: partSize, byteCount: source.byteCount,
                                             sourceModified: source.modified, sourcePath: source.path,
                                             startedAt: now())
            var sidecar = MultipartSidecar(uploadID: uploadID, completeSent: false, parts: [])
            saveSidecar(sidecar, id: job.id, name: name, in: store)
            await events(.multipartStarted(id: job.id, state: state))
            let count = MultipartPlan.partCount(byteCount: source.byteCount, partSize: partSize)
            log("Upload: \(name) multipart, \(count) parts of \(Self.mebibytes(partSize)) MiB, upload id \(uploadID)")

            let sender = PartSender(destination: destination, policy: filePolicy, sleep: sleep, log: log,
                                    name: name, file: url, key: key, uploadID: uploadID, partSize: partSize,
                                    byteCount: source.byteCount, count: count,
                                    progress: MultipartProgress(total: source.byteCount),
                                    report: throttledProgress(for: job.id))
            try await withThrowingTaskGroup(of: MultipartPart.self) { group in
                var next = 1
                while next <= min(plan.inFlight, count) {
                    let number = next
                    group.addTask { try await sender.send(number) }
                    next += 1
                }
                while let part = try await group.next() {
                    sidecar.parts.append(part)
                    sidecar.parts.sort { $0.number < $1.number }
                    saveSidecar(sidecar, id: job.id, name: name, in: store)
                    sender.report(sender.progress.finish(part: part.number, size: part.size))
                    if next <= count {
                        let number = next
                        group.addTask { try await sender.send(number) }
                        next += 1
                    }
                }
            }

            sidecar.completeSent = true
            saveSidecar(sidecar, id: job.id, name: name, in: store)
            let parts = sidecar.parts
            try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                try await self.destination.completeMultipartUpload(key: key, uploadID: uploadID, parts: parts)
            }
            log("Upload: \(name) multipart completed")
            let publicURL = try destination.publicURL(for: key)
            reservedKeys[job.id] = nil
            await events(.uploaded(id: job.id, url: publicURL, key: key))
            return .uploaded
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

    /// A sidecar that cannot be written leaves the upload going: a resume then lists the parts.
    private func saveSidecar(_ sidecar: MultipartSidecar, id: UUID, name: String, in store: MultipartStore) {
        do {
            try store.writeSidecar(sidecar, id: id)
        } catch {
            log("Upload: \(name) part list not saved: \(error.localizedDescription)")
        }
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

    private let counts = Mutex(Counts())
    private let total: Int64

    init(total: Int64) {
        self.total = total
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
