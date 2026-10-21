import AppKit
import CoreGraphics
import Foundation

/// What auto-scroll needs from the system, so the tests drive it with fakes.
struct AutoScrollEnvironment {
    var poster: any ScrollEventPoster
    /// The pointer in CoreGraphics global points (top-left origin), like the session's area.
    var pointerLocation: () -> CGPoint
    /// Whether the PostEvent grant holds; asked before Start and before every step.
    var isPermitted: () -> Bool

    /// The HID poster, `NSEvent.mouseLocation` (polling it needs no permission) and
    /// `PostEventPermission`.
    static func live() -> AutoScrollEnvironment {
        AutoScrollEnvironment(
            poster: HIDScrollEventPoster(),
            pointerLocation: {
                Geometry.cgPoint(fromAppKit: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            },
            isPermitted: { PostEventPermission.isGranted })
    }
}

/// Scrolls the captured area for a session in auto mode (spec 2.8, Auto-scroll driver). It
/// posts a step only while the pointer is over the area and the grant holds, waits for the
/// screen to settle, hands the settled frame to the session, and follows `ScrollEndDetector`.
/// TidyShot never moves the pointer: moving it away pauses, moving it back resumes.
final class AutoScrollDriver {
    /// The pointer is polled, and settling checked, this often: 20 times a second.
    static let pollInterval: Duration = .milliseconds(50)

    private let environment: AutoScrollEnvironment
    private let clock: any ScrollClock

    init(environment: AutoScrollEnvironment, clock: any ScrollClock) {
        self.environment = environment
        self.clock = clock
    }

    /// Runs until the session leaves auto mode: the end, a hand-over, Done or Cancel (which
    /// cancel this task).
    func run(session: ScrollCaptureSession) async {
        var detector = ScrollEndDetector()
        var direction: CGFloat = 1
        var step = AutoScrollPlan.firstStep(areaHeightPoints: session.area.height)
        // Set once a step has gone to the end detector, and once the other direction was tried.
        var decided = false
        var triedOtherDirection = false
        while session.phase == .capturing(.auto) {
            guard environment.isPermitted() else {
                session.handOver()
                return
            }
            guard session.hasFirstFrame, session.area.contains(environment.pointerLocation()) else {
                session.showAutoStatus(.autoPaused)
                guard await pause(Self.pollInterval) else { return }
                continue
            }
            session.showAutoStatus(.autoScrolling)
            guard let frame = await scroll(by: step * direction, in: session),
                  let progress = await session.integrate(frame, predicted: Int((step * session.scale).rounded()))
            else { return }
            // Nothing moved on the very first step: at the top of a page in an app that inverts
            // synthetic deltas, the step pushed against the top. Try the other direction once,
            // as a fresh first step, before the end detector may count it as the end.
            if !decided, !triedOtherDirection, progress.step.match == .still, !progress.step.isFull {
                triedOtherDirection = true
                direction = -direction
                continue
            }
            decided = true
            switch detector.decide(after: progress.step.match, isFull: progress.step.isFull) {
            case .continue:
                if case .moved(_, let top, let bandEnd, _) = progress.step.match {
                    step = AutoScrollPlan.nextStep(bandHeightPixels: bandEnd - top, scale: session.scale)
                }
            case .retryAfter(let delay):
                guard await pause(delay) else { return }
            case .reverseDirection:
                direction = -direction
            case .shrinkStep:
                // Back over the step that lost the place, so the smaller one overlaps the last
                // accepted frame again.
                guard await scroll(by: -step * direction, in: session) != nil else { return }
                step = AutoScrollPlan.shrunk(step)
            case .handOver:
                session.handOver()
                return
            case .end(let reason):
                await session.finish(showing: reason == .reachedEnd ? .autoReachedEnd : .heightLimit)
                return
            }
        }
    }

    /// Posts `points` (positive scrolls down) as events of at most 50 pt, 10 ms apart, then
    /// waits until the area settles and returns the newest frame. Nil when the session left auto
    /// mode or the task was cancelled.
    private func scroll(by points: CGFloat, in session: ScrollCaptureSession) async -> ScrollFrame? {
        let ignored = Int((ScrollCaptureLimits.scrollbarStripPoints * session.scale).rounded())
        let baseline = session.latestFrame.map { FrameSettler.contentHash(of: $0, ignoringRightColumns: ignored) }
        var seen = session.frameSerial
        for (index, size) in AutoScrollPlan.events(forPoints: abs(points)).enumerated() {
            if index > 0 {
                guard await pause(AutoScrollPlan.eventSpacing) else { return nil }
            }
            guard session.phase == .capturing(.auto) else { return nil }
            environment.poster.post(points: points < 0 ? -size : size)
        }
        var settler = FrameSettler(stepStart: clock.now, baselineHash: baseline)
        while session.phase == .capturing(.auto) {
            guard await pause(Self.pollInterval) else { return nil }
            if session.frameSerial != seen, let frame = session.latestFrame {
                seen = session.frameSerial
                _ = settler.observe(.frame(hash: FrameSettler.contentHash(of: frame, ignoringRightColumns: ignored),
                                           at: session.latestFrameAt ?? clock.now))
            }
            if settler.observe(.idle(at: clock.now)) { return session.latestFrame }
        }
        return nil
    }

    /// Sleeps on the session's clock; false when the task was cancelled.
    private func pause(_ duration: Duration) async -> Bool {
        do {
            try await clock.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }
}
