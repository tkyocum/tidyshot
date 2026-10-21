import CoreGraphics

/// Which image-pixel area to repaint when the tile shown for an effect changes. The highlighter's
/// multiply preview copies the shown tiles into its backdrop, so a replaced tile makes that copy stale.
nonisolated enum TileRepaint {
    /// The tile a layer shows: its image and the image-pixel rect it covers.
    struct Shown {
        var image: CGImage
        var rect: CGRect
    }

    /// The area `old` and `new` cover together, or nil when they are the same image at the same
    /// rect (or both absent). Empty rects add nothing.
    static func dirtyRect(old: Shown?, new: Shown?) -> CGRect? {
        if let old, let new, old.image === new.image, old.rect == new.rect { return nil }
        let rects = [old?.rect, new?.rect].compactMap { $0 }.filter { !$0.isEmpty }
        guard let first = rects.first else { return nil }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }
}
