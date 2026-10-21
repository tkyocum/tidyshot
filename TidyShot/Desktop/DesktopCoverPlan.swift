import CoreGraphics

/// What a capture of the wallpapers changes about the covers (spec 2.10). While the covers show,
/// a cover keeps its last wallpaper when a capture for its display fails, because a stale wallpaper
/// is better than the icons coming back; it goes only when its display does.
nonisolated struct DesktopCoverPlan: Equatable, Sendable {
    /// What the capture is for.
    enum Kind: Sendable {
        /// The covers come up from hidden. Covers kept from before are not trusted: each screen gets
        /// the new wallpaper or no cover.
        case show
        /// A show while the covers are up: existing covers are left as they are.
        case showWhileUp
        /// A refresh while the covers are up: existing covers get the new wallpaper, or keep theirs.
        case refresh
    }

    /// Screens whose cover, new or existing, gets the new wallpaper.
    var wallpapered: Set<CGDirectDisplayID>
    /// Covers that go: their display is gone, or a show from hidden has no wallpaper for them.
    var removed: Set<CGDirectDisplayID>
    /// Screens with no cover and no wallpaper; these are reported.
    var uncovered: Set<CGDirectDisplayID>

    /// `screens` are the current displays, `covered` those with a cover, `captured` those with a new
    /// wallpaper.
    static func make(screens: [CGDirectDisplayID], covered: Set<CGDirectDisplayID>,
                     captured: Set<CGDirectDisplayID>, kind: Kind) -> DesktopCoverPlan {
        var plan = DesktopCoverPlan(wallpapered: [], removed: covered.subtracting(screens), uncovered: [])
        for screen in screens {
            if covered.contains(screen), kind != .show {
                if kind == .refresh, captured.contains(screen) { plan.wallpapered.insert(screen) }
            } else if captured.contains(screen) {
                plan.wallpapered.insert(screen)
            } else {
                if covered.contains(screen) { plan.removed.insert(screen) }
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
