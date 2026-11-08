import CoreGraphics
import Foundation

nonisolated enum SelfTimerOutcome: Equatable, Sendable {
    /// The countdown reached zero and the capture closure ran.
    case finished
    /// Escape, or a refused start. The capture closure did not run.
    case cancelled
}

/// What the countdown puts on screen and the Escape hotkey it holds. The controller calls these in
/// a fixed order (tested through a fake): `armEscape`, `show`, a `tick` for each second left
/// below the first, `dismiss`, `disarmEscape`. `SelfTimerScreenStage` is the real one.
protocol SelfTimerStage: AnyObject {
    func armEscape()
    func show(seconds: Int)
    func tick(seconds: Int)
    /// Orders every panel out. Called once per run, before the settle delay.
    func dismiss()
    func disarmEscape()
}

/// Where the countdown badge goes (spec 2.9, Self-Timer). AppKit global points, origin bottom-left.
nonisolated enum SelfTimerGeometry {
    static let badgeSide: CGFloat = 96

    /// The badge centred on `subject` (the area or window), whole-point origin, kept inside
    /// `screenFrame` so a subject at the edge of its display still shows it.
    static func badgeFrame(around subject: CGRect, in screenFrame: CGRect) -> CGRect {
        CGRect.centred(CGSize(width: badgeSide, height: badgeSide), on: CGPoint(x: subject.midX, y: subject.midY),
                       within: screenFrame)
    }
}

/// The self-timer's countdown, on the clock the scrolling session uses so a test moves it by hand
/// (spec 2.9). One run at a time. The caller holds the capture lock around `run`.
final class SelfTimerController {
    /// After the panels are ordered out, for the window server to drop them before the capture.
    static let settleDelay: Duration = .milliseconds(100)

    private let clock: any ScrollClock
    /// The counting task; nil outside the counting, so Escape during the capture does nothing.
    private var countdown: Task<Bool, Never>?
    /// True from the start of a run until its capture closure returns.
    private(set) var isRunning = false

    init(clock: any ScrollClock = SystemScrollClock()) {
        self.clock = clock
    }

    /// Shows `seconds` on `stage`, counts down once a second, then orders the stage out, waits
    /// `settleDelay` and awaits `capture`. Returns `.cancelled` at once (touching nothing) when a
    /// run is under way or `seconds` is not above zero, and `.cancelled` after `cancel()` during
    /// the counting, with the stage already out and `capture` not called.
    func run(seconds: Int, stage: any SelfTimerStage, capture: () async -> Void) async -> SelfTimerOutcome {
        guard !isRunning, seconds > 0 else { return .cancelled }
        isRunning = true
        defer { isRunning = false }
        stage.armEscape()
        stage.show(seconds: seconds)
        let clock = self.clock
        let counting = Task { () -> Bool in
            var left = seconds
            while left > 0 {
                do { try await clock.sleep(for: .seconds(1)) } catch { return false }
                left -= 1
                if left > 0 { stage.tick(seconds: left) }
            }
            return true
        }
        countdown = counting
        let reachedZero = await counting.value
        countdown = nil
        stage.dismiss()
        stage.disarmEscape()
        guard reachedZero else { return .cancelled }
        // A cancelled caller skips the pause and still captures: the countdown ran out.
        try? await clock.sleep(for: Self.settleDelay)
        await capture()
        return .finished
    }

    /// Escape: stops the counting. No effect before it starts, or once the capture is under way.
    func cancel() {
        countdown?.cancel()
    }
}
