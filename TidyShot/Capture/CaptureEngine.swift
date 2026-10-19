import AppKit
import ScreenCaptureKit

/// Thin wrapper over ScreenCaptureKit's one-shot screenshot API.
final class CaptureEngine {
    /// All on-screen displays and windows. The first call prompts for Screen Recording permission.
    func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Captures `target`. `excludingWindows` removes windows (such as our own overlay) from display
    /// and area captures; it is ignored for window captures.
    func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [SCWindow] = []) async throws -> CaptureResult {
        let config = SCScreenshotConfiguration()
        config.showsCursor = options.showsCursor
        config.dynamicRange = .sdr

        let filter: SCContentFilter
        let scale: CGFloat
        let pointSize: CGSize

        switch target {
        case .display(let display):
            filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
            scale = Self.scale(forDisplayID: display.displayID)
            pointSize = display.frame.size
        case .area(let rect, let display):
            filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
            scale = Self.scale(forDisplayID: display.displayID)
            config.sourceRect = Geometry.displayLocal(rect, in: display.frame)
            pointSize = rect.size
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.ignoreShadows = true
            scale = Self.scale(forDisplayID: Self.displayID(containing: window.frame))
            pointSize = window.frame.size
        }

        let pixels = Geometry.pixelSize(points: pointSize, scale: scale)
        config.width = pixels.width
        config.height = pixels.height

        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        guard let image = output.sdrImage else { throw CaptureError.noImage }
        return CaptureResult(image: image, scale: scale, target: target)
    }

    /// Backing scale of a display: from its NSScreen when available, otherwise from the display
    /// mode's pixel width over its point width.
    static func scale(forDisplayID id: CGDirectDisplayID) -> CGFloat {
        if let screen = screen(forDisplayID: id) {
            return screen.backingScaleFactor
        }
        let bounds = CGDisplayBounds(id)
        guard bounds.width > 0, let mode = CGDisplayCopyDisplayMode(id) else { return 1 }
        return CGFloat(mode.pixelWidth) / bounds.width
    }

    static func screen(forDisplayID id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return number?.uint32Value == id
        }
    }

    /// The display containing the centre of `cgRect` (CG global coordinates), or the main display.
    static func displayID(containing cgRect: CGRect) -> CGDirectDisplayID {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: cgRect.midX, y: cgRect.midY), 1, &id, &count)
        return count > 0 ? id : CGMainDisplayID()
    }
}
