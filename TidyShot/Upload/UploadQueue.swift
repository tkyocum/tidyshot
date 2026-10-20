import Foundation

/// Uploads jobs one at a time, in order, with HEAD-before-PUT key reservation and retry with
/// backoff. Reports progress and results through `events`, which runs on the main actor. A job
/// can be cancelled while pending or in flight; it then ends with a single `.cancelled` event.
actor UploadQueue {
    typealias EventHandler = @MainActor @Sendable (UploadEvent) -> Void
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// What `cancel(recordID:)` found.
    nonisolated enum CancelResult: Sendable, Equatable {
        /// Nothing pending or in flight had that id: it already finished (its `.uploaded` or
        /// `.failed` event has been delivered) or was never enqueued.
        case notFound
        /// The job has ended and its `.cancelled` event has been delivered. `reservedKey` is the
        /// object key the job had claimed with HEAD-before-PUT, nil when it was cancelled before
        /// that. The PUT for that key may have completed on the server just as it was cancelled,
        /// so a caller that is deleting the capture deletes this key too.
        case stopped(reservedKey: String?)
    }

    static let maxKeyAttempts = 5

    private let destination: any Destination
    private let keyNamer: ObjectKeyNamer
    private let policy: RetryPolicy
    private let sleep: Sleeper
    private let events: EventHandler
    private var pending: [UploadJob] = []
    private var isDraining = false
    /// The job being processed and the task running it, so `cancel` can stop it and wait for it.
    private var current: (id: UUID, task: Task<Void, Never>)?
    private var cancelledIDs: Set<UUID> = []
    /// Key reserved by the in-flight job, kept after a cancellation for `cancel` to report.
    private var reservedKeys: [UUID: String] = [:]

    init(destination: any Destination,
         keyNamer: ObjectKeyNamer,
         policy: RetryPolicy = .default,
         sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
         events: @escaping EventHandler) {
        self.destination = destination
        self.keyNamer = keyNamer
        self.policy = policy
        self.sleep = sleep
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
    /// that event has been delivered. Later jobs continue.
    func cancel(recordID: UUID) async -> CancelResult {
        if let index = pending.firstIndex(where: { $0.id == recordID }) {
            pending.remove(at: index)
            await events(.cancelled(id: recordID, reservedKey: nil))
            return .stopped(reservedKey: nil)
        }
        guard let current, current.id == recordID else { return .notFound }
        cancelledIDs.insert(recordID)
        current.task.cancel()
        await current.task.value
        cancelledIDs.remove(recordID)
        return .stopped(reservedKey: reservedKeys.removeValue(forKey: recordID))
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            let task = Task { await process(job) }
            current = (job.id, task)
            await task.value
            current = nil
        }
        isDraining = false
    }

    private func process(_ job: UploadJob) async {
        var attempt = 1
        while true {
            await events(.started(id: job.id, attempt: attempt))
            do {
                let key = try await reserveKey(ext: job.fileExtension, context: job.naming)
                reservedKeys[job.id] = key
                let id = job.id
                let events = events
                try await destination.upload(job.data, key: key, contentType: job.contentType) { fraction in
                    Task { await events(.progress(id: id, fraction: fraction)) }
                }
                let url = try destination.publicURL(for: key)
                reservedKeys[job.id] = nil
                await events(.uploaded(id: job.id, url: url, key: key))
                return
            } catch {
                if cancelledIDs.contains(job.id) {
                    // `reservedKeys` is left for `cancel` to report as well.
                    await events(.cancelled(id: job.id, reservedKey: reservedKeys[job.id]))
                    return
                }
                if UploadError.isRetryable(error), attempt < policy.maxAttempts {
                    attempt += 1
                    do {
                        try await sleep(policy.delay(beforeAttempt: attempt))
                    } catch {
                        if cancelledIDs.contains(job.id) {
                            await events(.cancelled(id: job.id, reservedKey: reservedKeys[job.id]))
                            return
                        }
                        // A backoff sleep that fails on its own ends the job instead of retrying.
                        reservedKeys[job.id] = nil
                        await events(.failed(id: job.id, message: error.localizedDescription))
                        return
                    }
                    continue
                }
                reservedKeys[job.id] = nil
                await events(.failed(id: job.id, message: error.localizedDescription))
                return
            }
        }
    }

    /// Generates keys until HEAD reports one unused.
    private func reserveKey(ext: String, context: TemplateContext) async throws -> String {
        for _ in 0..<Self.maxKeyAttempts {
            let key = keyNamer.makeKey(ext: ext, context: context)
            if try await destination.exists(key: key) == false {
                return key
            }
        }
        throw UploadError.keyCollisionsExhausted
    }
}
