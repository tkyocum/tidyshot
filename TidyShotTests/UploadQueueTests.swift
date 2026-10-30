import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// Counts security-scope starts and stops, per folder, in order.
nonisolated final class FakeSecurityScope: Sendable {
    let calls = Mutex<[String]>([])

    var scope: UploadQueue.SecurityScope {
        UploadQueue.SecurityScope(
            start: { url in self.calls.withLock { $0.append("start \(url.lastPathComponent)") }; return true },
            stop: { url in self.calls.withLock { $0.append("stop \(url.lastPathComponent)") } })
    }

    var starts: Int { calls.withLock { $0.count { $0.hasPrefix("start") } } }
    var stops: Int { calls.withLock { $0.count { $0.hasPrefix("stop") } } }
}

/// The queue's `Upload:` log lines, in order.
nonisolated final class LogLines: Sendable {
    let lines = Mutex<[String]>([])
}

/// The backoff sleeps a queue asked for, recorded instead of waited.
nonisolated final class SleepLog: Sendable {
    let durations = Mutex<[Duration]>([])
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

        #expect(log.events.first == .started(id: id, attempt: 1, fraction: 0))
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
        #expect(starts == [.started(id: id, attempt: 1, fraction: 0), .started(id: id, attempt: 2, fraction: 0), .started(id: id, attempt: 3, fraction: 0)])
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

        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0),
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

        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0),
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
        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: "s/KKKKKK.png")])
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
        #expect(!log.events.contains { if case .started(second, _, _) = $0 { return true } else { return false } })
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
        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: "KKKKKK.png")])
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
        #expect(terminal == [.started(id: id, attempt: 1, fraction: 0),
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
        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: "s/KKKKKK.png")])
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
            case .started(let id, _, _), .uploaded(let id, _, _): id
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

        #expect(log.events.first == .started(id: id, attempt: 1, fraction: 0))
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
        #expect(starts == [.started(id: id, attempt: 1, fraction: 0), .started(id: id, attempt: 2, fraction: 0), .started(id: id, attempt: 3, fraction: 0)])
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
        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: fixedKey)])
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

    // MARK: Files

    /// A fresh folder holding `Recording.mp4`; the caller removes the folder.
    func makeMovie() throws -> (folder: URL, file: URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "UploadQueueTests-\(UUID().uuidString)",
                                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Recording.mp4")
        try Data("mp4".utf8).write(to: file)
        return (folder, file)
    }

    /// The app's policies (`.default` for data, `.file` for files), with the sleeps recorded
    /// instead of waited.
    func makeAppQueue(destination: FakeDestination, log: EventLog, scope: FakeSecurityScope = FakeSecurityScope(),
                      sleeps: SleepLog = SleepLog()) -> UploadQueue {
        UploadQueue(destination: destination,
                    keyNamer: ObjectKeyNamer(template: "s/{random}", randomString: { String(repeating: "K", count: $0) }),
                    scope: scope.scope,
                    sleep: { duration in sleeps.durations.withLock { $0.append(duration) } },
                    events: { log.events.append($0) })
    }

    func movieJob(_ id: UUID, file: URL, scope: URL?) -> UploadJob {
        UploadJob(id: id, payload: .file(file, scope: scope), contentType: "video/mp4", fileExtension: "mp4")
    }

    func starts(in log: EventLog) -> [UploadEvent] {
        log.events.filter { if case .started = $0 { return true } else { return false } }
    }

    @Test func fileJobUploadsFromTheFileWithItsTypeAndExtension() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeAppQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(movieJob(id, file: movie.file, scope: nil))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/s/KKKKKK.mp4")!,
                                                              key: "s/KKKKKK.mp4")) }

        let uploads = destination.state.withLock { $0.fileUploads }
        #expect(uploads.map(\.key) == ["s/KKKKKK.mp4"])
        #expect(uploads.map(\.url) == [movie.file])
        #expect(uploads.map(\.contentType) == ["video/mp4"])
        #expect(uploads.map(\.cacheControl) == [nil])
        #expect(destination.state.withLock { $0.uploads.isEmpty })
        #expect(destination.state.withLock { $0.headKeys } == ["s/KKKKKK.mp4"])
    }

    @Test func fileJobWithAFixedKeyPutsThatKey() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeAppQueue(destination: destination, log: log)
        let id = UUID()
        let key = "shots/2026/10/aB3dE9.mp4"

        await queue.enqueue(UploadJob(id: id, payload: .file(movie.file, scope: nil), contentType: "video/mp4",
                                      fileExtension: "mp4", fixedKey: key))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/\(key)")!, key: key)) }

        #expect(destination.state.withLock { $0.fileUploads.map(\.cacheControl) } == ["no-cache"])
        #expect(destination.state.withLock { $0.headKeys }.isEmpty)
    }

    @Test func fileJobRetryResendsFromTheFile() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(failuresRemaining: 2, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let queue = makeAppQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(movieJob(id, file: movie.file, scope: nil))
        try await eventually { log.events.contains { if case .uploaded(id, _, _) = $0 { return true } else { return false } } }

        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 0), .started(id: id, attempt: 2, fraction: 0), .started(id: id, attempt: 3, fraction: 0)])
        #expect(destination.state.withLock { $0.attemptFiles } == [movie.file, movie.file, movie.file])
        #expect(destination.state.withLock { $0.uploads.isEmpty })
    }

    /// The scope is held for each attempt only: started before `upload(fileAt:)` and stopped when
    /// it returns or throws, so a job in backoff holds nothing.
    @Test func fileJobHoldsTheScopeOncePerAttempt() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(failuresRemaining: 2, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let scope = FakeSecurityScope()
        let queue = makeAppQueue(destination: destination, log: log, scope: scope)
        let id = UUID()
        let folderName = movie.folder.lastPathComponent

        await queue.enqueue(movieJob(id, file: movie.file, scope: movie.folder))
        try await eventually { log.events.contains { if case .uploaded(id, _, _) = $0 { return true } else { return false } } }

        let pair = ["start \(folderName)", "stop \(folderName)"]
        #expect(scope.calls.withLock { $0 } == pair + pair + pair)
    }

    /// Every attempt of a job that fails for good still stops what it started.
    @Test func failingFileJobStopsTheScopeAfterEveryAttempt() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(failuresRemaining: 10, failure: .httpStatus(500, body: "")))
        let log = EventLog()
        let scope = FakeSecurityScope()
        let queue = makeAppQueue(destination: destination, log: log, scope: scope)
        let id = UUID()

        await queue.enqueue(movieJob(id, file: movie.file, scope: movie.folder))
        try await eventually { if case .failed = log.events.last { return true } else { return false } }

        #expect(scope.starts == 6)
        #expect(scope.stops == 6)
    }

    @Test func fileJobWithoutAScopeStartsNothing() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(failuresRemaining: 1, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let scope = FakeSecurityScope()
        let queue = makeAppQueue(destination: destination, log: log, scope: scope)
        let id = UUID()

        await queue.enqueue(movieJob(id, file: movie.file, scope: nil))
        try await eventually { log.events.contains { if case .uploaded(id, _, _) = $0 { return true } else { return false } } }

        #expect(scope.calls.withLock { $0 }.isEmpty)
    }

    /// A data job never touches a scope.
    @Test func dataJobStartsNoScope() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let scope = FakeSecurityScope()
        let queue = makeAppQueue(destination: destination, log: log, scope: scope)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains { if case .uploaded(id, _, _) = $0 { return true } else { return false } } }

        #expect(scope.calls.withLock { $0 }.isEmpty)
    }

    /// The policy comes from the payload: a file gets six attempts and about a minute of waits,
    /// data keeps three.
    @Test func fileJobRetriesSixTimesWhileDataGivesUpAfterThree() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(failuresRemaining: 100, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let sleeps = SleepLog()
        let queue = makeAppQueue(destination: destination, log: log, sleeps: sleeps)
        let file = UUID()
        let image = UUID()

        await queue.enqueue(movieJob(file, file: movie.file, scope: nil))
        try await eventually { log.events.contains { if case .failed(file, _) = $0 { return true } else { return false } } }
        #expect(starts(in: log).count == 6)
        #expect(sleeps.durations.withLock { $0 } == [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)])

        log.events = []
        sleeps.durations.withLock { $0 = [] }
        await queue.enqueue(UploadJob(id: image, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains { if case .failed(image, _) = $0 { return true } else { return false } } }
        #expect(starts(in: log).count == 3)
        #expect(sleeps.durations.withLock { $0 } == [.seconds(1), .seconds(2)])
    }

    /// Delete during the hash: the job ends with `.cancelled`, never `.failed`, and the scope it
    /// held is stopped.
    @Test func cancelDuringTheHashDeliversCancelled() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(blockingHashesRemaining: 1))
        let log = EventLog()
        let scope = FakeSecurityScope()
        let queue = makeAppQueue(destination: destination, log: log, scope: scope)
        let id = UUID()

        await queue.enqueue(movieJob(id, file: movie.file, scope: movie.folder))
        try await eventually { destination.state.withLock { $0.isHashing } }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: "s/KKKKKK.mp4"))
        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: "s/KKKKKK.mp4")])
        try await eventually { await queue.isIdle }
        #expect(scope.starts == 1)
        #expect(scope.stops == 1)
        #expect(destination.state.withLock { $0.fileUploads.isEmpty })
    }

    /// A file that cannot be opened inside the hold fails at once and is not retried.
    @Test func unreadableFileFailsAtOnce() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let gone = movie.folder.appending(path: "gone.mp4")
        let destination = FakeDestination()
        let log = EventLog()
        let scope = FakeSecurityScope()
        let queue = makeAppQueue(destination: destination, log: log, scope: scope)
        let id = UUID()

        await queue.enqueue(movieJob(id, file: gone, scope: movie.folder))
        try await eventually { if case .failed = log.events.last { return true } else { return false } }

        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0),
                               .failed(id: id, message: UploadError.fileUnreadable("gone.mp4").localizedDescription)])
        #expect(destination.state.withLock { $0.attemptFiles }.isEmpty)
        let folderName = movie.folder.lastPathComponent
        #expect(scope.calls.withLock { $0 } == ["start \(folderName)", "stop \(folderName)"])
    }

    // MARK: Progress

    /// Feeds `fractions` at the given milliseconds after a start and returns which passed.
    func admitted(_ fractions: [(Double, Int)]) -> [Double] {
        var throttle = UploadQueue.ProgressThrottle()
        let start = ContinuousClock.now
        return fractions.compactMap { fraction, milliseconds in
            throttle.admits(fraction, at: start + .milliseconds(milliseconds)) ? fraction : nil
        }
    }

    @Test func throttleAdmitsOnlyTheFirstFractionWithinAnInterval() {
        #expect(admitted([(0.1, 0), (0.2, 40), (0.3, 99)]) == [0.1])
    }

    @Test func throttleAlwaysAdmitsTheEnd() {
        #expect(admitted([(0.9, 0), (1, 1), (1, 2)]) == [0.9, 1, 1])
    }

    @Test func throttleAdmitsAFractionOneIntervalLater() {
        #expect(UploadQueue.ProgressThrottle.interval == .milliseconds(100))
        #expect(admitted([(0.1, 0), (0.2, 50), (0.3, 100), (0.4, 150), (0.5, 200)]) == [0.1, 0.3, 0.5])
    }

    /// Progress goes through the throttle: a burst of fractions reaches the coordinator as the
    /// first and the last.
    @Test func progressIsThrottled() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(progressFractions: (1...9).map { Double($0) / 10 } + [1]))
        let log = EventLog()
        let queue = makeAppQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(movieJob(id, file: movie.file, scope: nil))
        try await eventually { log.events.contains(.progress(id: id, fraction: 1)) }
        try await eventually { log.events.contains(.progress(id: id, fraction: 0.1)) }

        let fractions = log.events.compactMap { event -> Double? in
            if case .progress(_, let fraction) = event { return fraction } else { return nil }
        }
        // All ten arrive within microseconds; only a stalled thread would let a third through.
        #expect(fractions.count < 10)
    }

    // MARK: Multipart

    /// 1 MiB threshold, 256 KiB parts, 3 at a time.
    let smallPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 3)
    let lane = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                              bucket: "snap.tky.io", usePathStyle: true)
    let createdAt = Date(timeIntervalSinceReferenceDate: 783_456_789)
    let modified = Date(timeIntervalSinceReferenceDate: 783_400_000.1234567)
    let templateKey = "s/KKKKKK.mp4"
    let templateURL = URL(string: "https://snap.tky.io/s/KKKKKK.mp4")!
    let mib: Int64 = 1_048_576

    /// A fresh folder holding a sparse `Recording.mp4` of `byteCount` bytes, and a store in its
    /// `multipart` folder; the caller removes the folder.
    func makeLargeMovie(byteCount: Int64) throws -> (folder: URL, file: URL, store: MultipartStore) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "UploadQueueTests-\(UUID().uuidString)",
                                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Recording.mp4")
        #expect(FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(byteCount))
        try handle.close()
        return (folder, file, MultipartStore(directory: folder.appending(path: "multipart", directoryHint: .isDirectory)))
    }

    /// A `.file` job carrying its source, so the queue can send it multipart.
    func largeJob(_ id: UUID, file: URL, byteCount: Int64, scope: URL? = nil, fixedKey: String? = nil) -> UploadJob {
        var job = fixedKey.map {
            UploadJob(id: id, payload: .file(file, scope: scope), contentType: "video/mp4", fileExtension: "mp4", fixedKey: $0)
        } ?? movieJob(id, file: file, scope: scope)
        job.multipartSource = MultipartSource(location: lane, path: file.path(percentEncoded: false),
                                              byteCount: byteCount, modified: modified)
        return job
    }

    /// The small plan, immediate retries for both policies, and the log lines collected. `events`
    /// runs before each event is logged.
    func makeMultipartQueue(destination: FakeDestination, log: EventLog, store: MultipartStore?,
                            lines: LogLines = LogLines(), scope: FakeSecurityScope = FakeSecurityScope(),
                            plan: MultipartPlan? = nil,
                            events: @escaping @MainActor @Sendable (UploadEvent) -> Void = { _ in }) -> UploadQueue {
        let createdAt = createdAt
        return UploadQueue(destination: destination,
                           keyNamer: ObjectKeyNamer(template: "s/{random}", randomString: { String(repeating: "K", count: $0) }),
                           policy: .immediate, filePolicy: .immediate, scope: scope.scope, sleep: { _ in },
                           plan: plan ?? smallPlan, store: store, now: { createdAt },
                           log: { line in lines.lines.withLock { $0.append(line) } },
                           events: { event in
                               events(event)
                               log.events.append(event)
                           })
    }

    func hasEnded(_ log: EventLog) -> Bool {
        log.events.contains { event in
            switch event {
            case .uploaded, .failed, .cancelled: true
            default: false
            }
        }
    }

    func failures(in log: EventLog) -> [String] {
        log.events.compactMap { event -> String? in
            if case .failed(_, let message) = event { return message } else { return nil }
        }
    }

    func partNumbers(_ destination: FakeDestination) -> [Int] {
        destination.state.withLock { $0.parts.map(\.number) }.sorted()
    }

    func expectedParts(_ count: Int, size: Int64 = 262_144) -> [MultipartPart] {
        (1...count).map { MultipartPart(number: $0, etag: "\"etag-\($0)\"", size: size) }
    }

    @Test func aFileAtTheThresholdGoesMultipart() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination()
        let log = EventLog()
        let lines = LogLines()
        let scope = FakeSecurityScope()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines, scope: scope)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib, scope: movie.folder))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }
        try await eventually { await queue.isIdle }

        let state = MultipartUploadState(uploadID: "upload-1", key: templateKey, location: lane, partSize: 262_144,
                                         byteCount: mib, sourceModified: modified,
                                         sourcePath: movie.file.path(percentEncoded: false), startedAt: createdAt)
        #expect(log.events.filter { if case .progress = $0 { return false } else { return true } }
                == [.started(id: id, attempt: 1, fraction: 0), .multipartStarted(id: id, state: state),
                    .uploaded(id: id, url: templateURL, key: templateKey)])
        let creates = destination.state.withLock { $0.creates }
        #expect(creates.map(\.key) == [templateKey])
        #expect(creates.map(\.contentType) == ["video/mp4"])
        #expect(creates.map(\.cacheControl) == [nil])
        #expect(destination.state.withLock { $0.parts.map(\.uploadID) } == Array(repeating: "upload-1", count: 4))
        #expect(destination.state.withLock { $0.parts.map(\.size) } == Array(repeating: 262_144, count: 4))
        #expect(partNumbers(destination) == [1, 2, 3, 4])
        let completes = destination.state.withLock { $0.completes }
        #expect(completes.map(\.key) == [templateKey])
        #expect(completes.map(\.uploadID) == ["upload-1"])
        #expect(completes.first?.parts == expectedParts(4))
        #expect(destination.state.withLock { $0.fileUploads.isEmpty && $0.uploadAttempts == 0 })
        #expect(lines.lines.withLock { $0 } == ["Upload: Recording.mp4 multipart, 4 parts of 0.25 MiB, upload id upload-1",
                                                "Upload: Recording.mp4 multipart completed"])
        // One hold covers the whole attempt.
        let folderName = movie.folder.lastPathComponent
        #expect(scope.calls.withLock { $0 } == ["start \(folderName)", "stop \(folderName)"])
    }

    @Test func aFileOneByteUnderTheThresholdUsesTheSinglePUT() async throws {
        let movie = try makeLargeMovie(byteCount: mib - 1)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib - 1))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        #expect(log.events.first == .started(id: id, attempt: 1, fraction: 0))
        #expect(destination.state.withLock { $0.fileUploads.map(\.url) } == [movie.file])
        #expect(destination.state.withLock { $0.calls }.isEmpty)
    }

    /// A job needs both the store and its source to go multipart.
    @Test func withoutAStoreOrASourceALargeFileUsesTheSinglePUT() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination()
        let log = EventLog()
        let noStore = makeMultipartQueue(destination: destination, log: log, store: nil)
        let noSource = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let first = UUID()
        let second = UUID()

        await noStore.enqueue(largeJob(first, file: movie.file, byteCount: 2 * mib))
        await noSource.enqueue(movieJob(second, file: movie.file, scope: nil))
        try await eventually { log.events.filter { if case .uploaded = $0 { return true } else { return false } }.count == 2 }

        #expect(destination.state.withLock { $0.fileUploads.count } == 2)
        #expect(destination.state.withLock { $0.calls }.isEmpty)
    }

    /// The fake counts the parts in flight; each part starts only once all but 2 of the parts before
    /// it have answered, so they start in part order.
    @Test func partsAreSentThreeAtATimeInPartOrder() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(partDelay: .milliseconds(30)))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: 2 * mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        #expect(destination.state.withLock { $0.maxPartsInFlight } == 3)
        #expect(partNumbers(destination) == Array(1...8))
        #expect(Set(destination.state.withLock { $0.parts.prefix(3).map(\.number) }) == [1, 2, 3])
        let answered = destination.state.withLock { $0.answeredAtStart }
        for number in 4...8 {
            #expect((answered[number]?.first ?? -1) >= number - 3, "part \(number)")
        }
        #expect(destination.state.withLock { $0.completes.first?.parts } == expectedParts(8))
    }

    @Test func aFailingPartRetriesAloneWhileTheOthersFinish() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(partFailures: [3: [.httpStatus(503, body: ""), .httpStatus(503, body: "")]],
                                                partDelay: .milliseconds(20)))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: 2 * mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        let calls = destination.state.withLock { $0.parts.map(\.number) }
        #expect(calls.count { $0 == 3 } == 3)
        for number in [1, 2, 4, 5, 6, 7, 8] {
            #expect(calls.count { $0 == number } == 1, "part \(number)")
        }
        // Parts 1 and 2 answered while part 3 was still being retried.
        let sent = destination.state.withLock { $0.sentParts }
        #expect(sent.prefix { $0 != 3 }.count >= 2)
        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 0)])
        #expect(destination.state.withLock { $0.creates.count } == 1)
        #expect(destination.state.withLock { $0.completes.first?.parts } == expectedParts(8))
        #expect(lines.lines.withLock { $0 }.filter { $0.contains("failed") }
                == ["Upload: Recording.mp4 part 3 failed, retry 2: Server returned HTTP 503.",
                    "Upload: Recording.mp4 part 3 failed, retry 3: Server returned HTTP 503."])
    }

    /// No job-level retry: the job fails after one pass, and the sidecar keeps the parts done.
    @Test func aPartOutOfTriesFailsTheJob() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let failure = UploadError.httpStatus(503, body: "")
        let destination = FakeDestination(.init(partFailures: [3: [failure, failure, failure]], partDelay: .milliseconds(20)))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: 2 * mib))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(failures(in: log) == ["Part 3 of 8: Server returned HTTP 503."])
        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 0)])
        #expect(destination.state.withLock { $0.creates.count } == 1)
        #expect(destination.state.withLock { $0.completes.isEmpty })
        #expect(destination.state.withLock { $0.partsInFlight } == 0)
        let sidecar = try #require(movie.store.readSidecar(id: id, uploadID: "upload-1"))
        let sent = Set(destination.state.withLock { $0.sentParts })
        #expect(!sidecar.completeSent)
        #expect(!sidecar.parts.isEmpty)
        #expect(!sidecar.parts.contains { $0.number == 3 })
        #expect(sidecar.parts.allSatisfy { sent.contains($0.number) && $0.etag == "\"etag-\($0.number)\"" && $0.size == 262_144 })
        #expect(sidecar.parts.map(\.number) == sidecar.parts.map(\.number).sorted())
    }

    @Test func createRetriesUnderThePolicy() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(createFailures: [.httpStatus(503, body: ""), .noHTTPResponse]))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        #expect(destination.state.withLock { $0.creates.count } == 3)
        #expect(Set(destination.state.withLock { $0.parts.map(\.uploadID) }) == ["upload-3"])
        #expect(destination.state.withLock { $0.headKeys } == [templateKey])
    }

    @Test func aCreateOutOfTriesFailsTheJob() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let failure = UploadError.httpStatus(503, body: "")
        let destination = FakeDestination(.init(createFailures: [failure, failure, failure]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }

        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .failed(id: id, message: "Server returned HTTP 503.")])
        #expect(destination.state.withLock { $0.creates.count } == 3)
        #expect(destination.state.withLock { $0.parts.isEmpty })
        #expect(lines.lines.withLock { $0 } == ["Upload: Recording.mp4 create failed: Server returned HTTP 503."])
        #expect(movie.store.readSidecar(id: id, uploadID: "upload-3") == nil)
    }

    /// A Create refused for good is not retried.
    @Test func aCreateRefusedFailsAtOnce() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(createFailures: [.httpStatus(403, body: "AccessDenied: Access Denied")]))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }

        #expect(failures(in: log) == ["Server returned HTTP 403: AccessDenied: Access Denied"])
        #expect(destination.state.withLock { $0.creates.count } == 1)
    }

    @Test func completeRetriesUnderThePolicy() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(completeFailures: [.httpStatus(500, body: ""), .noHTTPResponse]))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        let completes = destination.state.withLock { $0.completes }
        #expect(completes.count == 3)
        #expect(completes.allSatisfy { $0.parts == expectedParts(4) })
    }

    @Test func aRetryableCompleteErrorRetriesThenCompletes() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(completeFailures: [.completeError(code: "SlowDown",
                                                                                  body: "SlowDown: Please reduce your request rate.")]))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        #expect(destination.state.withLock { $0.completes.count } == 2)
    }

    @Test func anEntityTooLargeCompleteErrorFailsTheJob() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let error = UploadError.completeError(code: "EntityTooLarge", body: "EntityTooLarge: Your proposed upload exceeds the maximum allowed size")
        let destination = FakeDestination(.init(completeFailures: [error]))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }

        #expect(failures(in: log)
                == ["The server could not complete the upload: EntityTooLarge: Your proposed upload exceeds the maximum allowed size"])
        #expect(destination.state.withLock { $0.completes.count } == 1)
    }

    /// The cancel stops every part, and waits for each, before the one `.cancelled` is delivered.
    @Test func aCancelDuringThePartsWaitsForEveryPart() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(partDelay: .seconds(60), cancelLinger: 0.05))
        let log = EventLog()
        let inFlightAtCancel = Mutex<[Int]>([])
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, events: { event in
            if case .cancelled = event {
                let inFlight = destination.state.withLock { $0.partsInFlight }
                inFlightAtCancel.withLock { $0.append(inFlight) }
            }
        })
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: 2 * mib))
        try await eventually { destination.state.withLock { $0.partsInFlight } == 3 }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: templateKey))
        try await eventually { await queue.isIdle }
        #expect(inFlightAtCancel.withLock { $0 } == [0])
        #expect(log.events.filter { if case .cancelled = $0 { return true } else { return false } }
                == [.cancelled(id: id, reservedKey: templateKey)])
        #expect(failures(in: log).isEmpty)
        #expect(destination.state.withLock { $0.parts.count } == 3)
        #expect(destination.state.withLock { $0.completes.isEmpty })
        // The upload's state stays for a Retry.
        #expect(movie.store.readSidecar(id: id, uploadID: "upload-1") == MultipartSidecar(uploadID: "upload-1",
                                                                                          completeSent: false, parts: []))
    }

    /// `multipartStarted` is delivered before any part goes; the sidecar names the upload id from
    /// the start, gains each part before the part 3 places later starts, and marks Complete sent
    /// before it goes.
    @Test func theStateIsDeliveredFirstAndTheSidecarFollowsEachPart() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let store = movie.store
        let snapshots = Mutex<[(call: String, sidecar: MultipartSidecar?)]>([])
        let destination = FakeDestination(.init(onCall: { call in
            let sidecar = store.readSidecar(id: id, uploadID: "upload-1")
            snapshots.withLock { $0.append((call, sidecar)) }
        }, partDelay: .milliseconds(10)))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: store, events: { event in
            if case .multipartStarted = event {
                destination.state.withLock { $0.calls.append("multipartStarted") }
            }
        })

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: 2 * mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        let calls = destination.state.withLock { $0.calls }
        #expect(Array(calls.prefix(2)) == ["create", "multipartStarted"])
        #expect(calls.last == "complete")
        for (call, sidecar) in snapshots.withLock({ $0 }) {
            guard call.hasPrefix("part "), let number = Int(call.dropFirst(5)) else { continue }
            #expect(sidecar?.completeSent == false, "\(call)")
            #expect((sidecar?.parts.count ?? -1) >= number - 3, "\(call)")
        }
        let atComplete = snapshots.withLock { all in all.last { $0.call == "complete" }?.sidecar }
        #expect(atComplete == MultipartSidecar(uploadID: "upload-1", completeSent: true, parts: expectedParts(8)))
        #expect(store.readSidecar(id: id, uploadID: "upload-1") == atComplete)
    }

    /// Replaces the store's folder with a plain file, so every sidecar write after this fails.
    nonisolated static func blockSidecarWrites(in store: MultipartStore) {
        try? FileManager.default.removeItem(at: store.directory)
        FileManager.default.createFile(atPath: store.directory.path(percentEncoded: false), contents: Data())
    }

    /// A sidecar that cannot be written after Create fails the job before any part goes, with the
    /// write's error and no log line of its own.
    @Test func aSidecarUnwritableAtCreateFailsTheJob() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let store = movie.store
        let destination = FakeDestination(.init(onCall: { call in
            if call == "create" { Self.blockSidecarWrites(in: store) }
        }))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: store, lines: lines)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(failures(in: log).count == 1)
        #expect(destination.state.withLock { $0.calls } == ["create"])
        #expect(!log.events.contains { if case .uploaded = $0 { return true } else { return false } })
        #expect(lines.lines.withLock { $0 }.allSatisfy { !$0.contains("not saved") })
    }

    /// A sidecar that cannot be written once parts are going fails the job before Complete, so
    /// Complete never goes without `completeSent` stored.
    @Test func aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let store = movie.store
        let destination = FakeDestination(.init(onCall: { call in
            if call == "part 4" { Self.blockSidecarWrites(in: store) }
        }))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: store, lines: lines)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(failures(in: log).count == 1)
        #expect(destination.state.withLock { $0.completes.isEmpty })
        #expect(destination.state.withLock { $0.partsInFlight } == 0)
        #expect(!log.events.contains { if case .uploaded = $0 { return true } else { return false } })
        #expect(lines.lines.withLock { $0 }.allSatisfy { !$0.contains("not saved") && !$0.contains("completed") })
    }

    /// The key is reserved once, before Create, and every part and Complete use it. A HEAD that
    /// fails is retried on its own.
    @Test func aTemplateKeyIsReservedOncePerUploadID() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination(.init(headFailures: [.httpStatus(503, body: "")]))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: 2 * mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

        #expect(destination.state.withLock { $0.headKeys } == [templateKey, templateKey])
        #expect(destination.state.withLock { $0.creates.map(\.key) } == [templateKey])
        #expect(destination.state.withLock { $0.completes.map(\.key) } == [templateKey])
    }

    /// A fixed key gets no HEAD, and its `Cache-Control` goes on Create.
    @Test func aFixedKeyCreatesAtThatKey() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()
        let key = "shots/2026/10/aB3dE9.mp4"

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib, fixedKey: key))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/\(key)")!, key: key)) }

        #expect(destination.state.withLock { $0.headKeys }.isEmpty)
        let creates = destination.state.withLock { $0.creates }
        #expect(creates.map(\.key) == [key])
        #expect(creates.map(\.cacheControl) == ["no-cache"])
    }

    /// With one part at a time the first fraction is half a part's bytes, sent and not yet done.
    @Test func theFractionCountsInFlightBytesAndEndsAtOne() async throws {
        let movie = try makeLargeMovie(byteCount: 2 * mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store,
                                       plan: MultipartPlan(threshold: mib, partSize: 262_144, inFlight: 1))
        let id = UUID()

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: 2 * mib))
        try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }
        try await eventually { log.events.contains(.progress(id: id, fraction: 1)) }

        let fractions = log.events.compactMap { event -> Double? in
            if case .progress(_, let fraction) = event { return fraction } else { return nil }
        }
        #expect(fractions.contains(0.0625))
        #expect(fractions.allSatisfy { (0...1).contains($0) })
    }

    @Test func multipartProgressAddsDoneAndInFlightBytes() {
        let progress = MultipartProgress(total: 1000)
        #expect(progress.sent(100, part: 1) == 0.1)
        #expect(progress.sent(50, part: 2) == 0.15)
        #expect(progress.sent(150, part: 1) == 0.3)
        #expect(progress.finish(part: 1, size: 400) == 0.45)
        // A retried part starts its count again.
        progress.restart(part: 2)
        #expect(progress.sent(10, part: 2) == 0.41)
        #expect(progress.finish(part: 2, size: 400) == 0.8)
        #expect(progress.sent(300, part: 3) == 1)
        #expect(progress.finish(part: 3, size: 200) == 1)
    }

    @Test func readPartReadsItsRange() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let bytes = Data((0..<200).map { UInt8($0) })
        try bytes.write(to: movie.file)

        #expect(try await UploadQueue.readPart(of: movie.file, range: 0..<64) == bytes.prefix(64))
        #expect(try await UploadQueue.readPart(of: movie.file, range: 128..<200) == bytes.subdata(in: 128..<200))
    }

    /// A file that shrank, or is gone, cannot give the part's bytes.
    @Test func readPartOfAShortOrMissingFileIsUnreadable() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }

        await #expect(throws: UploadError.fileUnreadable("Recording.mp4")) {
            try await UploadQueue.readPart(of: movie.file, range: 0..<64)
        }
        await #expect(throws: UploadError.fileUnreadable("gone.mp4")) {
            try await UploadQueue.readPart(of: movie.folder.appending(path: "gone.mp4"), range: 0..<1)
        }
    }

    /// A file gone before the pass starts fails it before any request.
    @Test func anUnreadableLargeFileFailsBeforeCreate() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let gone = movie.folder.appending(path: "gone.mp4")
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
        let id = UUID()

        await queue.enqueue(largeJob(id, file: gone, byteCount: mib))
        try await eventually { hasEnded(log) }

        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0),
                               .failed(id: id, message: UploadError.fileUnreadable("gone.mp4").localizedDescription)])
        #expect(destination.state.withLock { $0.calls }.isEmpty)
        #expect(destination.state.withLock { $0.headKeys }.isEmpty)
    }

    // MARK: Resume and restarts

    let storedKey = "s/STORED.mp4"
    let storedURL = URL(string: "https://snap.tky.io/s/STORED.mp4")!
    let replaceKey = "shots/2026/10/aB3dE9.mp4"
    let replaceURL = URL(string: "https://snap.tky.io/shots/2026/10/aB3dE9.mp4")!

    /// The state a job made at Create, as `multipartStarted` carries it.
    func createdState(_ uploadID: String, key: String, file: URL, byteCount: Int64 = 1_048_576) -> MultipartUploadState {
        MultipartUploadState(uploadID: uploadID, key: key, location: lane, partSize: 262_144, byteCount: byteCount,
                             sourceModified: modified, sourcePath: file.path(percentEncoded: false), startedAt: createdAt)
    }

    /// A job that resumes `stored-1` at `storedKey` (a template job), or at `fixedKey`.
    func resumeJob(_ id: UUID, file: URL, byteCount: Int64 = 1_048_576, fixedKey: String? = nil) -> UploadJob {
        var job = largeJob(id, file: file, byteCount: byteCount, fixedKey: fixedKey)
        job.resume = createdState("stored-1", key: fixedKey ?? storedKey, file: file, byteCount: byteCount)
        return job
    }

    func part(_ number: Int, size: Int64 = 262_144, etag: String? = nil) -> MultipartPart {
        MultipartPart(number: number, etag: etag ?? "\"etag-\(number)\"", size: size)
    }

    func withoutProgress(_ log: EventLog) -> [UploadEvent] {
        log.events.filter { if case .progress = $0 { return false } else { return true } }
    }

    /// The queue's log lines without the `Upload: Recording.mp4 ` in front.
    func logged(_ lines: LogLines) -> [String] {
        lines.lines.withLock { $0 }.map { $0.replacingOccurrences(of: "Upload: Recording.mp4 ", with: "") }
    }

    func created(_ uploadID: String) -> String {
        "multipart, 4 parts of 0.25 MiB, upload id \(uploadID)"
    }

    /// The sidecar's parts are not sent again, and the bar starts at their fraction. The stored
    /// template key is HEADed first and found free.
    @Test func aResumeSendsOnlyTheMissingParts() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        try movie.store.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: false, parts: [part(1), part(2)]), id: id)
        let destination = FakeDestination()
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(withoutProgress(log) == [.started(id: id, attempt: 1, fraction: 0.5),
                                         .uploaded(id: id, url: storedURL, key: storedKey)])
        #expect(destination.state.withLock { $0.objectSizeKeys } == [storedKey])
        #expect(destination.state.withLock { $0.headKeys }.isEmpty)
        #expect(destination.state.withLock { $0.creates.isEmpty })
        #expect(destination.state.withLock { $0.parts.map(\.uploadID) } == ["stored-1", "stored-1"])
        #expect(partNumbers(destination) == [3, 4])
        let completes = destination.state.withLock { $0.completes }
        #expect(completes.map(\.key) == [storedKey])
        #expect(completes.map(\.uploadID) == ["stored-1"])
        #expect(completes.first?.parts == expectedParts(4))
        #expect(logged(lines) == ["resumes at 2 of 4 parts", "multipart completed"])
        let fractions = log.events.compactMap { event -> Double? in
            if case .progress(_, let fraction) = event { return fraction } else { return nil }
        }
        #expect(fractions.allSatisfy { $0 >= 0.5 })
    }

    /// With no sidecar for the stored id, ListParts rebuilds it: a part of the part size (or, last,
    /// the rest) is trusted, any other is sent again. A fixed key gets no HEAD.
    @Test(arguments: [false, true])
    func aResumeWithoutItsSidecarListsTheParts(staleSidecar: Bool) async throws {
        let byteCount = mib + 1000
        let movie = try makeLargeMovie(byteCount: byteCount)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        if staleSidecar {
            try movie.store.writeSidecar(MultipartSidecar(uploadID: "other-1", completeSent: false, parts: expectedParts(4)), id: id)
        }
        let destination = FakeDestination(.init(listedParts: [part(1), part(2, size: 1000, etag: "\"short\""), part(3),
                                                              part(5, size: 1000)]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file, byteCount: byteCount, fixedKey: replaceKey))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        let done = Double(2 * 262_144 + 1000) / Double(byteCount)
        #expect(withoutProgress(log) == [.started(id: id, attempt: 1, fraction: done),
                                         .uploaded(id: id, url: replaceURL, key: replaceKey)])
        #expect(destination.state.withLock { $0.calls }.first == "list")
        #expect(destination.state.withLock { $0.listPartsCalls.map(\.uploadID) } == ["stored-1"])
        #expect(destination.state.withLock { $0.listPartsCalls.map(\.key) } == [replaceKey])
        #expect(destination.state.withLock { $0.headKeys.isEmpty && $0.objectSizeKeys.isEmpty && $0.creates.isEmpty })
        #expect(partNumbers(destination) == [2, 4])
        let all = expectedParts(4) + [part(5, size: 1000)]
        #expect(destination.state.withLock { $0.completes.first?.parts } == all)
        #expect(logged(lines) == ["part list missing, listing parts", "resumes at 3 of 5 parts", "multipart completed"])
        #expect(movie.store.readSidecar(id: id, uploadID: "stored-1") == MultipartSidecar(uploadID: "stored-1",
                                                                                          completeSent: true, parts: all))
    }

    /// The stored key holds an object of the stored size: an earlier Complete landed.
    @Test func aTemplateResumeWhoseKeyHoldsTheUploadCountsAsUploaded() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(objectSizes: [storedKey: mib]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(log.events == [.uploaded(id: id, url: storedURL, key: storedKey)])
        #expect(destination.state.withLock { $0.calls } == ["size"])
        #expect(logged(lines).isEmpty)
    }

    /// Another capture took the stored key while the upload waited: the stored id is aborted and a
    /// new key drawn, as a restart.
    @Test func aTemplateResumeWhoseKeyWasTakenDrawsANewKeyAndRestarts() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        try movie.store.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: false, parts: [part(1), part(2)]), id: id)
        let destination = FakeDestination(.init(objectSizes: [storedKey: 5]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(withoutProgress(log) == [.started(id: id, attempt: 2, fraction: 0),
                                         .multipartStarted(id: id, state: createdState("upload-1", key: templateKey, file: movie.file)),
                                         .uploaded(id: id, url: templateURL, key: templateKey)])
        #expect(Array(destination.state.withLock { $0.calls }.prefix(3)) == ["size", "abort", "create"])
        #expect(destination.state.withLock { $0.aborts.map(\.key) } == [storedKey])
        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1"])
        #expect(destination.state.withLock { $0.headKeys } == [templateKey])
        #expect(destination.state.withLock { $0.creates.map(\.key) } == [templateKey])
        #expect(partNumbers(destination) == [1, 2, 3, 4])
        #expect(logged(lines) == ["multipart aborted", "key taken, starting again", created("upload-1"), "multipart completed"])
    }

    /// ListParts refused (a key without `s3:ListMultipartUploadParts`) or out of tries: the stored
    /// id is aborted and the job restarts under the same key.
    @Test(arguments: [[UploadError.httpStatus(403, body: "AccessDenied: Access Denied")],
                      Array(repeating: UploadError.httpStatus(503, body: ""), count: 3)])
    func aResumeWhosePartListIsUnavailableRestarts(listFailures: [UploadError]) async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(listPartsFailures: listFailures, listedParts: [part(1)]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file, fixedKey: replaceKey))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(withoutProgress(log) == [.started(id: id, attempt: 2, fraction: 0),
                                         .multipartStarted(id: id, state: createdState("upload-1", key: replaceKey, file: movie.file)),
                                         .uploaded(id: id, url: replaceURL, key: replaceKey)])
        #expect(destination.state.withLock { $0.listPartsCalls.count } == listFailures.count)
        #expect(Array(destination.state.withLock { $0.calls }.dropFirst(listFailures.count).prefix(2)) == ["abort", "create"])
        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1"])
        #expect(destination.state.withLock { $0.creates.map(\.key) } == [replaceKey])
        #expect(partNumbers(destination) == [1, 2, 3, 4])
        #expect(logged(lines) == ["part list missing, listing parts", "multipart aborted", "part list unavailable, starting again",
                                  created("upload-1"), "multipart completed"])
    }

    /// ListParts finding the upload id gone restarts under the same key, with nothing to abort.
    @Test func aResumeWhoseUploadIDIsGoneAtListPartsRestarts() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(listPartsFailures: [.noSuchUpload]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file, fixedKey: replaceKey))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(log.events.contains(.uploaded(id: id, url: replaceURL, key: replaceKey)))
        #expect(starts(in: log) == [.started(id: id, attempt: 2, fraction: 0)])
        #expect(Array(destination.state.withLock { $0.calls }.prefix(2)) == ["list", "create"])
        #expect(destination.state.withLock { $0.aborts.isEmpty })
        #expect(destination.state.withLock { $0.creates.map(\.key) } == [replaceKey])
        #expect(logged(lines) == ["part list missing, listing parts", "upload id gone, starting again", created("upload-1"),
                                  "multipart completed"])
    }

    /// A cancel during a resume reports the stored key, found free, and keeps the sidecar's parts.
    @Test func aCancelDuringAResumeReportsTheStoredKey() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let sidecar = MultipartSidecar(uploadID: "stored-1", completeSent: false, parts: [part(1)])
        try movie.store.writeSidecar(sidecar, id: id)
        let destination = FakeDestination(.init(partDelay: .seconds(60)))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)

        await queue.enqueue(resumeJob(id, file: movie.file))
        try await eventually { destination.state.withLock { $0.partsInFlight } == 3 }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: storedKey))
        #expect(withoutProgress(log) == [.started(id: id, attempt: 1, fraction: 0.25),
                                         .cancelled(id: id, reservedKey: storedKey)])
        #expect(movie.store.readSidecar(id: id, uploadID: "stored-1") == sidecar)
    }

    @Test func listPartsRetriesUnderThePolicy() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(listPartsFailures: [.httpStatus(503, body: ""), .noHTTPResponse],
                                                listedParts: [part(1)]))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)

        await queue.enqueue(resumeJob(id, file: movie.file, fixedKey: replaceKey))
        try await eventually { hasEnded(log) }

        #expect(withoutProgress(log) == [.started(id: id, attempt: 1, fraction: 0.25),
                                         .uploaded(id: id, url: replaceURL, key: replaceKey)])
        #expect(destination.state.withLock { $0.listPartsCalls.count } == 3)
        #expect(partNumbers(destination) == [2, 3, 4])
        #expect(destination.state.withLock { $0.creates.isEmpty && $0.aborts.isEmpty })
    }

    /// The server forgot the upload id mid-parts: a new upload under the same key, HEADed again.
    @Test func aPartWhoseUploadIDIsGoneRestartsUnderTheSameKey() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(partFailures: [2: [.noSuchUpload]]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(withoutProgress(log) == [.started(id: id, attempt: 1, fraction: 0),
                                         .multipartStarted(id: id, state: createdState("upload-1", key: templateKey, file: movie.file)),
                                         .started(id: id, attempt: 2, fraction: 0),
                                         .multipartStarted(id: id, state: createdState("upload-2", key: templateKey, file: movie.file)),
                                         .uploaded(id: id, url: templateURL, key: templateKey)])
        #expect(destination.state.withLock { $0.headKeys } == [templateKey, templateKey])
        #expect(destination.state.withLock { $0.creates.map(\.key) } == [templateKey, templateKey])
        #expect(destination.state.withLock { $0.aborts.isEmpty })
        #expect(destination.state.withLock { $0.parts.filter { $0.uploadID == "upload-2" }.map(\.number).sorted() } == [1, 2, 3, 4])
        let completes = destination.state.withLock { $0.completes }
        #expect(completes.map(\.uploadID) == ["upload-2"])
        #expect(completes.first?.parts == expectedParts(4))
        #expect(logged(lines) == [created("upload-1"), "upload id gone, starting again", created("upload-2"), "multipart completed"])
        #expect(movie.store.readSidecar(id: id, uploadID: "upload-2")?.parts == expectedParts(4))
    }

    /// A server that keeps forgetting the upload cannot loop: the third time fails the job.
    @Test func anUploadIDGoneOnEveryCreateFailsAfterTwoRestarts() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(partFailures: [1: [.noSuchUpload, .noSuchUpload, .noSuchUpload]]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(failures(in: log) == ["The upload was no longer known to the server."])
        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 0), .started(id: id, attempt: 2, fraction: 0),
                                    .started(id: id, attempt: 3, fraction: 0)])
        #expect(destination.state.withLock { $0.creates.count } == 3)
        #expect(destination.state.withLock { $0.completes.isEmpty && $0.aborts.isEmpty })
        #expect(logged(lines) == [created("upload-1"), "upload id gone, starting again", created("upload-2"),
                                  "upload id gone, starting again", created("upload-3")])
    }

    /// A Complete sent before (here, before a quit) may have landed: the object's size decides.
    @Test(arguments: [Int64(1_048_576), 5])
    func aCompleteWhoseUploadIDIsGoneAfterAnEarlierCompleteChecksTheObject(size: Int64) async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        try movie.store.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: true, parts: expectedParts(4)), id: id)
        let destination = FakeDestination(.init(completeFailures: [.noSuchUpload], objectSizes: [replaceKey: size]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file, fixedKey: replaceKey))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        let calls = destination.state.withLock { $0.calls }
        #expect(Array(calls.prefix(2)) == ["complete", "size"])
        #expect(destination.state.withLock { $0.objectSizeKeys } == [replaceKey])
        #expect(log.events.contains(.uploaded(id: id, url: replaceURL, key: replaceKey)))
        if size == mib {
            #expect(calls == ["complete", "size"])
            #expect(withoutProgress(log) == [.started(id: id, attempt: 1, fraction: 1),
                                             .uploaded(id: id, url: replaceURL, key: replaceKey)])
            #expect(logged(lines) == ["resumes at 4 of 4 parts", "multipart completed"])
        } else {
            #expect(calls.dropFirst(2).first == "create")
            #expect(destination.state.withLock { $0.aborts.isEmpty })
            #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 1), .started(id: id, attempt: 2, fraction: 0)])
            #expect(logged(lines) == ["resumes at 4 of 4 parts", "upload id gone, starting again", created("upload-1"),
                                      "multipart completed"])
        }
    }

    /// No Complete was sent for the id before this one, so the id is gone without an object.
    @Test func aCompleteWhoseUploadIDIsGoneBeforeAnyCompleteRestarts() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        try movie.store.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: false, parts: expectedParts(4)), id: id)
        let destination = FakeDestination(.init(completeFailures: [.noSuchUpload], objectSizes: [replaceKey: mib]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(resumeJob(id, file: movie.file, fixedKey: replaceKey))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(Array(destination.state.withLock { $0.calls }.prefix(2)) == ["complete", "create"])
        #expect(destination.state.withLock { $0.objectSizeKeys.isEmpty && $0.aborts.isEmpty })
        #expect(destination.state.withLock { $0.completes.map(\.uploadID) } == ["stored-1", "upload-1"])
        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 1), .started(id: id, attempt: 2, fraction: 0)])
        #expect(log.events.contains(.uploaded(id: id, url: replaceURL, key: replaceKey)))
        #expect(logged(lines) == ["resumes at 4 of 4 parts", "upload id gone, starting again", created("upload-1"),
                                  "multipart completed"])
    }

    /// A Complete retried in this run may have landed on its first try, whose answer was lost.
    @Test func aRetriedCompleteWhoseUploadIDIsGoneChecksTheObject() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(completeFailures: [.noHTTPResponse, .noSuchUpload],
                                                objectSizes: [templateKey: mib]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }

        #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
        #expect(destination.state.withLock { $0.completes.count } == 2)
        #expect(destination.state.withLock { $0.objectSizeKeys } == [templateKey])
        #expect(destination.state.withLock { $0.creates.count } == 1)
        #expect(logged(lines) == [created("upload-1"), "multipart completed"])
    }

    /// The first rejection lists the parts and sends again those missing or different.
    @Test func aRejectedPartListIsListedAndTheDifferingPartsSentAgain() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let rejected = UploadError.partsRejected(body: "InvalidPart: One or more of the specified parts could not be found.")
        let destination = FakeDestination(.init(completeFailures: [rejected],
                                                listedParts: [part(1), part(2), part(3, etag: "\"stale\"")]))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 0)])
        let calls = destination.state.withLock { $0.calls }
        let afterFirstComplete = Array(calls.drop { $0 != "complete" })
        #expect(afterFirstComplete.first == "complete")
        #expect(afterFirstComplete.dropFirst().first == "list")
        #expect(Set(afterFirstComplete.dropFirst(2).prefix(2)) == ["part 3", "part 4"])
        #expect(afterFirstComplete.last == "complete")
        #expect(afterFirstComplete.count == 5)
        let completes = destination.state.withLock { $0.completes }
        #expect(completes.map(\.uploadID) == ["upload-1", "upload-1"])
        #expect(completes.last?.parts == expectedParts(4))
        #expect(destination.state.withLock { $0.creates.count == 1 && $0.aborts.isEmpty })
        #expect(logged(lines) == [created("upload-1"), "part list rejected, listing parts", "multipart completed"])
        #expect(movie.store.readSidecar(id: id, uploadID: "upload-1") == MultipartSidecar(uploadID: "upload-1",
                                                                                          completeSent: true, parts: expectedParts(4)))
    }

    /// A second rejection in the job aborts the upload and starts again under the same key.
    @Test func aSecondRejectedPartListRestarts() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let rejected = UploadError.partsRejected(body: "InvalidPartOrder: The list of parts was not in ascending order.")
        let destination = FakeDestination(.init(completeFailures: [rejected, rejected], listedParts: expectedParts(4)))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)

        await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
        try await eventually { hasEnded(log) }
        try await eventually { await queue.isIdle }

        #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 0), .started(id: id, attempt: 2, fraction: 0)])
        #expect(destination.state.withLock { $0.listPartsCalls.count } == 1)
        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["upload-1"])
        #expect(destination.state.withLock { $0.aborts.map(\.key) } == [templateKey])
        #expect(destination.state.withLock { $0.creates.map(\.key) } == [templateKey, templateKey])
        #expect(destination.state.withLock { $0.completes.map(\.uploadID) } == ["upload-1", "upload-1", "upload-2"])
        #expect(logged(lines) == [created("upload-1"), "part list rejected, listing parts", "multipart aborted",
                                  created("upload-2"), "multipart completed"])
    }

    /// A start over aborts the stored upload before its Create; a failed abort is logged and the
    /// job goes on.
    @Test(arguments: [nil, UploadError.httpStatus(403, body: "AccessDenied: Access Denied")])
    func aJobWithAnUploadToAbortAbortsItBeforeItsCreate(abortFailure: UploadError?) async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(abortFailures: abortFailure.map { [$0] } ?? []))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: mib)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { hasEnded(log) }

        #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
        #expect(starts(in: log) == [.started(id: id, attempt: 1, fraction: 0)])
        #expect(Array(destination.state.withLock { $0.calls }.prefix(2)) == ["abort", "create"])
        #expect(destination.state.withLock { $0.aborts.map(\.key) } == ["s/OLD.mp4"])
        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["old-1"])
        let abortLine = abortFailure == nil ? "multipart aborted"
                                            : "multipart abort failed: Server returned HTTP 403: AccessDenied: Access Denied"
        #expect(logged(lines) == [abortLine, created("upload-1"), "multipart completed"])
    }

    /// A start over whose new file is under the threshold goes as one PUT. The stored upload is
    /// still aborted first, once, and a failed abort is logged and the job goes on.
    @Test(arguments: [nil, UploadError.httpStatus(403, body: "AccessDenied: Access Denied")])
    func aSinglePutJobWithAnUploadToAbortAbortsItFirst(abortFailure: UploadError?) async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(abortFailures: abortFailure.map { [$0] } ?? []))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder),
                                       lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: 3)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { hasEnded(log) }

        #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
        #expect(destination.state.withLock { $0.creates.isEmpty })
        #expect(destination.state.withLock { $0.fileUploads.count } == 1)
        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["old-1"])
        #expect(destination.state.withLock { $0.aborts.map(\.key) } == ["s/OLD.mp4"])
        #expect(Array(destination.state.withLock { $0.calls }.prefix(1)) == ["abort"])
        let abortLine = abortFailure == nil ? "multipart aborted"
                                            : "multipart abort failed: Server returned HTTP 403: AccessDenied: Access Denied"
        #expect(logged(lines) == [abortLine])
    }

    /// The abort is not repeated by the single PUT's own retries.
    @Test func aSinglePutJobAbortsOnceAcrossItsRetries() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(failuresRemaining: 2, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder))
        var job = largeJob(id, file: movie.file, byteCount: 3)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { hasEnded(log) }

        #expect(starts(in: log).count == 3)
        #expect(destination.state.withLock { $0.aborts.count } == 1)
    }

    /// A stored upload already gone (an Abort's 404) is logged as such, not as aborted (harness design 5.2).
    @Test func aSinglePutJobsAbortThatFindsNothingIsLoggedAsGone() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(abortResult: .notFound))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder),
                                       lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: 3)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { hasEnded(log) }

        #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["old-1"])
        #expect(logged(lines) == ["multipart upload already gone"])
    }

    @Test func aMultipartJobsAbortThatFindsNothingIsLoggedAsGone() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(abortResult: .notFound))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: mib)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { hasEnded(log) }

        #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
        #expect(logged(lines) == ["multipart upload already gone", created("upload-1"), "multipart completed"])
    }

    /// A cancel that lands while a single PUT's stored upload is being aborted ends the job with one
    /// `.cancelled` and nothing else: no `.started`, no upload, and no log line, as a cancelled Abort
    /// logs nothing (harness design 5.3).
    @Test func aCancelDuringTheSinglePutAbortDeliversCancelled() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(blockingAbortsRemaining: 1))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder),
                                       lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: 3)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { destination.state.withLock { $0.calls } == ["abort"] }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: nil))
        #expect(log.events == [.cancelled(id: id, reservedKey: nil)])
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(destination.state.withLock { $0.creates.isEmpty })
        #expect(logged(lines).isEmpty)
        try await eventually { await queue.isIdle }
    }

    /// An Abort that answers after the cancel is logged, and the job still ends cancelled.
    @Test func anAbortThatAnswersAfterTheSinglePutsCancelIsLoggedAndTheJobCancels() async throws {
        let movie = try makeMovie()
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(holdingAbortsRemaining: 1))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder),
                                       lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: 3)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { destination.state.withLock { $0.calls } == ["abort"] }
        let cancel = Task { await queue.cancel(recordID: id) }
        try await eventually { destination.state.withLock { $0.heldAbortCancellations } == 1 }
        destination.releaseAborts()

        #expect(await cancel.value == .stopped(reservedKey: nil))
        #expect(log.events == [.cancelled(id: id, reservedKey: nil)])
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(logged(lines) == ["multipart aborted"])
    }

    /// The multipart path's equivalent: `.started` went before the abort, and `.cancelled` follows it.
    @Test func aCancelDuringTheMultipartAbortDeliversCancelled() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(blockingAbortsRemaining: 1))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: mib)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { destination.state.withLock { $0.calls } == ["abort"] }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: nil))
        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: nil)])
        #expect(destination.state.withLock { $0.creates.isEmpty })
        #expect(logged(lines).isEmpty)
        try await eventually { await queue.isIdle }
    }

    @Test func anAbortThatAnswersAfterTheMultipartCancelIsLoggedAndTheJobCancels() async throws {
        let movie = try makeLargeMovie(byteCount: mib)
        defer { try? FileManager.default.removeItem(at: movie.folder) }
        let id = UUID()
        let destination = FakeDestination(.init(holdingAbortsRemaining: 1))
        let log = EventLog()
        let lines = LogLines()
        let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
        var job = largeJob(id, file: movie.file, byteCount: mib)
        job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

        await queue.enqueue(job)
        try await eventually { destination.state.withLock { $0.calls } == ["abort"] }
        let cancel = Task { await queue.cancel(recordID: id) }
        try await eventually { destination.state.withLock { $0.heldAbortCancellations } == 1 }
        destination.releaseAborts()

        #expect(await cancel.value == .stopped(reservedKey: nil))
        #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: nil)])
        #expect(destination.state.withLock { $0.creates.isEmpty })
        #expect(logged(lines) == ["multipart aborted"])
    }
}
