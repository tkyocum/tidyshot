import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// Scripted destination: records calls, pretends some keys exist, fails a set number of times.
nonisolated final class FakeDestination: Destination, Sendable {
    struct State: Sendable {
        var existingKeys: Set<String> = []
        var failuresRemaining = 0
        var failure: UploadError = .httpStatus(503, body: "")
        var headKeys: [String] = []
        var uploads: [(key: String, data: Data, contentType: String, cacheControl: String?)] = []
        /// Every call to `upload`, including ones that throw.
        var uploadAttempts = 0
        /// The key of every call to `upload`, including ones that throw, in order.
        var attemptKeys: [String] = []
        /// This many uploads (after any scripted failures) wait a minute instead of finishing,
        /// so a test can cancel them; the wait throws `CancellationError` when the task is cancelled.
        var blockingUploadsRemaining = 0
        /// This many uploads (after any scripted failures and blocking uploads) wait for
        /// `releaseUploads(throwing:)` even when their task is cancelled, like a PUT that the server
        /// finishes just as it is cancelled.
        var holdingUploadsRemaining = 0
        /// Held uploads waiting for `releaseUploads(throwing:)`.
        var heldUploads: [CheckedContinuation<Void, any Error>] = []
        /// Set by `releaseUploads(throwing:)`; a later held upload finishes at once with this result.
        var heldUploadsRelease: Result<Void, any Error>?
        /// Times a held upload's task was cancelled while it waited.
        var heldUploadCancellations = 0
    }

    let state: Mutex<State>

    init(_ state: State = State()) {
        self.state = Mutex(state)
    }

    func exists(key: String) async throws -> Bool {
        state.withLock { $0.headKeys.append(key); return $0.existingKeys.contains(key) }
    }

    func upload(_ data: Data, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        let failure: UploadError? = state.withLock {
            $0.uploadAttempts += 1
            $0.attemptKeys.append(key)
            guard $0.failuresRemaining > 0 else { return nil }
            $0.failuresRemaining -= 1
            return $0.failure
        }
        if let failure { throw failure }
        let blocks = state.withLock {
            guard $0.blockingUploadsRemaining > 0 else { return false }
            $0.blockingUploadsRemaining -= 1
            return true
        }
        if blocks {
            try await Task.sleep(for: .seconds(60))
        }
        let holds = state.withLock {
            guard $0.holdingUploadsRemaining > 0 else { return false }
            $0.holdingUploadsRemaining -= 1
            return true
        }
        if holds {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let release: Result<Void, any Error>? = state.withLock {
                        if let release = $0.heldUploadsRelease { return release }
                        $0.heldUploads.append(continuation)
                        return nil
                    }
                    if let release { continuation.resume(with: release) }
                }
            } onCancel: {
                state.withLock { $0.heldUploadCancellations += 1 }
            }
        }
        progress(0.5)
        progress(1)
        state.withLock { $0.uploads.append((key, data, contentType, cacheControl)) }
    }

    /// Finishes every held upload, now and later: successfully, or by throwing `error`.
    func releaseUploads(throwing error: (any Error)? = nil) {
        let release: Result<Void, any Error> = error.map { .failure($0) } ?? .success(())
        let held = state.withLock {
            $0.heldUploadsRelease = release
            defer { $0.heldUploads = [] }
            return $0.heldUploads
        }
        for continuation in held { continuation.resume(with: release) }
    }

    func delete(key: String) async throws {}

    func publicURL(for key: String) throws -> URL {
        URL(string: "https://snap.tky.io/\(key)")!
    }
}

@MainActor
final class EventLog {
    var events: [UploadEvent] = []
}

nonisolated struct EventuallyTimedOut: Error, CustomStringConvertible {
    var description: String { "condition did not become true within 2 seconds" }
}

/// Polls `condition` every 10 ms for up to two seconds and throws `EventuallyTimedOut` if it
/// never holds, which fails the calling test. `async` so the condition can read actor state.
@MainActor
func eventually(_ condition: () async -> Bool) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw EventuallyTimedOut()
}

struct UploadQueueTests {
    let data = Data("png".utf8)
    let fixedKey = "shots/2026/10/aB3dE9.png"
    let fixedURL = URL(string: "https://snap.tky.io/shots/2026/10/aB3dE9.png")!

    func makeQueue(destination: FakeDestination, log: EventLog) -> UploadQueue {
        UploadQueue(destination: destination,
                    keyNamer: ObjectKeyNamer(template: "s/{random}", randomString: { String(repeating: "K", count: $0) }),
                    policy: .immediate,
                    sleep: { _ in },
                    events: { log.events.append($0) })
    }

