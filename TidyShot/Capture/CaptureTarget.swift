import CoreGraphics
import ScreenCaptureKit

/// What to capture. Rects are in CoreGraphics global points (top-left origin).
enum CaptureTarget {
    case display(SCDisplay)
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}

struct CaptureOptions {
    var showsCursor: Bool = false
}

struct CaptureResult {
    let image: CGImage
    /// Backing scale factor of the display the capture came from (1 or 2).
    let scale: CGFloat
    let target: CaptureTarget
}

enum CaptureError: LocalizedError {
    case noImage

    var errorDescription: String? {
        switch self {
        case .noImage: "ScreenCaptureKit returned no image."
        }
    }
}
