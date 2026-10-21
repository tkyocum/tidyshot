import CoreGraphics

/// Where the scrolling capture's control panel goes (spec 2.8, The session). Pure. All rects are
/// AppKit screen coordinates (origin bottom left, y up): convert the area with
/// `Geometry.appKitRect(fromCG:primaryHeight:)` first.
nonisolated enum ScrollPanelGeometry {
    static let panelWidth: CGFloat = 240
    /// Between the area and the panel, and from the area's edges for the inside placement.
    static let gap: CGFloat = 12
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 560

    /// The panel height for a wanted height: between 220 and `min(560, areaHeight)`. An area
    /// shorter than 220 still gets 220, since the controls need that much.
    static func height(wanted: CGFloat, areaHeight: CGFloat) -> CGFloat {
        let upper = max(minimumHeight, min(maximumHeight, areaHeight))
        return min(max(wanted, minimumHeight), upper)
    }

    /// 12 pt right of the area, top aligned, else 12 pt left of it, else inside its bottom-right
    /// corner, 12 pt from both edges; then clamped into `visibleFrame` (the area's screen).
    static func frame(panelSize: CGSize, area: CGRect, visibleFrame: CGRect) -> CGRect {
        var origin: CGPoint
        if area.maxX + gap + panelSize.width <= visibleFrame.maxX {
            origin = CGPoint(x: area.maxX + gap, y: area.maxY - panelSize.height)
        } else if area.minX - gap - panelSize.width >= visibleFrame.minX {
            origin = CGPoint(x: area.minX - gap - panelSize.width, y: area.maxY - panelSize.height)
        } else {
            origin = CGPoint(x: area.maxX - gap - panelSize.width, y: area.minY + gap)
        }
        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - panelSize.width))
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - panelSize.height))
        return CGRect(origin: origin, size: panelSize)
    }
}