    @Test func uploadsAndReportsPublicURL() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/s/KKKKKK.png")!, key: "s/KKKKKK.png")) }

        #expect(log.events.first == .started(id: id, attempt: 1))
        try await eventually { log.events.contains(.progress(id: id, fraction: 1)) }
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        #expect(uploads.first?.contentType == "image/png")
        #expect(uploads.first?.data == data)
    }

    @Test func keyUsesTheJobsNamingContext() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{hostname}/{date}/{counter}-{random:2}",
                                                         randomString: { String(repeating: "K", count: $0) }),
                                policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let id = UUID()
        let captured = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!
        let naming = TemplateContext(date: captured, counter: 3, hostname: "miffle")

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", naming: naming))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/miffle/2026-10-19/3-KK.png")!,
                                                              key: "miffle/2026-10-19/3-KK.png")) }
    }

    @Test func regeneratesKeyWhenHeadReturns200() async throws {
        let counter = Mutex(0)
        let destination = FakeDestination(.init(existingKeys: ["AAAAAA.png"]))
        let log = EventLog()
        let queue = UploadQueue(
            destination: destination,
            keyNamer: ObjectKeyNamer(template: "{random}", randomString: { length in
                let n = counter.withLock { $0 += 1; return $0 }
                return String(repeating: n == 1 ? "A" : "B", count: length)
            }),
            policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/BBBBBB.png")!, key: "BBBBBB.png")) }

        #expect(destination.state.withLock { $0.headKeys } == ["AAAAAA.png", "BBBBBB.png"])
    }

    @Test func givesUpAfterFiveCollisions() async throws {
        let destination = FakeDestination(.init(existingKeys: ["KKKKKK.png"]))
        let log = EventLog()
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{random}", randomString: { String(repeating: "K", count: $0) }),
                                policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.last == .failed(id: id, message: UploadError.keyCollisionsExhausted.localizedDescription) }

        #expect(destination.state.withLock { $0.headKeys.count } == 5)
        #expect(destination.state.withLock { $0.uploads.isEmpty })
    }

    @Test func retriesServerErrorsWithBackoffThenSucceeds() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 2, failure: .httpStatus(503, body: "slow down")))
        let log = EventLog()
        let sleeps = Mutex<[Duration]>([])
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{random}", randomString: { String(repeating: "K", count: $0) }),
                                policy: RetryPolicy(maxAttempts: 3, baseDelay: .seconds(1), maxDelay: .seconds(30)),
                                sleep: { duration in sleeps.withLock { $0.append(duration) } },
                                events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/KKKKKK.png")!, key: "KKKKKK.png")) }

        let starts = log.events.filter { if case .started = $0 { return true } else { return false } }
        #expect(starts == [.started(id: id, attempt: 1), .started(id: id, attempt: 2), .started(id: id, attempt: 3)])
        #expect(sleeps.withLock { $0 } == [.seconds(1), .seconds(2)])
    }

    @Test func failsAfterMaxAttempts() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 10, failure: .httpStatus(500, body: "")))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.last == .failed(id: id, message: UploadError.httpStatus(500, body: "").localizedDescription) }

        #expect(log.events.filter { if case .started = $0 { return true } else { return false } }.count == 3)
    }

    @Test func doesNotRetryClientErrors() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 10, failure: .httpStatus(403, body: "SignatureDoesNotMatch")))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { if case .failed = log.events.last { return true } else { return false } }

        #expect(log.events == [.started(id: id, attempt: 1),
                               .failed(id: id, message: "Server returned HTTP 403: SignatureDoesNotMatch")])
    }

    @Test func cancelledBackoffEmitsFailedAndStops() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 1, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{random}", randomString: { String(repeating: "K", count: $0) }),
                                policy: .immediate,
                                sleep: { _ in throw CancellationError() },
                                events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { if case .failed = log.events.last { return true } else { return false } }
        try await eventually { await queue.isIdle }

        #expect(log.events == [.started(id: id, attempt: 1),
                               .failed(id: id, message: CancellationError().localizedDescription)])
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
        #expect(destination.state.withLock { $0.uploads.isEmpty })
    }

    @Test func cancelInFlightEndsWithASingleCancelledEvent() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        let result = await queue.cancel(recordID: id)
        #expect(result == .stopped(reservedKey: "s/KKKKKK.png"))
        #expect(log.events == [.started(id: id, attempt: 1), .cancelled(id: id, reservedKey: "s/KKKKKK.png")])
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploads.isEmpty })
        #expect(log.events.count == 2)
    }

    @Test func cancelDropsAPendingJobWithoutUploadingIt() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let first = UUID()
        let second = UUID()

        await queue.enqueue(UploadJob(id: first, data: data, contentType: "image/png", fileExtension: "png"))
        await queue.enqueue(UploadJob(id: second, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        #expect(await queue.cancel(recordID: second) == .stopped(reservedKey: nil))
        #expect(log.events.contains(.cancelled(id: second, reservedKey: nil)))
        #expect(await queue.cancel(recordID: first) == .stopped(reservedKey: "s/KKKKKK.png"))
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
        #expect(!log.events.contains { if case .started(second, _) = $0 { return true } else { return false } })
    }

    @Test func cancelUnknownIDIsNotFound() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        #expect(await queue.cancel(recordID: UUID()) == .notFound)
        #expect(log.events.isEmpty)

        let id = UUID()
        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains { if case .uploaded(id, _, _) = $0 { return true } else { return false } } }
        try await eventually { await queue.isIdle }
        #expect(await queue.cancel(recordID: id) == .notFound)
    }

    @Test func cancelDuringBackoffDoesNotRetry() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 1, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let sleeping = Mutex(false)
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{random}", randomString: { String(repeating: "K", count: $0) }),
                                policy: .default,
                                sleep: { _ in
                                    sleeping.withLock { $0 = true }
                                    try await Task.sleep(for: .seconds(60))
                                },
                                events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { sleeping.withLock { $0 } }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: "KKKKKK.png"))
        #expect(log.events == [.started(id: id, attempt: 1), .cancelled(id: id, reservedKey: "KKKKKK.png")])
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
    }

    @Test func queueContinuesWithTheNextJobAfterACancel() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let first = UUID()
        let second = UUID()

        await queue.enqueue(UploadJob(id: first, data: data, contentType: "image/png", fileExtension: "png"))
        await queue.enqueue(UploadJob(id: second, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        _ = await queue.cancel(recordID: first)
        try await eventually { log.events.contains(.uploaded(id: second, url: URL(string: "https://snap.tky.io/s/KKKKKK.png")!, key: "s/KKKKKK.png")) }
        try await eventually { await queue.isIdle }
        #expect(log.events.contains(.cancelled(id: first, reservedKey: "s/KKKKKK.png")))
        #expect(destination.state.withLock { $0.uploads.count } == 1)
    }

    @Test func cancelAfterUploadCompletedReportsNotFound() async throws {
        let destination = FakeDestination(.init(holdingUploadsRemaining: 1))
        defer { destination.releaseUploads(throwing: CancellationError()) }
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

        let cancel = Task { await queue.cancel(recordID: id) }
        try await eventually { destination.state.withLock { $0.heldUploadCancellations } == 1 }
        destination.releaseUploads()

        #expect(await cancel.value == .notFound)
        try await eventually { await queue.isIdle }
        let terminal = log.events.filter { if case .progress = $0 { return false } else { return true } }
        #expect(terminal == [.started(id: id, attempt: 1),
                             .uploaded(id: id, url: URL(string: "https://snap.tky.io/s/KKKKKK.png")!, key: "s/KKKKKK.png")])
    }

    @Test func concurrentCancelsAgreeOnTheReservedKey() async throws {
        let destination = FakeDestination(.init(holdingUploadsRemaining: 1))
        defer { destination.releaseUploads(throwing: CancellationError()) }
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

        // Both tasks start on the main actor in order, so both reach the queue before the job can end.
        let first = Task { await queue.cancel(recordID: id) }
        let second = Task { await queue.cancel(recordID: id) }
        try await eventually { destination.state.withLock { $0.heldUploadCancellations } == 1 }
        destination.releaseUploads(throwing: CancellationError())

        #expect(await first.value == .stopped(reservedKey: "s/KKKKKK.png"))
        #expect(await second.value == .stopped(reservedKey: "s/KKKKKK.png"))
        try await eventually { await queue.isIdle }
        #expect(log.events == [.started(id: id, attempt: 1), .cancelled(id: id, reservedKey: "s/KKKKKK.png")])
    }

    @Test func processesJobsInOrderOneAtATime() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let first = UUID()
        let second = UUID()

        await queue.enqueue(UploadJob(id: first, data: data, contentType: "image/png", fileExtension: "png"))
        await queue.enqueue(UploadJob(id: second, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.filter { if case .uploaded = $0 { return true } else { return false } }.count == 2 }

        let ids = log.events.compactMap { event -> UUID? in
            switch event {
            case .started(let id, _), .uploaded(let id, _, _): id
            default: nil
            }
        }
        #expect(ids == [first, first, second, second])
        try await eventually { await queue.isIdle }
    }

    /// A fixed key is the record's own key at its own location, so the queue sends no HEAD. The
    /// existing initialiser still names its key from the template.
    @Test func fixedKeyJobSkipsHEAD() async throws {
        let naming = TemplateContext(date: Date(timeIntervalSince1970: 1_792_411_200), counter: 3, hostname: "miffle")
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", naming: naming).key
                == .template(naming))
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey).key
                == .fixed(fixedKey))

        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: id, url: fixedURL, key: fixedKey)) }

        #expect(log.events.first == .started(id: id, attempt: 1))
        #expect(destination.state.withLock { $0.headKeys } == [])
        #expect(destination.state.withLock { state in state.uploads.map { $0.key } } == [fixedKey])
    }

    /// HEAD would find the record's own object and steer the replace to a new key. A fixed key
    /// overwrites the object that is there.
    @Test func fixedKeyPutsExactKeyEvenWhenItExists() async throws {
        let destination = FakeDestination(.init(existingKeys: [fixedKey]))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: id, url: fixedURL, key: fixedKey)) }

        #expect(destination.state.withLock { state in state.uploads.map { $0.key } } == [fixedKey])
        #expect(destination.state.withLock { $0.headKeys } == [])
    }

    /// Every attempt PUTs the same key, so a retried replace keeps the URL.
    @Test func fixedKeyRetryReusesKey() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 2, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: id, url: fixedURL, key: fixedKey)) }

        let starts = log.events.filter { if case .started = $0 { return true } else { return false } }
        #expect(starts == [.started(id: id, attempt: 1), .started(id: id, attempt: 2), .started(id: id, attempt: 3)])
        #expect(destination.state.withLock { $0.attemptKeys } == [fixedKey, fixedKey, fixedKey])
        #expect(destination.state.withLock { $0.headKeys } == [])
    }

    /// Delete cancels an in-flight replace and must learn its key, because the PUT may have landed.
    @Test func cancelOfFixedKeyJobReportsThatKey() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: fixedKey))
        #expect(log.events == [.started(id: id, attempt: 1), .cancelled(id: id, reservedKey: fixedKey)])
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploads.isEmpty })
    }

    /// The coordinator draws a `{counter}` only for template jobs. The queue never expands the
    /// template for a fixed key, so nothing is drawn from the key namer. The template job after it
    /// uses the same namer, which shows that the zero is not vacuous.
    @Test func fixedKeyDrawsNoCounter() async throws {
        let draws = Mutex(0)
        let destination = FakeDestination()
        let log = EventLog()
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{counter}-{random}", randomString: { length in
                                    draws.withLock { $0 += 1 }
                                    return String(repeating: "K", count: length)
                                }),
                                policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let fixed = UUID()
        let template = UUID()

        await queue.enqueue(UploadJob(id: fixed, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: fixed, url: fixedURL, key: fixedKey)) }
        #expect(draws.withLock { $0 } == 0)

        let naming = TemplateContext(date: Date(timeIntervalSince1970: 1_792_411_200), counter: 7, hostname: "miffle")
        await queue.enqueue(UploadJob(id: template, data: data, contentType: "image/png", fileExtension: "png", naming: naming))
        try await eventually { log.events.contains(.uploaded(id: template, url: URL(string: "https://snap.tky.io/7-KKKKKK.png")!,
                                                              key: "7-KKKKKK.png")) }
        #expect(draws.withLock { $0 } == 1)
    }

    /// A replace sends `Cache-Control: no-cache` by default. A template job sends none.
    @Test func fixedKeyPassesCacheControl() async throws {
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey).cacheControl
                == "no-cache")
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey,
                          cacheControl: nil).cacheControl == nil)
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png").cacheControl == nil)

        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let fixed = UUID()
        let template = UUID()

        await queue.enqueue(UploadJob(id: fixed, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        await queue.enqueue(UploadJob(id: template, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.filter { if case .uploaded = $0 { return true } else { return false } }.count == 2 }

        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map { $0.key } == [fixedKey, "s/KKKKKK.png"])
        #expect(uploads.map { $0.cacheControl } == ["no-cache", nil])
    }
}
