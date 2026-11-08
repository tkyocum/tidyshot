import Foundation

/// Progress through `UploadQueue.ProgressThrottle`: never decreasing, at most 10 times a second,
/// and a fraction of 1 once. `force` passes a phase's boundary through the throttle. The GIF
/// conversion and the trim's re-encode report through one each.
nonisolated final class ProgressReporter {
    private let send: @Sendable (Double) -> Void
    private var throttle = UploadQueue.ProgressThrottle()
    private var last = -1.0

    init(_ send: @escaping @Sendable (Double) -> Void) {
        self.send = send
    }

    func report(_ fraction: Double, force: Bool = false) {
        let value = min(1, fraction)
        guard value > last, force || throttle.admits(value, at: .now) else { return }
        last = value
        send(value)
    }
}
