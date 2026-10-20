import Foundation

/// Uploads jobs one at a time, in order, with HEAD-before-PUT key reservation and retry with
/// backoff. Reports progress and results through `events`, which runs on the main actor.
actor UploadQueue {
    typealias EventHandler = @MainActor @Sendable (UploadEvent) -> Void
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    static let maxKeyAttempts = 5

    private let destination: any Destination
    private let keyNamer: ObjectKeyNamer
    private let policy: RetryPolicy
    private let sleep: Sleeper
    private let events: EventHandler
    private var pending: [UploadJob] = []
    private var isDraining = false

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

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            await process(job)
        }
        isDraining = false
    }

    private func process(_ job: UploadJob) async {
        var attempt = 1
        while true {
            await events(.started(id: job.id, attempt: attempt))
            do {
                let key = try await reserveKey(ext: job.fileExtension, context: job.naming)
                let id = job.id
                let events = events
                try await destination.upload(job.data, key: key, contentType: job.contentType) { fraction in
                    Task { await events(.progress(id: id, fraction: fraction)) }
                }
                let url = try destination.publicURL(for: key)
                await events(.uploaded(id: job.id, url: url, key: key))
                return
            } catch {
                if UploadError.isRetryable(error), attempt < policy.maxAttempts {
                    attempt += 1
                    do {
                        try await sleep(policy.delay(beforeAttempt: attempt))
                    } catch {
                        // A cancelled backoff sleep ends the job instead of retrying.
                        await events(.failed(id: job.id, message: error.localizedDescription))
                        return
                    }
                    continue
                }
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
