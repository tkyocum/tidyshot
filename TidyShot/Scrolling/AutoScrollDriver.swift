import AppKit
import CoreGraphics
import Foundation

/// What auto-scroll needs from the system, so the tests drive it with fakes.
struct AutoScrollEnvironment {
    var poster: any ScrollEventPoster
    /// The pointer in CoreGraphics global points (top-left origin), like the session's area.
    var pointerLocation: () -> CGPoint
    /// Whether the PostEvent grant holds (a TCC preflight); asked before Start and, while the
    /// pointer is over the area, before every wheel event. Never while paused.
    var isPermitted: () -> Bool

    /// The HID poster, `NSEvent.mouseLocation` (polling it needs no permission) and
    /// `PostEventPermission`.
    static func live() -> AutoScrollEnvironment {
        AutoScrollEnvironment(
            poster: HIDScrollEventPoster(),
            pointerLocation: {
                Geometry.cgPoint(fromAppKit: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            },
            isPermitted: { TCCPermission.postEvent.isGranted() })
    }
}

/// Scrolls the captured area for a session in auto mode (spec 2.8, Auto-scroll driver). It
/// posts each wheel event of a step only while the pointer is over the area and the grant holds,
/// waits for the screen to settle, hands the settled frame to the session, and follows
/// `ScrollEndDetector`. TidyShot never moves the pointer: moving it away pauses, moving it back
/// resumes.
final class AutoScrollDriver {
    /// The pointer is polled, and settling checked, this often: 20 times a second.
    static let pollInterval: Duration = .milliseconds(50)

    private let environment: AutoScrollEnvironment
    private let clock: any ScrollClock

    init(environment: AutoScrollEnvironment, clock: any ScrollClock) {
        self.environment = environment
        self.clock = clock
    }

    /// Runs until the session leaves auto mode (a hand-over, or Done or Cancel, which cancel this
    /// task) or the end, which it leaves to `ScrollCaptureSession.finishSoon(showing:)`.
    func run(session: ScrollCaptureSession) async {
        var detector = ScrollEndDetector()
        var direction: CGFloat = 1
        var step = AutoScrollPlan.firstStep(areaHeightPoints: session.area.height)
        // Set once a step has gone to the end detector, and once the other direction was tried.
        var decided = false
        var triedOtherDirection = false
        // The scroll-back owed after a lost step. It goes out at the top of the loop, behind the
        // same grant and pointer checks as a step, so a pause never lets it reach another window.
        var pendingBack: CGFloat?
        var pausedLogged = false
        while session.phase == .capturing(.auto) {
            // The pointer first: the grant is a TCC preflight, asked only when a post would follow,
            // never 20 times a second while paused.
            guard session.hasFirstFrame, session.area.contains(environment.pointerLocation()) else {
                if !pausedLogged {
                    pausedLogged = true
                    ScrollDiag.log("auto paused: \(session.hasFirstFrame ? "pointer outside the area" : "no first frame yet") serial=\(session.frameSerial)")
                }
                session.showAutoStatus(.autoPaused)
                guard await pause(Self.pollInterval) else { return }
                continue
            }
            if pausedLogged {
                pausedLogged = false
                ScrollDiag.log("auto resumed serial=\(session.frameSerial)")
            }
            guard environment.isPermitted() else {
                ScrollDiag.log("auto HAND OVER to manual: PostEvent grant gone, serial=\(session.frameSerial)")
                session.handOver()
                return
            }
            session.showAutoStatus(.autoScrolling)
            if let back = pendingBack {
                pendingBack = nil
                ScrollDiag.log("auto scroll-back step=\(abs(back))pt direction=\(back < 0 ? "up" : "down") serial=\(session.frameSerial)")
                guard let moved = await scroll(by: back, in: session) else { return }
                ScrollDiag.log("auto scroll-back posted=\(moved.posted)pt settledSerial=\(moved.frame.serial) (not compared)")
                // A scroll-back cut short (the pointer left, or the grant went) owes the rest.
                if abs(moved.posted) < abs(back) { pendingBack = back - moved.posted }
                continue
            }
            // A burst cut short (the pointer left, or the grant went) still integrates: the
            // finder measures dy, and the points that went out are the prediction.
            guard let moved = await scroll(by: step * direction, in: session),
                  let progress = await session.integrate(moved.frame, predicted: Int((moved.posted * session.scale).rounded()))
            else { return }
            // Nothing moved on the very first step: at the top of a page in an app that inverts
            // synthetic deltas, the step pushed against the top. Try the other direction once,
            // as a fresh first step, before the end detector may count it as the end.
            if !decided, !triedOtherDirection, progress.step.match == .still, !progress.step.isFull {
                ScrollDiag.log("auto first step posted=\(moved.posted)pt settledSerial=\(moved.frame.serial) was still: trying the other direction")
                triedOtherDirection = true
                direction = -direction
                continue
            }
            decided = true
            let decision = detector.decide(after: progress.step.match, isFull: progress.step.isFull)
            ScrollDiag.log("auto step size=\(step)pt direction=\(direction < 0 ? "up" : "down") posted=\(moved.posted)pt predicted=\(Int((moved.posted * session.scale).rounded()))px settledSerial=\(moved.frame.serial) -> \(ScrollDiag.describe(progress.step.match)) committed=\(progress.step.committedRows) decision=\(decision) detector(stills=\(detector.stills) losses=\(detector.losses))")
            switch decision {
            case .continue:
                if case .moved(_, let top, let bandEnd, _) = progress.step.match {
                    step = AutoScrollPlan.nextStep(bandHeightPixels: bandEnd - top, scale: session.scale)
                }
            case .retryAfter(let delay):
                guard await pause(delay) else { return }
            case .reverseDirection:
                direction = -direction
            case .shrinkStep:
                // Back over what the step that lost the place posted, so the smaller one overlaps
                // the last accepted frame again; posted at the top of the loop.
                pendingBack = -moved.posted
                step = AutoScrollPlan.shrunk(step)
            case .handOver:
                ScrollDiag.log("auto HAND OVER to manual: \(detector.losses) lost steps in a row (limit \(ScrollEndDetector.lossesBeforeHandOver)), last settledSerial=\(moved.frame.serial) step=\(step)pt")
                session.handOver()
                return
            case .end(let reason):
                // In the session's own task: Done cancels this one.
                session.finishSoon(showing: reason == .reachedEnd ? .autoReachedEnd : .heightLimit)
                return
            }
        }
    }

