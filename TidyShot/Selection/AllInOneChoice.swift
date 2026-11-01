import CoreGraphics
import ScreenCaptureKit

/// What All-in-One resolved to (spec 2.9), returned by `SelectionController.selectAllInOne`. Rects
/// are CoreGraphics global points, clipped to `display`. `Selection` gains no case: the coordinator
/// maps each of these to an existing capture path.
enum AllInOneChoice {
    /// Capture (the button, Return or a double-click inside): the area, frozen or live.
    case area(rect: CGRect, display: CaptureDisplay)
    /// The window whose frame a click took, captured from its own surface.
    case window(CaptureWindow)
    /// The display the rect is on.
    case fullscreen(CaptureDisplay)
    case scrolling(rect: CGRect, display: CaptureDisplay)
    /// The Self-Timer countdown over the rect (Task 3).
    case timer(rect: CGRect, display: CaptureDisplay)
}

/// All-in-One's toolbar buttons, left to right after the size fields and the lock (spec 2.9).
nonisolated enum AllInOneAction: CaseIterable, Equatable, Sendable {
    case capture, window, fullscreen, scrolling, timer, cancel

    /// The accessibility label.
    var title: String {
        switch self {
        case .capture: "Capture"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        case .scrolling: "Scrolling"
        case .timer: "Timer"
        case .cancel: "Cancel"
        }
    }

    var symbolName: String {
        switch self {
        case .capture: "camera"
        case .window: "macwindow"
        case .fullscreen: "display"
        case .scrolling: "scroll"
        case .timer: "timer"
        case .cancel: "xmark"
        }
    }

    /// The tooltip. `timerSeconds` is `settings.selfTimerSeconds` (Task 3).
    func help(timerSeconds: Int) -> String {
        switch self {
        case .capture: "Capture area (Return)"
        case .window: "Capture the window with transparent corners"
        case .fullscreen: "Capture this display"
        case .scrolling: "Scrolling capture of this area"
        case .timer: "Capture this area after \(timerSeconds) seconds"
        case .cancel: "Cancel (Escape)"
        }
    }

    /// Window only when the rect came from a window click.
    func isEnabled(hasWindow: Bool) -> Bool {
        self != .window || hasWindow
    }
}

/// The aspect-ratio lock button's strings.
nonisolated enum AllInOneLock {
    static let help = "Lock aspect ratio"

    static func symbolName(locked: Bool) -> String {
        locked ? "lock" : "lock.open"
    }
}
