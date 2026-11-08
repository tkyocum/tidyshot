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
    func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow] = []) async throws -> CaptureResult {
        let excludingWindows = excludingWindows.compactMap(\.live)
        let config = SCScreenshotConfiguration()
        config.showsCursor = options.showsCursor
        config.dynamicRange = .sdr

        let filter: SCContentFilter
        let scale: CGFloat
        let pixels: (width: Int, height: Int)

        switch target {
        case .display(let display), .area(_, let display):
            guard let source = display.live else { throw CaptureError.notListed }
            filter = SCContentFilter(display: source, excludingWindows: excludingWindows)
            scale = Self.scale(forDisplayID: display.displayID)
            var points = display.frame.size
            if case .area(let rect, _) = target {
                config.sourceRect = Geometry.displayLocal(rect, in: display.frame)
                points = rect.size
            }
            pixels = Geometry.pixelSize(points: points, scale: scale)
        case .window(let window):
            guard let source = window.live else { throw CaptureError.notListed }
            filter = SCContentFilter(desktopIndependentWindow: source)
            // Off is today's output. On, the shadow lies outside `window.frame`, so the size
            // comes from the filter (see `windowPixelSize`).
            config.ignoreShadows = !options.windowShadow
            let displayScale = Self.scale(forDisplayID: Self.displayID(containing: window.frame))
            let geometry = Self.windowGeometry(frame: window.frame, contentRect: filter.contentRect,
                                               pointPixelScale: CGFloat(filter.pointPixelScale),
                                               displayScale: displayScale, includeShadow: options.windowShadow)
            scale = geometry.scale
            pixels = (geometry.width, geometry.height)
        }
        config.width = pixels.width
        config.height = pixels.height

        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config)
        guard let image = output.sdrImage else { throw CaptureError.noImage }
        return CaptureResult(image: image, scale: scale, target: target)
    }

    /// The pixel size of a window capture. Without the shadow: the frame at the display's scale,
    /// as before. With it: the filter's `contentRect` (points) times `pointPixelScale`, which the
    /// probe (`probes/window-shadow`) checks includes the shadow. A degenerate filter (empty or smaller than
    /// the frame, or a zero scale) falls back to the frame, so a capture is never zero-sized.
    static func windowPixelSize(frame: CGRect, contentRect: CGRect, pointPixelScale: CGFloat,
                                displayScale: CGFloat, includeShadow: Bool) -> (width: Int, height: Int) {
        let geometry = windowGeometry(frame: frame, contentRect: contentRect, pointPixelScale: pointPixelScale,
                                      displayScale: displayScale, includeShadow: includeShadow)
        return (geometry.width, geometry.height)
    }

    /// The pixel size and the pixels-per-point of a window capture. When the size comes from the
    /// filter (the branch described at `windowPixelSize`), the scale is the filter's
    /// `pointPixelScale` too, so the result's points match its pixels; otherwise it is the
    /// display's.
    static func windowGeometry(frame: CGRect, contentRect: CGRect, pointPixelScale: CGFloat,
                               displayScale: CGFloat, includeShadow: Bool) -> (width: Int, height: Int, scale: CGFloat) {
        if includeShadow, pointPixelScale > 0,
           contentRect.width >= frame.width, contentRect.height >= frame.height {
            let size = Geometry.pixelSize(points: contentRect.size, scale: pointPixelScale)
            return (size.width, size.height, pointPixelScale)
        }
        let size = Geometry.pixelSize(points: frame.size, scale: displayScale)
        return (size.width, size.height, displayScale)
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
        NSScreen.screens.first { $0.displayID == id }
    }

    /// The display containing the centre of `cgRect` (CG global coordinates), or the main display.
    static func displayID(containing cgRect: CGRect) -> CGDirectDisplayID {
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        CGGetDisplaysWithPoint(CGPoint(x: cgRect.midX, y: cgRect.midY), 1, &id, &count)
        return count > 0 ? id : CGMainDisplayID()
    }

    /// The display under an AppKit-global point, falling back to the first display.
    static func display(under appKitPoint: CGPoint, in displays: [CaptureDisplay]) -> CaptureDisplay? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = Geometry.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
        return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
    }
}

extension CaptureEngine: CaptureSource {
    func screenContent() async throws -> ScreenContent { ScreenContent(try await shareableContent()) }
    func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow] {
        await OverlayWindowLookup.windows(numbers: numbers, engine: self).map(CaptureWindow.init)
    }
    func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay? {
        Self.display(under: NSEvent.mouseLocation, in: displays)
    }
    var isScreenRecordingGranted: Bool { TCCPermission.screenRecording.isGranted() }
}

extension NSScreen {
    /// The CoreGraphics display id of this screen.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
