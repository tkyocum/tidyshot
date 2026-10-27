import AppKit
import Testing
@testable import TidyShot

/// A click source that installs nothing and hands events to the highlighter when a test sends them.
final class FakeClickSource: ClickEventSource {
    private(set) var installs = 0
    private(set) var removes = 0
    private var handler: ((ClickEvent) -> Void)?

    func install(_ handler: @escaping (ClickEvent) -> Void) {
        installs += 1
        self.handler = handler
    }

    func remove() {
        removes += 1
    }

    /// Delivers an event as a monitor would, even after `remove`, to show the highlighter drops it.
    func send(_ event: ClickEvent) {
        handler?(event)
    }
}

/// A ring drawing that keeps what it was asked to do.
final class FakeRingDrawing: ClickRingDrawing {
    private(set) var changes: [ClickRingChange] = []
    private(set) var removeAllCount = 0

    func apply(_ change: ClickRingChange) {
        changes.append(change)
    }

    func removeAllRings() {
        removeAllCount += 1
    }
}

/// The monitors, the rule and the overlay joined (design, Click highlights; plan Task 10, Gap 10).
struct ClickHighlighterTests {
    let display = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let area = CGRect(x: 100, y: 100, width: 400, height: 300)
    let source = FakeClickSource()
    let drawing = FakeRingDrawing()

    func highlighter(area: CGRect? = nil) -> ClickHighlighter {
        ClickHighlighter(rule: ClickHighlightRule(displayFrame: display, area: area), source: source, drawing: drawing)
    }

    func event(_ phase: ClickEvent.Phase, _ button: ClickButton = .left, at point: CGPoint) -> ClickEvent {
        ClickEvent(phase: phase, button: button, isControl: false, point: point)
    }

    @Test func startInstallsOnce() {
        let highlighter = highlighter()
        #expect(!highlighter.isMonitoring)
        highlighter.start()
        highlighter.start()
        #expect(source.installs == 1)
        #expect(highlighter.isMonitoring)
    }

    @Test func eventsReachTheDrawingAsTheRulesChanges() {
        let highlighter = highlighter()
        highlighter.start()
        source.send(event(.down, at: CGPoint(x: 200, y: 300)))
        source.send(event(.dragged, at: CGPoint(x: 220, y: 310)))
        source.send(event(.down, .right, at: CGPoint(x: 400, y: 500)))
        source.send(event(.up, at: CGPoint(x: 230, y: 320)))
        #expect(drawing.changes == [
            .begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 200, y: 300))),
            .move(.left, to: CGPoint(x: 220, y: 310)),
            .begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 400, y: 500))),
            .end(.left),
        ])
    }

    @Test func aDownOutsideTheRecordedRectDrawsNothing() {
        let highlighter = highlighter(area: area)
        highlighter.start()
        source.send(event(.down, at: CGPoint(x: 50, y: 50)))
        source.send(event(.up, at: CGPoint(x: 50, y: 50)))
        #expect(drawing.changes.isEmpty)
    }

    @Test func setRuleBeforeStartMovesWhereADownDraws() {
        let highlighter = highlighter(area: area)
        let moved = CGRect(x: 800, y: 500, width: 300, height: 200)
        highlighter.setRule(ClickHighlightRule(displayFrame: display, area: moved))
        highlighter.start()
        source.send(event(.down, at: CGPoint(x: 200, y: 200)))
        source.send(event(.down, .right, at: CGPoint(x: 900, y: 600)))
        #expect(drawing.changes == [.begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 900, y: 600)))])
    }

    /// The fresh rule's display frame sets the overlay's origin.
    @Test func setRuleBeforeStartTakesTheFreshDisplayFrame() {
        let highlighter = highlighter()
        let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        highlighter.setRule(ClickHighlightRule(displayFrame: second, area: nil))
        highlighter.start()
        source.send(event(.down, at: CGPoint(x: 1500, y: 40)))
        #expect(drawing.changes == [.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 60, y: 40)))])
    }

    @Test func setRuleWhileMonitoringChangesNothing() {
        let highlighter = highlighter(area: area)
        highlighter.start()
        highlighter.setRule(ClickHighlightRule(displayFrame: display, area: nil))
        source.send(event(.down, at: CGPoint(x: 50, y: 50)))
        source.send(event(.down, .right, at: CGPoint(x: 200, y: 200)))
        #expect(drawing.changes == [.begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 200, y: 200)))])
    }

    @Test func stopRemovesTheMonitorsAndEndsEachHeldRing() {
        let highlighter = highlighter()
        highlighter.start()
        source.send(event(.down, .right, at: CGPoint(x: 400, y: 500)))
        source.send(event(.down, at: CGPoint(x: 200, y: 300)))
        highlighter.stop()
        #expect(source.removes == 1)
        #expect(!highlighter.isMonitoring)
        #expect(Array(drawing.changes.suffix(2)) == [.end(.left), .end(.right)])
    }

    @Test func anEventAfterStopDrawsNothing() {
        let highlighter = highlighter()
        highlighter.start()
        highlighter.stop()
        source.send(event(.down, at: CGPoint(x: 200, y: 300)))
        #expect(drawing.changes.isEmpty)
    }

    /// The bar turns highlights off and on again mid-recording.
    @Test func startAfterStopInstallsAgain() {
        let highlighter = highlighter()
        highlighter.start()
        highlighter.stop()
        highlighter.start()
        #expect(source.installs == 2)
        source.send(event(.down, at: CGPoint(x: 200, y: 300)))
        #expect(drawing.changes == [.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 200, y: 300)))])
    }

    @Test func closeRemovesEveryRing() {
        let highlighter = highlighter()
        highlighter.start()
        source.send(event(.down, at: CGPoint(x: 200, y: 300)))
        highlighter.close()
        #expect(source.removes == 1)
        #expect(drawing.changes.last == .end(.left))
        #expect(drawing.removeAllCount == 1)
        #expect(!highlighter.isMonitoring)
    }

    /// A close with no start removes no monitor but still clears the overlay.
    @Test func closeBeforeStartRemovesNoMonitor() {
        let highlighter = highlighter()
        highlighter.close()
        #expect(source.removes == 0)
        #expect(drawing.removeAllCount == 1)
    }

    // MARK: The monitor

    @Test func theMonitorWatchesTheSixButtonTypes() {
        #expect(ClickMonitor.mask == [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                      .rightMouseDown, .rightMouseUp, .rightMouseDragged])
    }

    /// Gap 10: a local down draws only on the bubble; local drags and ups pass from any window.
    @Test(arguments: [
        (ClickEvent.Phase.down, true, true),
        (.down, false, false),
        (.dragged, true, true),
        (.dragged, false, true),
        (.up, true, true),
        (.up, false, true),
    ])
    func aLocalEventPasses(phase: ClickEvent.Phase, onFilmedWindow: Bool, passes: Bool) {
        #expect(ClickMonitor.localEventPasses(phase, onFilmedWindow: onFilmedWindow) == passes)
    }
}
