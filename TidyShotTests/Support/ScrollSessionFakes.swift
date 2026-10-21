import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// A `FrameSource` the tests feed by hand. Unlike the stream, it buffers without limit, so every
/// frame a test sends reaches the session, in order. `stop()` finishes the events after what is
/// buffered, as `ScrollFrameSource` does.
final class FakeFrameSource: FrameSource {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// Thrown by `start()` when set.
    var startError: (any Error)?
    private var continuation: AsyncStream<FrameEvent>.Continuation?

    func start() async throws -> AsyncStream<FrameEvent> {
        startCount += 1
        if let startError { throw startError }
        let (events, continuation) = AsyncStream.makeStream(of: FrameEvent.self)
        self.continuation = continuation
        return events
    }

    func stop() async {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }

    func send(_ event: FrameEvent) {
        continuation?.yield(event)
    }
}

struct FakeClockTimedOut: Error {}

/// A `ScrollClock` that moves only when the test moves it. Sleepers wait on continuations, never
/// on a thread, so nothing blocks the main actor the tests run on.
final class FakeScrollClock: ScrollClock {
    private struct Sleeper {
        let id: Int
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private(set) var now = ContinuousClock.now
    private var sleepers: [Sleeper] = []
    private var nextID = 0

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = nextID
        nextID += 1
        let deadline = now + duration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in self.resume(id, throwing: CancellationError()) }
        }
    }

    /// Moves time forward by `duration`, waking each sleeper it passes in deadline order and
    /// letting the woken code run on the main actor before the next. Tasks created just before
    /// the call run first, so a sleep they are about to start counts from the time before.
    func advance(by duration: Duration) async {
        await Self.letOthersRun()
        let target = now + duration
        while let next = earliest(), next.deadline <= target {
            now = max(now, next.deadline)
            resume(next.id, throwing: nil)
            await Self.letOthersRun()
        }
        now = target
        await Self.letOthersRun()
    }

    /// Wakes sleepers in deadline order until `condition` holds. After each wake-up it waits in
    /// real time, up to two seconds, until something sleeps on the clock again or the condition
    /// holds, so work on other actors (the stitch engine) finishes between steps.
    func run(until condition: () -> Bool, limit: Duration = .seconds(300)) async throws {
        let end = now + limit
        while !condition() {
            guard try await waitForSleeper(orUntil: condition, realTime: .seconds(2)) else { throw FakeClockTimedOut() }
            if condition() { return }
            guard let next = earliest(), next.deadline <= end else { throw FakeClockTimedOut() }
            now = max(now, next.deadline)
            resume(next.id, throwing: nil)
        }
    }

    /// Lets `duration` pass, waking sleepers as `run(until:)` does. When nothing sleeps on the
    /// clock for 250 ms of real time, the rest of the time passes at once.
    func run(for duration: Duration) async throws {
        let target = now + duration
        while true {
            guard try await waitForSleeper(orUntil: { false }, realTime: .milliseconds(250)),
                  let next = earliest(), next.deadline <= target else { break }
            now = max(now, next.deadline)
            resume(next.id, throwing: nil)
        }
        now = max(now, target)
    }

    private func waitForSleeper(orUntil condition: () -> Bool, realTime: Duration) async throws -> Bool {
        await Self.letOthersRun()
        let giveUp = ContinuousClock.now + realTime
        while sleepers.isEmpty && !condition() {
            guard ContinuousClock.now < giveUp else { return false }
            try await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    /// The sleeper with the earliest deadline; among equal deadlines, the first to sleep.
    private func earliest() -> Sleeper? {
        sleepers.min { $0.deadline < $1.deadline }
    }

    private func resume(_ id: Int, throwing error: (any Error)?) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        let sleeper = sleepers.remove(at: index)
        if let error {
            sleeper.continuation.resume(throwing: error)
        } else {
            sleeper.continuation.resume()
        }
    }

    private static func letOthersRun() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// The stitched image's own bytes. The engine wraps the stitcher's BGRA rows in the CGImage
/// without copying them, so the provider's data is exactly what the stitcher wrote.
func stitchedPixels(of image: ScaledImage) throws -> StitchedImage {
    let cgImage = image.image
    #expect(cgImage.bytesPerRow == cgImage.width * 4)
    let data = try #require(cgImage.dataProvider?.data)
    return StitchedImage(width: cgImage.width, height: cgImage.height, bgra: data as Data)
}
