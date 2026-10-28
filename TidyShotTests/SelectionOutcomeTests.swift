import CoreGraphics
import Testing
@testable import TidyShot

struct SelectionOutcomeTests {
    let drag = CGRect(x: 40, y: 50, width: 300, height: 200)

    @Test func areaModeTakesADraggedRect() {
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: drag, hasHighlight: false) == .area(drag))
    }

    @Test func areaModeCancelsOnAClickOrATinyDrag() {
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: nil, hasHighlight: false) == .cancel)
        let tiny = CGRect(x: 10, y: 10, width: 1, height: 30)
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: tiny, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: CGRect(x: 10, y: 10, width: 30, height: 1.9), hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: CGRect(x: 10, y: 10, width: 2, height: 2), hasHighlight: false)
                == .area(CGRect(x: 10, y: 10, width: 2, height: 2)))
    }

    @Test func windowModePicksTheHighlightAndIgnoresDrags() {
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: nil, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: drag, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: nil, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: drag, hasHighlight: false) == .cancel)
    }

    /// Scrolling takes a drag like area mode and a click on the highlight like window mode.
    @Test func scrollingModeDragsAnAreaOrClicksAWindow() {
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: drag, hasHighlight: false) == .area(drag))
        // A drag wins over a highlight that happens to be under the pointer.
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: drag, hasHighlight: true) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: nil, hasHighlight: true) == .window)
        // A jittery click on a highlighted window is a click.
        let jitter = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: jitter, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: nil, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: jitter, hasHighlight: false) == .cancel)
    }

    /// All-in-One's first selection works as scrolling's: a drag is an area, a click the
    /// highlighted window (spec 2.9). The overlay then keeps the rect adjustable.
    @Test func allInOneModeDragsAnAreaOrClicksAWindow() {
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: drag, hasHighlight: false) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: drag, hasHighlight: true) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: nil, hasHighlight: true) == .window)
        let jitter = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: jitter, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: nil, hasHighlight: false) == .cancel)
    }

    /// Self-Timer selects like scrolling: a drag is an area, a click on the highlight is a window.
    @Test func selfTimerModeDragsAnAreaOrClicksAWindow() {
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: drag, hasHighlight: false) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: drag, hasHighlight: true) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: nil, hasHighlight: true) == .window)
        let jitter = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: jitter, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: nil, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: jitter, hasHighlight: false) == .cancel)
    }

    /// Record Screen selects as Self-Timer does: a drag records an area, a click the highlighted window.
    @Test func recordingModeDragsAnAreaOrClicksAWindow() {
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: drag, hasHighlight: false) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: drag, hasHighlight: true) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: nil, hasHighlight: true) == .window)
        let jitter = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: jitter, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: nil, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: jitter, hasHighlight: false) == .cancel)
    }
    /// A URL command's preset rect in Record Screen (R4): a click in it records it, before the
    /// window rule; a drag still records its own rect; a click outside picks the highlight.
    @Test func recordingModeClickInThePresetRecordsIt() {
        let preset = CGRect(x: 100, y: 120, width: 640, height: 360)
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: nil, hasHighlight: true, clickInPreset: preset)
                == .area(preset))
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: nil, hasHighlight: false, clickInPreset: preset)
                == .area(preset))
        let jitter = CGRect(x: 200, y: 200, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: jitter, hasHighlight: true, clickInPreset: preset)
                == .area(preset))
        // A click outside the preset (the view passes nil) picks the highlighted window.
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: nil, hasHighlight: true, clickInPreset: nil) == .window)
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: nil, hasHighlight: false, clickInPreset: nil) == .cancel)
    }

    /// A drag gives its own rect, even one that starts inside the preset.
    @Test func recordingModeDragReplacesThePreset() {
        let preset = CGRect(x: 100, y: 120, width: 640, height: 360)
        let inside = CGRect(x: 150, y: 150, width: 200, height: 100)
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: drag, hasHighlight: true, clickInPreset: preset)
                == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .recording, dragRect: inside, hasHighlight: false, clickInPreset: preset)
                == .area(inside))
    }

    /// Every other mode ignores the preset click.
    @Test func otherModesIgnoreThePresetClick() {
        let preset = CGRect(x: 100, y: 120, width: 640, height: 360)
        for mode in [SelectionMode.area, .scrolling, .selfTimer, .allInOne] {
            #expect(SelectionOutcome.resolve(mode: mode, dragRect: nil, hasHighlight: true, clickInPreset: preset) == .window)
            #expect(SelectionOutcome.resolve(mode: mode, dragRect: nil, hasHighlight: false, clickInPreset: preset) == .cancel)
            #expect(SelectionOutcome.resolve(mode: mode, dragRect: drag, hasHighlight: false, clickInPreset: preset) == .area(drag))
        }
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: nil, hasHighlight: true, clickInPreset: preset) == .window)
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: nil, hasHighlight: false, clickInPreset: preset) == .cancel)
    }
}
