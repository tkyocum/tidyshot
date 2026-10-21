import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// A stage that records what the controller does to it, in order. `note` lets a test put its own
/// marks (the capture) in the same list.
final class FakeSelfTimerStage: SelfTimerStage {
    private(set) var events: [String] = []

    func armEscape() { events.append("arm") }
    func show(seconds: Int) { events.append("show \(seconds)") }
    func tick(seconds: Int) { events.append("tick \(seconds)") }
    func dismiss() { events.append("dismiss") }
    func disarmEscape() { events.append("disarm") }
    func note(_ event: String) { events.append(event) }
}

/// The countdown on a clock the test moves (spec 2.9, Self-Timer), and where the badge goes.
struct SelfTimerTests {
    /// Starts a run of `seconds` and returns its task. The capture marks the stage's event list.
    func start(_ controller: SelfTimerController, _ stage: FakeSelfTimerStage, seconds: Int = 3)
        -> Task<SelfTimerOutcome, Never> {
        Task { await controller.run(seconds: seconds, stage: stage) { stage.note("capture") } }
    }

    @Test func countsDownFromTheConfiguredSeconds() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage)

        await clock.advance(by: .zero)
        #expect(stage.events == ["arm", "show 3"])
        #expect(controller.isRunning)
        await clock.advance(by: .seconds(1))
        #expect(stage.events == ["arm", "show 3", "tick 2"])
        await clock.advance(by: .seconds(1))
        #expect(stage.events == ["arm", "show 3", "tick 2", "tick 1"])
        // Nothing moves between the seconds.
        await clock.advance(by: .milliseconds(999))
        #expect(stage.events.count == 4)
        await clock.advance(by: .milliseconds(1))
        // Zero: the panels go and Escape is released; the capture waits for the settle delay.
        #expect(stage.events == ["arm", "show 3", "tick 2", "tick 1", "dismiss", "disarm"])

        await clock.advance(by: SelfTimerController.settleDelay)
        #expect(await run.value == .finished)
        #expect(!controller.isRunning)
    }

    /// The capture runs once, after the panels are gone and 100 ms later, not before.
    @Test func capturesOnceOnlyAfterThePanelsAreGoneAndTheSettleDelay() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage, seconds: 2)

        await clock.advance(by: .seconds(2))
        #expect(stage.events.suffix(2) == ["dismiss", "disarm"])
        #expect(!stage.events.contains("capture"))
        await clock.advance(by: .milliseconds(99))
        #expect(!stage.events.contains("capture"))
        await clock.advance(by: .milliseconds(1))
        #expect(await run.value == .finished)
        #expect(stage.events == ["arm", "show 2", "tick 1", "dismiss", "disarm", "capture"])
        // Time passing afterwards captures nothing more.
        await clock.advance(by: .seconds(30))
        #expect(stage.events.filter { $0 == "capture" }.count == 1)
    }

    @Test func cancelStopsTheCountdownBeforeTheCapture() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage)

        await clock.advance(by: .seconds(1))
        controller.cancel()
        #expect(await run.value == .cancelled)
        #expect(stage.events == ["arm", "show 3", "tick 2", "dismiss", "disarm"])
        await clock.advance(by: .seconds(30))
        #expect(!stage.events.contains("capture"))
        #expect(!controller.isRunning)
    }

    /// Escape after zero (the capture is under way) cancels nothing.
    @Test func cancelOnceTheCountdownHasEndedIsIgnored() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage, seconds: 1)

        await clock.advance(by: .seconds(1))
        controller.cancel()
        await clock.advance(by: SelfTimerController.settleDelay)
        #expect(await run.value == .finished)
        #expect(stage.events == ["arm", "show 1", "dismiss", "disarm", "capture"])
    }

    @Test func aSecondRunWhileOneRunsIsRefusedAndTouchesNothing() async {
        let clock = FakeScrollClock()
        let first = FakeSelfTimerStage()
        let second = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, first)
        await clock.advance(by: .zero)

        let refused = await controller.run(seconds: 3, stage: second) { second.note("capture") }
        #expect(refused == .cancelled)
        #expect(second.events.isEmpty)
        #expect(controller.isRunning)

        controller.cancel()
        #expect(await run.value == .cancelled)
    }

    @Test func zeroSecondsIsRefused() async {
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: FakeScrollClock())
        let outcome = await controller.run(seconds: 0, stage: stage) { stage.note("capture") }
        #expect(outcome == .cancelled)
        #expect(stage.events.isEmpty)
        #expect(!controller.isRunning)
    }

    // MARK: Badge geometry (AppKit global points, origin bottom-left)

    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func theBadgeIsCentredOnTheSubject() {
        #expect(SelfTimerGeometry.badgeSide == 96)
        let area = SelfTimerGeometry.badgeFrame(around: CGRect(x: 100, y: 100, width: 400, height: 300), in: screen)
        #expect(area == CGRect(x: 252, y: 202, width: 96, height: 96))
        // A subject smaller than the badge is still centred; a half point rounds up.
        let tiny = SelfTimerGeometry.badgeFrame(around: CGRect(x: 100, y: 100, width: 20, height: 20), in: screen)
        #expect(tiny == CGRect(x: 62, y: 62, width: 96, height: 96))
        let odd = SelfTimerGeometry.badgeFrame(around: CGRect(x: 100, y: 100, width: 45, height: 45), in: screen)
        #expect(odd == CGRect(x: 75, y: 75, width: 96, height: 96))
    }

    @Test func theBadgeStaysInsideItsScreen() {
        let corner = SelfTimerGeometry.badgeFrame(around: CGRect(x: 0, y: 0, width: 40, height: 40), in: screen)
        #expect(corner == CGRect(x: 0, y: 0, width: 96, height: 96))
        let far = SelfTimerGeometry.badgeFrame(around: CGRect(x: 1420, y: 880, width: 20, height: 20), in: screen)
        #expect(far == CGRect(x: 1344, y: 804, width: 96, height: 96))
        // A display left of and below the main one has negative coordinates.
        let second = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let inside = SelfTimerGeometry.badgeFrame(around: CGRect(x: -1000, y: 100, width: 300, height: 200), in: second)
        #expect(inside == CGRect(x: -898, y: 152, width: 96, height: 96))
        let edge = SelfTimerGeometry.badgeFrame(around: CGRect(x: -1930, y: -210, width: 20, height: 20), in: second)
        #expect(edge == CGRect(x: -1920, y: -200, width: 96, height: 96))
    }

    /// The badge sits at the screen-saver level; isFloatingPanel would otherwise reset it.
    @Test func theBadgeSitsAtTheScreenSaverLevel() {
        let model = SelfTimerModel()
        model.seconds = 3
        let panel = SelfTimerPanel(model: model, frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        #expect(panel.level == .screenSaver)
    }
}
