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
    /// What the save path reads of this target (`AppCoordinator.save(_:from:intent:)`).
    var origin: CaptureOrigin {
        switch self {
        case .display: CaptureOrigin(kind: .display, displayID: displayID)
        case .area(let rect, _): CaptureOrigin(kind: .area(rect), displayID: displayID)
        case .window: CaptureOrigin(kind: .window, displayID: displayID)
        }
    }
}

/// Where a capture came from, as the save path reads it: a display, an area or a window, and the
/// display it came from. A value, not the ScreenCaptureKit objects, so the suite can build one
/// (seams.md section 3, `TARGET`); `CaptureTarget.origin` makes it from a live target.
nonisolated struct CaptureOrigin: Equatable, Sendable {
    /// An area carries its rect, in CoreGraphics global points.
    enum Kind: Equatable, Sendable { case display, area(CGRect), window }
    var kind: Kind
    /// `CaptureTarget.displayID`: the card's screen under `Show on` and the desktop picture's display.
    var displayID: CGDirectDisplayID
    /// The rect of an area capture, nil for a display or a window. A pin of the newest capture opens over it.
    var areaRect: CGRect? { if case .area(let rect) = kind { rect } else { nil } }
    /// Only a window capture goes on the Capture tab's background.
    var isWindow: Bool { kind == .window }
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
