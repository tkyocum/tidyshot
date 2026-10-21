import Foundation

/// The time the scrolling session and the auto-scroll driver run on: the continuous clock in the
/// app, a clock the test moves in tests (spec 2.8, Session model). `sleep` throws
/// `CancellationError` when the task is cancelled.
protocol ScrollClock: AnyObject {
    var now: ContinuousClock.Instant { get }
    func sleep(for duration: Duration) async throws
}

final class SystemScrollClock: ScrollClock {
    var now: ContinuousClock.Instant { .now }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
