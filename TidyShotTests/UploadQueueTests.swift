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
        var uploads: [(key: String, data: Data, contentType: String)] = []
        /// Every call to `upload`, including ones that throw.
        var uploadAttempts = 0
    }

    let state: Mutex<State>

    init(_ state: State = State()) {
        self.state = Mutex(state)
    }

    func exists(key: String) async throws -> Bool {
        state.withLock { $0.headKeys.append(key); return $0.existingKeys.contains(key) }
    }

    func upload(_ data: Data, key: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let failure: UploadError? = state.withLock {
            $0.uploadAttempts += 1
            guard $0.failuresRemaining > 0 else { return nil }
            $0.failuresRemaining -= 1
            return $0.failure
        }
        if let failure { throw failure }
        progress(0.5)
        progress(1)
        state.withLock { $0.uploads.append((key, data, contentType)) }
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
                                keyNamer: ObjectKeyNamer(template: "{app}/{date}/{counter}-{random:2}",
                                                         randomString: { String(repeating: "K", count: $0) }),
                                policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let id = UUID()
        let captured = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!
        let naming = TemplateContext(date: captured, appName: "Safari", counter: 3, hostname: "miffle")

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", naming: naming))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/Safari/2026-10-19/3-KK.png")!,
                                                              key: "Safari/2026-10-19/3-KK.png")) }
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
}
