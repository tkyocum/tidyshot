import CoreGraphics

/// What a capture of the wallpapers changes about the covers (spec 2.10). A cover keeps its last
/// wallpaper when a capture for its display fails, because a stale wallpaper is better than the
/// icons coming back; it goes only when its display does.
nonisolated struct DesktopCoverPlan: Equatable, Sendable {
    /// Screens whose cover, new or existing, gets the new wallpaper.
    var wallpapered: Set<CGDirectDisplayID>
    /// Covers whose display is gone.
    var removed: Set<CGDirectDisplayID>
    /// Screens with no cover and no wallpaper; these are reported.
    var uncovered: Set<CGDirectDisplayID>

    /// `screens` are the current displays, `covered` those with a cover, `captured` those with a new
    /// wallpaper. With `keepsExisting`, as for a show while the covers are up, existing covers
    /// are left as they are.
    static func make(screens: [CGDirectDisplayID], covered: Set<CGDirectDisplayID>,
                     captured: Set<CGDirectDisplayID>, keepsExisting: Bool) -> DesktopCoverPlan {
        var plan = DesktopCoverPlan(wallpapered: [], removed: covered.subtracting(screens), uncovered: [])
        for screen in screens {
            if covered.contains(screen) {
                if !keepsExisting, captured.contains(screen) { plan.wallpapered.insert(screen) }
            } else if captured.contains(screen) {
                plan.wallpapered.insert(screen)
            } else {
                plan.uncovered.insert(screen)
            }
        }
        return plan
    }

    /// The screens without a cover, in order. A show while the covers are up captures only when
    /// there is one.
    static func needingCapture(screens: [CGDirectDisplayID], covered: Set<CGDirectDisplayID>) -> [CGDirectDisplayID] {
        screens.filter { !covered.contains($0) }
    }
}
