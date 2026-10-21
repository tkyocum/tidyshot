import CoreGraphics

/// Where All-in-One's toolbar sits (spec 2.9). Pure; the selection view's coordinates, bottom-left
/// origin. `screenBounds` is the view's bounds less the menu bar's safe-area inset (Task 2).
nonisolated enum AllInOneToolbarPlacement {
    /// Between the selection and the toolbar.
    static let gap: CGFloat = 8
    /// Between the toolbar and the screen's edges.
    static let margin: CGFloat = 8

    /// Centred under the selection; above it when below leaves less than `margin` to the screen's
    /// edge; otherwise inside its bottom edge. x is clamped `margin` inside the screen's sides (the
    /// left side wins on a screen narrower than the toolbar). The origin is whole points.
    static func frame(toolbarSize size: CGSize, selection: CGRect, screenBounds bounds: CGRect) -> CGRect {
        let below = selection.minY - gap - size.height
        let above = selection.maxY + gap
        let y: CGFloat
        if below >= bounds.minY + margin {
            y = below
        } else if above + size.height <= bounds.maxY - margin {
            y = above
        } else {
            y = max(min(selection.minY + gap, bounds.maxY - margin - size.height), bounds.minY + margin)
        }
        let x = max(min(selection.midX - size.width / 2, bounds.maxX - margin - size.width), bounds.minX + margin)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
