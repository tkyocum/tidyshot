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
}

/// Result of the selection overlay. Rects are in CoreGraphics global points.
enum Selection {
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}
