import AppKit
import Testing
@testable import TidyShot

/// The selection overlay's own events (spec 2.9 and R4 design, Record Screen's preset rect): a `SelectionView` in a
/// borderless window that is never shown, driven by synthesized events, as `SelectionViewArmingTests` does; its
/// completion converts the rect through that window. A key the view leaves to `super.keyDown` goes to a responder
/// that keeps it, where the window would beep (D10).
struct SelectionViewTests {
    let rect = CGRect(x: 100, y: 100, width: 400, height: 200)

    final class Fired {
        var completed: [CGRect] = []
        var cancels = 0
        var pickedWindow = 0
        var actions: [AllInOneAction] = []
        var rectsSet: [Bool] = []
        var emptyClicks = 0
    }

    /// Keeps the keys the view passes up the responder chain.
    final class KeySink: NSResponder {
        private(set) var keyCodes: [UInt16] = []

        override func keyDown(with event: NSEvent) {
            keyCodes.append(event.keyCode)
        }
    }

    nonisolated enum Mode: CaseIterable, Sendable {
        case area
        case window
    }

    func makeView(_ mode: SelectionMode) -> (view: SelectionView, window: NSWindow, fired: Fired, sink: KeySink) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: .borderless,
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.mode = mode
        window.contentView = view
        let sink = KeySink()
        view.nextResponder = sink
        let fired = Fired()
        view.onComplete = { fired.completed.append($0) }
        view.onCancel = { fired.cancels += 1 }
        view.onPickWindow = { fired.pickedWindow += 1 }
        view.onAllInOneAction = { action, _ in fired.actions.append(action) }
        view.onAdjustRectSet = { fired.rectsSet.append($0) }
        view.onEmptyClick = { fired.emptyClicks += 1 }
        return (view, window, fired, sink)
    }

    func key(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                           pressure: type == .leftMouseUp ? 0 : 1)!
    }

    func click(_ view: SelectionView, at point: CGPoint, in window: NSWindow) {
        view.mouseDown(with: mouse(.leftMouseDown, at: point, in: window))
        view.mouseUp(with: mouse(.leftMouseUp, at: point, in: window))
    }

    func drag(_ view: SelectionView, from start: CGPoint, to end: CGPoint, in window: NSWindow) {
        view.mouseDown(with: mouse(.leftMouseDown, at: start, in: window))
        view.mouseDragged(with: mouse(.leftMouseDragged, at: end, in: window))
        view.mouseUp(with: mouse(.leftMouseUp, at: end, in: window))
    }

    /// The toolbar's text field with the accessibility label `label`; the fields are private, so it is found
    /// among the subviews.
    func textField(_ label: String, in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let candidate = subview as? NSTextField, candidate.accessibilityLabel() == label { return candidate }
            if let found = textField(label, in: subview) { return found }
        }
        return nil
    }

    /// phase-1 :19, phase-1 :33. Escape before any click cancels an area selection, and cancels a window selection.
    /// The controller's dismiss, which needs `SelectionController.present`, is not reached.
    @Test(arguments: Mode.allCases)
    func escapeCancelsAnAreaOrWindowSelection(mode: Mode) {
        let (view, window, fired, _) = makeView(mode == .area ? .area : .window)

        view.keyDown(with: key(53, "\u{1B}", in: window))

        #expect(fired.cancels == 1)
        #expect(fired.completed.isEmpty)
    }

    /// recording-r4 :208, recording-r4 :311 (gap 4). In a recording selection with a preset rect, Return and Enter do
    /// nothing; a click inside records the preset; a drag, also one that starts inside, records the dragged
    /// area; a click outside on a window picks the window; Escape cancels. No key records.
    @Test func aRecordingSelectionIgnoresReturnAndRecordsAClickInsideTheRect() {
        let (view, window, fired, sink) = makeView(.recording)
        view.presetRect = rect

        view.keyDown(with: key(36, "\r", in: window))
        view.keyDown(with: key(76, "\u{3}", in: window))
        #expect(fired.completed.isEmpty)
        #expect(fired.cancels == 0)
        #expect(sink.keyCodes == [36, 76])

        click(view, at: CGPoint(x: rect.midX, y: rect.midY), in: window)
        #expect(fired.completed == [rect])

        drag(view, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250), in: window)
        #expect(fired.completed == [rect, CGRect(x: 150, y: 150, width: 150, height: 100)])

        view.highlightedRect = CGRect(x: 600, y: 500, width: 200, height: 100)
        click(view, at: CGPoint(x: 700, y: 550), in: window)
        #expect(fired.pickedWindow == 1)

        view.keyDown(with: key(53, "\u{1B}", in: window))
        #expect(fired.cancels == 1)
        #expect(fired.completed.count == 2)
    }

    /// phase-6b :52. In All-in-One a click without a drag takes the highlighted window's frame, fitted to the
    /// display, with Window enabled; a resize and a nudge keep Window enabled; a new drag greys it; a click outside
    /// on another window takes that frame; a click outside on the bare desktop keeps the rect.
    @Test func aClickWithoutADragTakesTheHighlightedWindowAndADragDoesNot() {
        let (view, window, fired, _) = makeView(.allInOne)
        let first = CGRect(x: 100, y: 100, width: 300, height: 200)
        view.highlightedRect = first

        click(view, at: CGPoint(x: 200, y: 200), in: window)
        #expect(view.adjustRect == SelectionAdjust.fitted(first, in: view.bounds))
        #expect(view.adjustRectIsWindow)
        #expect(fired.rectsSet == [true])

        // The right edge's handle, dragged out.
        drag(view, from: CGPoint(x: first.maxX, y: first.midY), to: CGPoint(x: first.maxX + 50, y: first.midY),
             in: window)
        #expect(view.adjustRect?.width == first.width + 50)
        #expect(view.adjustRectIsWindow)
        view.keyDown(with: key(124, "\u{F703}", in: window))
        #expect(view.adjustRect?.minX == first.minX + 1)
        #expect(view.adjustRectIsWindow)

        view.highlightedRect = nil
        drag(view, from: CGPoint(x: 600, y: 500), to: CGPoint(x: 700, y: 600), in: window)
        #expect(view.adjustRect == CGRect(x: 600, y: 500, width: 100, height: 100))
        #expect(!view.adjustRectIsWindow)
        #expect(fired.rectsSet == [true, false])

        let second = CGRect(x: 50, y: 600, width: 200, height: 100)
        view.highlightedRect = second
        click(view, at: CGPoint(x: 60, y: 610), in: window)
        #expect(view.adjustRect == second)
        #expect(view.adjustRectIsWindow)

        view.highlightedRect = nil
        click(view, at: CGPoint(x: 900, y: 100), in: window)
        #expect(view.adjustRect == second)
        #expect(fired.emptyClicks == 0)
    }

    /// phase-6b :53 (a press outside the rect). A press outside the rect and a drag start a new rect, and the pointer
    /// is held to the display while it drags. The handles' geometry is `SelectionAdjustTests`.
    @Test func aPressOutsideTheRectStartsANewOne() {
        let (view, window, _, _) = makeView(.allInOne)
        view.beginAdjusting(rect, fromWindow: false)

        drag(view, from: CGPoint(x: 700, y: 600), to: CGPoint(x: 900, y: 700), in: window)
        #expect(view.adjustRect == CGRect(x: 700, y: 600, width: 200, height: 100))

        drag(view, from: CGPoint(x: 650, y: 550), to: CGPoint(x: 1_200, y: 900), in: window)
        #expect(view.adjustRect == CGRect(x: 650, y: 550, width: 350, height: 250))
    }

    /// phase-6b :55. In All-in-One, Command-Return and Command-arrows neither capture nor nudge (they go on up the
    /// responder chain), and a Shift-arrow moves the rect 10 pt. Plain arrows are
    /// `SelectionViewArmingTests.aDisarmedRectStillNudgesAndCancels`.
    @Test func commandKeysNeitherCaptureNorNudgeAndShiftArrowMovesTen() {
        let (view, window, fired, sink) = makeView(.allInOne)
        view.beginAdjusting(rect, fromWindow: false)

        view.keyDown(with: key(36, "\r", .command, in: window))
        view.keyDown(with: key(124, "\u{F703}", .command, in: window))
        #expect(fired.actions.isEmpty)
        #expect(view.adjustRect == rect)
        #expect(sink.keyCodes == [36, 124])

        view.keyDown(with: key(124, "\u{F703}", .shift, in: window))
        #expect(view.adjustRect == rect.offsetBy(dx: 10, dy: 0))
    }

    /// phase-6b :56. Typing 640 into W and pressing Return makes the width 640, growing from the top-left corner, and
    /// captures nothing; the same for H; a width larger than the room is clamped and moved inside, and the field
    /// then shows the size the rect has; a Return in the overlay then captures; Tab goes from W to H.
    @Test func aTypedWidthResizesFromTheTopLeftWithoutCapturing() throws {
        let (view, window, fired, _) = makeView(.allInOne)
        view.beginAdjusting(rect, fromWindow: false)
        let toolbar = try #require(view.subviews.compactMap { $0 as? AllInOneToolbar }.first)
        let width = try #require(textField("Width", in: toolbar))
        let height = try #require(textField("Height", in: toolbar))
        let newline = #selector(NSResponder.insertNewline(_:))

        width.stringValue = "640"
        #expect(toolbar.control(width, textView: NSTextView(), doCommandBy: newline))
        #expect(view.adjustRect == CGRect(x: 100, y: 100, width: 640, height: 200))
        height.stringValue = "300"
        #expect(toolbar.control(height, textView: NSTextView(), doCommandBy: newline))
        #expect(view.adjustRect == CGRect(x: 100, y: 0, width: 640, height: 300))
        #expect(fired.actions.isEmpty)

        width.stringValue = "5000"
        #expect(toolbar.control(width, textView: NSTextView(), doCommandBy: newline))
        #expect(view.adjustRect == CGRect(x: 0, y: 0, width: 1_000, height: 300))
        #expect(width.stringValue == "1000")
        #expect(fired.actions.isEmpty)

        view.keyDown(with: key(36, "\r", in: window))
        #expect(fired.actions == [.capture])
        #expect(width.nextKeyView === height)
    }
}
