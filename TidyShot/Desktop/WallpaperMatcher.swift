import CoreGraphics

/// A window that might be a display's wallpaper, as a value. The frame is in global display
/// coordinates with the origin at the top left, as ScreenCaptureKit gives it.
nonisolated struct WallpaperCandidate: Equatable, Sendable {
    var windowID: CGWindowID
    var bundleID: String?
    var title: String?
    var layer: Int
    var frame: CGRect
}

/// Picks the wallpaper window of one display (spec 2.10).
nonisolated enum WallpaperMatcher {
    static let ownerBundleID = "com.apple.WindowManager"
    static let title = "Wallpaper"

    /// The window owned by WindowManager, titled `Wallpaper`, covering the display; otherwise the
    /// lowest-layer WindowManager window covering it; otherwise none.
    static func match(_ candidates: [WallpaperCandidate], displayFrame: CGRect) -> CGWindowID? {
        let covering = candidates.filter { $0.bundleID == ownerBundleID && $0.frame == displayFrame }
        if let titled = covering.first(where: { $0.title == title }) {
            return titled.windowID
        }
        return covering.min { $0.layer < $1.layer }?.windowID
    }
}
