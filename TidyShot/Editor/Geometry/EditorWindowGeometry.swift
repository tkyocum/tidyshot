import CoreGraphics

/// The editor window's first size and where it goes. Pure, so it is tested without windows.
/// Frames are AppKit screen rects (origin bottom left).
nonisolated enum EditorWindowGeometry {
    /// Space around the image at its natural size, in points; also the `inset` passed to
    /// `CanvasTransform.fitting`.
    static let inset: CGFloat = 24
    /// The smallest content size the editor opens at, in points.
    static let minimumContentSize = CGSize(width: 640, height: 420)
    /// The largest share of the visible frame the window's frame opens at.
    static let screenFraction: CGFloat = 0.9

    /// The content size for an image of `imagePixels` at `scale`: its natural point size plus
    /// `inset` on every side, rounded up to whole points, at least `minimumContentSize`, and
    /// small enough that the frame (content plus `chrome`, the title bar and toolbar) fits in
    /// 90 % of `visibleFrame`. On a screen too small for the minimum, the 90 % cap wins.
    static func initialContentSize(imagePixels: CGSize, scale: CGFloat, chrome: CGSize,
                                   visibleFrame: CGRect) -> CGSize {
        let scale = scale > 0 ? scale : 1
        let wantedWidth = (imagePixels.width / scale + 2 * inset).rounded(.up)
        let wantedHeight = (imagePixels.height / scale + 2 * inset).rounded(.up)
        let largestWidth = (visibleFrame.width * screenFraction - chrome.width).rounded(.down)
        let largestHeight = (visibleFrame.height * screenFraction - chrome.height).rounded(.down)
        return CGSize(width: min(max(wantedWidth, minimumContentSize.width), largestWidth),
                      height: min(max(wantedHeight, minimumContentSize.height), largestHeight))
    }

    /// A window frame of `size`: centred in `visibleFrame` when there is no `previous` editor,
    /// otherwise `offset` points right of and below `previous` (its top edge `offset` lower).
    /// Clamped inside `visibleFrame`; a frame larger than it keeps its top-left corner on screen
    /// so the title bar can be reached. The origin is rounded to whole points.
    static func cascaded(from previous: CGRect?, size: CGSize, visibleFrame: CGRect,
                         offset: CGFloat = 22) -> CGRect {
        let origin = previous.map { CGPoint(x: $0.minX + offset, y: $0.maxY - offset - size.height) }
            ?? CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        let x = max(min(origin.x, visibleFrame.maxX - size.width), visibleFrame.minX)
        let y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
