import CoreGraphics

/// Where the full-size preview goes beside the Recent Captures submenu. Pure, so it is tested
/// without windows. All rects are AppKit screen coordinates (origin bottom left).
nonisolated enum PreviewPlacement {
    /// The largest preview, in points.
    static let maxSize = CGSize(width: 560, height: 420)
    /// Space between the preview and the submenu, and between the preview and the screen edge.
    static let gap: CGFloat = 8

    /// `imageSize` scaled down to fit `bounds`, never up, rounded to whole points.
    static func fitted(_ imageSize: CGSize, in bounds: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(1, bounds.width / imageSize.width, bounds.height / imageSize.height)
        return CGSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
    }

    /// The preview's frame, beside `menuFrame` (the submenu's window) on the side away from the
    /// status menu, vertically centred on `rowFrame` (the hovered row) and kept inside
    /// `visibleFrame`. The status menu hangs from the status item, so a submenu whose left edge is
    /// at or right of `statusItemFrame`'s opened to the right of it, and the preview goes on the
    /// submenu's right; otherwise, or with no status item frame, on its left. When that side is
    /// too narrow for the whole preview and the other side is wider, the other side is used.
    static func frame(imageSize: CGSize, menuFrame: CGRect, rowFrame: CGRect, statusItemFrame: CGRect?,
                      visibleFrame: CGRect) -> CGRect {
        let leftRoom = menuFrame.minX - gap - (visibleFrame.minX + gap)
        let rightRoom = visibleFrame.maxX - gap - (menuFrame.maxX + gap)
        let heightBound = min(maxSize.height, visibleFrame.height - 2 * gap)
        let wanted = fitted(imageSize, in: CGSize(width: maxSize.width, height: heightBound))
        let prefersRight = statusItemFrame.map { menuFrame.minX >= $0.minX } ?? false
        let preferredRoom = prefersRight ? rightRoom : leftRoom
        let otherRoom = prefersRight ? leftRoom : rightRoom
        let onRight = preferredRoom >= wanted.width || preferredRoom >= otherRoom ? prefersRight : !prefersRight
        let room = max(0, onRight ? rightRoom : leftRoom)
        let size = fitted(imageSize, in: CGSize(width: min(maxSize.width, room), height: heightBound))
        let x = onRight ? menuFrame.maxX + gap : menuFrame.minX - gap - size.width
        let clampedX = min(max(x, visibleFrame.minX + gap), visibleFrame.maxX - gap - size.width)
        let y = min(max(rowFrame.midY - size.height / 2, visibleFrame.minY + gap), visibleFrame.maxY - gap - size.height)
        return CGRect(x: clampedX, y: y, width: size.width, height: size.height)
    }
}