    /// Posts `points` (positive scrolls down) as events of at most 50 pt, 10 ms apart, then
    /// waits until the area settles and returns the newest frame with the points actually posted
    /// (signed). Only frames read after the first event (the session's frame serial past its value
    /// then) reach the settler, so the frame from before the step is returned only when none came
    /// before the settler's timeout, and the step then reads as still. The caller checked the pointer and the grant before the first event; the burst
    /// lasts up to about 80 ms, so each later event checks them again, and when the pointer has
    /// left the area (or moved onto the panel, which the environment reports as outside) or the
    /// grant has gone, the rest is not posted and the settler waits for what was. Nil when the
    /// session left auto mode or the task was cancelled.
    private func scroll(by points: CGFloat, in session: ScrollCaptureSession) async -> (frame: ScrollFrame, posted: CGFloat)? {
        let ignored = Int((ScrollCaptureLimits.scrollbarStripPoints * session.scale).rounded())
        let baseline = session.latestFrame.map { FrameSettler.contentHash(of: $0, ignoringRightColumns: ignored) }
        // The serial at the step's start: frames past it are the only ones that can settle it.
        var seen = session.frameSerial
        var posted: CGFloat = 0
        for (index, size) in AutoScrollPlan.events(forPoints: abs(points)).enumerated() {
            if index > 0 {
                guard await pause(AutoScrollPlan.eventSpacing) else { return nil }
            }
            guard session.phase == .capturing(.auto) else { return nil }
            if index > 0 {
                guard session.area.contains(environment.pointerLocation()), environment.isPermitted() else { break }
            }
            let event = points < 0 ? -size : size
            environment.poster.post(points: event)
            posted += event
            ScrollDiag.log("auto post event=\(event)pt postedSoFar=\(posted)pt of \(points)pt serial=\(session.frameSerial)")
        }
        let stepStart = ContinuousClock.now
        var settler = FrameSettler(stepStart: clock.now, baselineHash: baseline)
        while session.phase == .capturing(.auto) {
            guard await pause(Self.pollInterval) else { return nil }
            if session.frameSerial != seen, let frame = session.latestFrame {
                seen = session.frameSerial
                let hash = FrameSettler.contentHash(of: frame, ignoringRightColumns: ignored)
                ScrollDiag.log("settler frame serial=\(seen) \(hash == baseline ? "same as" : "changed from") the baseline, sinceStep=\(ScrollDiag.ms(since: stepStart))ms")
                settler.record(hash: hash, at: session.latestFrameAt ?? clock.now)
            }
            if settler.isSettled(at: clock.now) {
                ScrollDiag.log("settler SETTLED after \(ScrollDiag.ms(since: stepStart))ms serial=\(session.frameSerial) settledFrameIsBaseline=\(session.latestFrame.map { FrameSettler.contentHash(of: $0, ignoringRightColumns: ignored) } == baseline)")
                return session.latestFrame.map { ($0, posted) }
            }
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
