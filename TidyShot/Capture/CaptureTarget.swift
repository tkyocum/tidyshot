import CoreGraphics
import ScreenCaptureKit

/// What to capture. Rects are in CoreGraphics global points (top-left origin).
enum CaptureTarget {
    case display(SCDisplay)
    case area(rect: CGRect, display: SCDisplay)
    case window(SCWindow)
}

extension CaptureTarget {
    /// The display the capture came from: the area's or the fullscreen display, or the display
    /// under a window's centre. The Quick Access stack goes there with `Show on` set to the capture.
    var displayID: CGDirectDisplayID {
        switch self {
        case .display(let display): display.displayID
        case .area(_, let display): display.displayID
        case .window(let window): CaptureEngine.displayID(containing: window.frame)
        }
    }
}

extension CaptureTarget {
    /// Where the capture looks, in CoreGraphics global points: the display's frame, the area's
    /// rect or the window's frame. The self-timer's badge and frame are placed from it.
    var cgFrame: CGRect {
        switch self {
        case .display(let display): display.frame
        case .area(let rect, _): rect
        case .window(let window): window.frame
        }
    }
}

extension CaptureTarget {
    /// The rect of an area capture (CoreGraphics global points), nil for a display or a window.
    /// A pin of the newest capture opens over it.
    var areaRect: CGRect? {
        if case .area(let rect, _) = self { rect } else { nil }
    }
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
