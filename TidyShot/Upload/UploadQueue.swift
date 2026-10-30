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
    nonisolated enum JobOutcome: Sendable {
        case uploaded
        case failed
        case cancelled(reservedKey: String?)
    }

    static let maxKeyAttempts = 5

    let destination: any Destination
    private let keyNamer: ObjectKeyNamer
    /// For `.data` jobs.
    private let policy: RetryPolicy
    /// For `.file` jobs.
    let filePolicy: RetryPolicy
    let scope: SecurityScope
    let sleep: Sleeper
    let plan: MultipartPlan
    /// Where a multipart job keeps its parts; with none, every job uses the single PUT.
    private let store: MultipartStore?
    let now: @Sendable () -> Date
    let log: Logger
    let events: EventHandler
    private var pending: [UploadJob] = []
    private var isDraining = false
    /// The job being processed and the task running it, so `cancel` can stop it and wait for it.
    private var current: (id: UUID, task: Task<JobOutcome, Never>)?
    var cancelledIDs: Set<UUID> = []
    /// The in-flight job's key (its fixed key, or one reserved with HEAD), reported in its
    /// `.cancelled` event if it is cancelled.
    var reservedKeys: [UUID: String] = [:]

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

    /// Aborts an upload the job no longer uses, in one try. A failure is logged and the job goes on;
    /// the bucket's lifecycle rule removes what is left.
    func abortUpload(key: String, uploadID: String, name: String) async {
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

    /// Runs `operation` until it succeeds, it throws an error `UploadError.isRetryable` refuses,
    /// or `policy` runs out of tries, sleeping with `sleep` between tries. `onRetry` gets the try
    /// about to be made (2 for the first retry) and the error that caused it.
    nonisolated static func withRetries<T>(policy: RetryPolicy, sleep: Sleeper,
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
    func throttledProgress(for id: UUID) -> @Sendable (Double) -> Void {
        let throttle = ProgressGate()
        let events = events
        return { fraction in
            guard throttle.admits(fraction) else { return }
            Task { await events(.progress(id: id, fraction: fraction)) }
        }
    }

    /// Delivers `.cancelled` with the key the job reserved (`cancel` clears the entry).
    func deliverCancelled(_ id: UUID) async -> JobOutcome {
        let key = reservedKeys[id]
        await events(.cancelled(id: id, reservedKey: key))
        return .cancelled(reservedKey: key)
    }

    /// The key for this attempt. A template key is named afresh and reserved with HEAD. A fixed key
    /// is the record's own key at its own location, and no other record points at it (the
    /// coordinator's shared-key rule checks that), so it is PUT as is on every attempt. A HEAD
    /// would find the record's own object and steer away from it. A multipart job retries each
    /// HEAD on its own (`retryingHEADs`), as it does every request; a single PUT retries the attempt.
    func objectKey(for job: UploadJob, retryingHEADs: Bool) async throws -> String {
        switch job.key {
        case .template(let context):
            return try await reserveKey(ext: job.fileExtension, context: context, retryingHEADs: retryingHEADs)
        case .fixed(let key):
            return key
        }
    }

    /// Generates keys until HEAD reports one unused. Without `retryingHEADs` each HEAD gets one try.
    func reserveKey(ext: String, context: TemplateContext, retryingHEADs: Bool) async throws -> String {
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

/// A `ProgressThrottle` behind a lock, shared by one attempt's (or one multipart job's) progress
/// callbacks.
nonisolated final class ProgressGate: Sendable {
    private let throttle = Mutex(UploadQueue.ProgressThrottle())

    func admits(_ fraction: Double) -> Bool {
        throttle.withLock { $0.admits(fraction, at: .now) }
    }
}
