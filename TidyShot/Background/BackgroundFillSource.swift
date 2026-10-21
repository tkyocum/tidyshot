import CoreGraphics

/// The image a desktop-picture or custom-image fill draws (spec 2.11). Gradients and solid
/// colours need none. A nil image makes the compositor draw gradient preset 0.
nonisolated enum BackgroundFillSource {
    /// The fill's image: the wallpaper of `displayID` (the main display when nil), or the stored
    /// custom image. Nil for gradients and solid colours, and when the image cannot be read.
    @concurrent
    static func fillImage(for fill: BackgroundFill, displayID: CGDirectDisplayID?) async -> CGImage? {
        switch fill {
        case .gradient, .solid: nil
        case .desktopPicture: await desktopPicture(displayID: displayID)
        case .customImage: CustomBackgroundStore.shared.image()
        }
    }

    /// The wallpaper of `displayID`, or of the main display when nil, through 7b's `WallpaperSource`.
    @concurrent
    static func desktopPicture(displayID: CGDirectDisplayID?) async -> CGImage? {
        let id = displayID ?? CGMainDisplayID()
        return await WallpaperSource().wallpapers()[id]
    }
}
