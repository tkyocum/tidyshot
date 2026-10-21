import AppKit
import Testing
@testable import TidyShot

/// All-in-One's capture arming (spec 2.9): a URL command's rect opens disarmed, so Return, keypad
/// Enter and a double-click do not capture it until the user presses in the overlay. The view sits
/// in a window that is never shown, because `fireAllInOne` converts the rect through its window.
struct SelectionViewArmingTests {
    let rect = CGRect(x: 100, y: 100, width: 400, height: 200)

    final class Fired {
        var actions: [AllInOneAction] = []
        var cancels = 0
    }

    func makeView() -> (view: SelectionView, window: NSWindow, fired: Fired) {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: .borderless,
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.mode = .allInOne
        window.contentView = view
        let fired = Fired()
        view.onAllInOneAction = { action, _ in fired.actions.append(action) }
        view.onCancel = { fired.cancels += 1 }
        return (view, window, fired)
    }

    func key(_ keyCode: UInt16, _ characters: String, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: characters,
                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
    }

    func press(at point: CGPoint, clickCount: Int = 1, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                           clickCount: clickCount, pressure: 1)!
    }

    func release(at point: CGPoint, clickCount: Int = 1, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                           clickCount: clickCount, pressure: 0)!
    }

    @Test func returnAndEnterCaptureAnArmedRect() {
        let (view, window, fired) = makeView()
        view.beginAdjusting(rect, fromWindow: false)
        #expect(view.keyCaptureArmed)
        view.keyDown(with: key(36, "\r", in: window))
        view.keyDown(with: key(76, "\u{3}", in: window))
        #expect(fired.actions == [.capture, .capture])
    }

    @Test func aDisarmedRectIgnoresReturnUntilAPress() {
        let (view, window, fired) = makeView()
        view.beginAdjusting(rect, fromWindow: false, armed: false)
        #expect(!view.keyCaptureArmed)
        view.keyDown(with: key(36, "\r", in: window))
        view.keyDown(with: key(76, "\u{3}", in: window))
        #expect(fired.actions.isEmpty)

        let inside = CGPoint(x: rect.midX, y: rect.midY)
        view.mouseDown(with: press(at: inside, in: window))
        view.mouseUp(with: release(at: inside, in: window))
        #expect(view.keyCaptureArmed)
        #expect(view.adjustRect == rect)
        view.keyDown(with: key(36, "\r", in: window))
        #expect(fired.actions == [.capture])
    }

    @Test func aDisarmedRectStillNudgesAndCancels() {
        let (view, window, fired) = makeView()
        view.beginAdjusting(rect, fromWindow: false, armed: false)
        view.keyDown(with: key(124, "\u{F703}", in: window)) // right arrow
        #expect(view.adjustRect == rect.offsetBy(dx: 1, dy: 0))
        #expect(!view.keyCaptureArmed)
        view.keyDown(with: key(53, "\u{1B}", in: window))
        #expect(fired.cancels == 1)
        #expect(fired.actions.isEmpty)
    }

    /// The second click of a double-click that began before the overlay appeared lands disarmed:
    /// it arms but does not capture. A real double-click afterwards does.
    @Test func aDoubleClickCapturesOnlyWhenArmedBeforeIt() {
        let (view, window, fired) = makeView()
        view.beginAdjusting(rect, fromWindow: false, armed: false)
        let inside = CGPoint(x: rect.midX, y: rect.midY)
        view.mouseDown(with: press(at: inside, clickCount: 2, in: window))
        view.mouseUp(with: release(at: inside, clickCount: 2, in: window))
        #expect(fired.actions.isEmpty)
        #expect(view.keyCaptureArmed)

        view.mouseDown(with: press(at: inside, clickCount: 2, in: window))
        #expect(fired.actions == [.capture])
    }

    /// A new rect from the user (a drag or a window click) is armed again.
    @Test func aNewRectIsArmed() {
        let (view, _, _) = makeView()
        view.beginAdjusting(rect, fromWindow: false, armed: false)
        view.beginAdjusting(rect.insetBy(dx: 10, dy: 10), fromWindow: false)
        #expect(view.keyCaptureArmed)
    }
}
