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
}
