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

/// Time the Mac is awake, on the suspending clock, which stops while the Mac sleeps: a timeout on
/// it never fires on wake for the time spent asleep (the recording's stop wait). Its instants
/// start at the continuous clock's now and fall behind it by each sleep.
final class SuspendingScrollClock: ScrollClock {
    private let start = (continuous: ContinuousClock.now, suspending: SuspendingClock.now)

    var now: ContinuousClock.Instant { start.continuous + (SuspendingClock.now - start.suspending) }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration, clock: .suspending)
    }
}
