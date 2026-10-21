import CoreGraphics

/// Maps the model's image pixels (origin top left, CGImage row 0 at the top) to the editor's
/// flipped canvas views (points, origin top left) and back: `view = image * zoom + offset`.
/// `zoom` is points per image pixel, so a 2x capture is at its natural size (100 %) at zoom 0.5.
nonisolated struct CanvasTransform: Equatable, Sendable {
    /// Points per image pixel.
    var zoom: CGFloat
    /// Where image pixel (0, 0) sits in the view, in points.
    var offset: CGPoint

    func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * zoom + offset.x, y: point.y * zoom + offset.y)
    }

    func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom)
    }

    func viewRect(_ rect: CGRect) -> CGRect {
        guard !rect.isNull else { return rect }
        return CGRect(x: rect.minX * zoom + offset.x, y: rect.minY * zoom + offset.y,
                      width: rect.width * zoom, height: rect.height * zoom)
    }

    func imageRect(_ rect: CGRect) -> CGRect {
        guard !rect.isNull else { return rect }
        return CGRect(x: (rect.minX - offset.x) / zoom, y: (rect.minY - offset.y) / zoom,
                      width: rect.width / zoom, height: rect.height / zoom)
    }

    /// Concatenated onto a flipped view's CTM, this makes drawing happen in image pixels:
    /// `point.applying(affine) == viewPoint(point)`.
    var affine: CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: offset.x, ty: offset.y)
    }

    /// 10 % to 800 % of the natural size.
    static func zoomLimits(captureScale: CGFloat) -> ClosedRange<CGFloat> {
        let scale = captureScale > 0 ? captureScale : 1
        return (0.1 / scale)...(8 / scale)
    }

    /// The whole image inside `viewSize` less `inset` on every side, centred, and never above
    /// the natural size (`1 / captureScale`). Not clamped to `zoomLimits`, so a very tall capture
    /// still fits. The offset is not snapped; call `snapped(toBackingScale:)` before showing it.
    static func fitting(imagePixelSize: CGSize, in viewSize: CGSize, inset: CGFloat,
                        captureScale: CGFloat) -> CanvasTransform {
        let natural = 1 / (captureScale > 0 ? captureScale : 1)
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return CanvasTransform(zoom: natural, offset: .zero)
        }
        let roomWidth = max(viewSize.width - 2 * inset, 1)
        let roomHeight = max(viewSize.height - 2 * inset, 1)
        let zoom = min(natural, roomWidth / imagePixelSize.width, roomHeight / imagePixelSize.height)
        return CanvasTransform(zoom: zoom, offset: CGPoint(x: (viewSize.width - imagePixelSize.width * zoom) / 2,
                                                           y: (viewSize.height - imagePixelSize.height * zoom) / 2))
    }

    /// Zoom multiplied by `factor` and clamped to `limits`, keeping the image pixel under the
    /// view point `anchor` where it is. The range is widened to include the current zoom, so a
    /// zoom that starts outside the limits (a fit below 10 %) never moves against the gesture.
    func zoomed(by factor: CGFloat, around anchor: CGPoint, limits: ClosedRange<CGFloat>) -> CanvasTransform {
        guard factor > 0, factor.isFinite else { return self }
        let lower = min(limits.lowerBound, zoom)
        let upper = max(limits.upperBound, zoom)
        let next = min(max(zoom * factor, lower), upper)
        guard next != zoom else { return self }
        let fixed = imagePoint(anchor)
        return CanvasTransform(zoom: next, offset: CGPoint(x: anchor.x - fixed.x * next, y: anchor.y - fixed.y * next))
    }

    /// The image moved by `delta` view points. Unbounded.
    func panned(by delta: CGPoint) -> CanvasTransform {
        CanvasTransform(zoom: zoom, offset: CGPoint(x: offset.x + delta.x, y: offset.y + delta.y))
    }

    /// The offset rounded to the nearest device pixel at `backingScale`, so the image's pixel
    /// grid starts on a device pixel. The zoom is unchanged.
    func snapped(toBackingScale backingScale: CGFloat) -> CanvasTransform {
        guard backingScale > 0 else { return self }
        return CanvasTransform(zoom: zoom, offset: CGPoint(x: (offset.x * backingScale).rounded() / backingScale,
                                                           y: (offset.y * backingScale).rounded() / backingScale))
    }

    /// The zoom as a whole percentage of the natural size: 100 at `1 / captureScale`.
    func percent(captureScale: CGFloat) -> Int {
        Int((zoom * captureScale * 100).rounded())
    }
}
