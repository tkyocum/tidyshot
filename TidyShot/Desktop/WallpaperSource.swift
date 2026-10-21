import AppKit
import ScreenCaptureKit

/// Captures each display's wallpaper window (spec 2.10). The window is captured on its own, so
/// covers above it do not show in the capture.
nonisolated struct WallpaperSource: Sendable {
    /// One image per display, at the display's frame times its scale. A display with no wallpaper
    /// window, or whose capture fails, is left out. With `displayID`, only that display's wallpaper
    /// is captured.
    @concurrent
    func wallpapers(only displayID: CGDirectDisplayID? = nil) async -> [CGDirectDisplayID: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else { return [:] }
        let candidates = content.windows.map {
            WallpaperCandidate(windowID: $0.windowID, bundleID: $0.owningApplication?.bundleIdentifier,
                               title: $0.title, layer: $0.windowLayer, frame: $0.frame)
        }
        let matches: [(displayID: CGDirectDisplayID, window: SCWindow)] = content.displays.compactMap { display in
            guard displayID == nil || display.displayID == displayID,
                  let id = WallpaperMatcher.match(candidates, displayFrame: display.frame),
                  let window = content.windows.first(where: { $0.windowID == id })
            else { return nil }
            return (display.displayID, window)
        }
        let requests = matches.map { (displayID: $0.displayID, frame: $0.window.frame) }
        let sizes = await MainActor.run {
            requests.map { Geometry.pixelSize(points: $0.frame.size, scale: CaptureEngine.scale(forDisplayID: $0.displayID)) }
        }

        return await withTaskGroup(of: (CGDirectDisplayID, CGImage?).self) { group in
            for (match, size) in zip(matches, sizes) {
                let displayID = match.displayID
                // SCWindow is not Sendable; it is only read, inside this one capture call.
                nonisolated(unsafe) let window = match.window
                group.addTask {
                    (displayID, try? await Self.capture(window, width: size.width, height: size.height))
                }
            }
            var images: [CGDirectDisplayID: CGImage] = [:]
            for await (displayID, image) in group {
                images[displayID] = image
            }
            return images
        }
    }

    private static func capture(_ window: SCWindow, width: Int, height: Int) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                          configuration: config)
    }
}
