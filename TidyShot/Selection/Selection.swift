import CoreGraphics
import ScreenCaptureKit

enum SelectionMode {
    case area
    case window
}

/// Result of the selection overlay. Rects are in CoreGraphics global points.
enum Selection {
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}
