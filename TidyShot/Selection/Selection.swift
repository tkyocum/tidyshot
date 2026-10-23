import CoreGraphics
import ScreenCaptureKit

enum SelectionMode {
    case area
    case window
    /// Capture Scrolling: the crosshair and loupe of `.area` plus the window highlight of `.window`.
    case scrolling
    /// All-in-One: starts as `.scrolling` (crosshair, loupe, window highlight), then keeps the
    /// rect adjustable under a toolbar. Resolved through `SelectionController.selectAllInOne`.
    case allInOne
    /// Self-Timer: the same crosshair, loupe and window highlight as `.scrolling`. A drag is an
    /// area; a click on the highlight returns the window (the controller returns `.window` for a
    /// click in every mode but `.scrolling`).
    case selfTimer
    /// Record Screen: exactly as `.selfTimer`. A drag records an area; a click records the
    /// highlighted window.
    case recording
}

/// Result of the selection overlay. Rects are in CoreGraphics global points.
enum Selection {
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}
