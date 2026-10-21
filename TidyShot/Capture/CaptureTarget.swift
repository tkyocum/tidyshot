import CoreGraphics
import ScreenCaptureKit

/// What to capture. Rects are in CoreGraphics global points (top-left origin).
enum CaptureTarget {
    case display(SCDisplay)
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}

struct CaptureOptions: Equatable {
    var showsCursor: Bool = false
    /// Window captures only: keep the window's shadow (spec 2.9). Off is today's output.
    var windowShadow: Bool = false
}

extension CaptureOptions {
    /// The one place the cursor rule lives (spec 2.9, Cursor). A capture taken while the
    /// selection overlay is up never shows the pointer: it would be TidyShot's own crosshair.
    /// Any other capture, and a frozen snapshot taken before the overlay appears, follows the
    /// setting. In an extension so the memberwise `init(showsCursor:windowShadow:)` stays.
    init(settings: AppSettings, duringSelection: Bool) {
        self.init(showsCursor: settings.showsCursor && !duringSelection, windowShadow: settings.windowShadow)
    }
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
