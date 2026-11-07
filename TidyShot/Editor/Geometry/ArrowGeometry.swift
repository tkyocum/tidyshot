import CoreGraphics
import Foundation

/// The arrow's filled head and the end of its round-capped shaft, in image pixels. `scale` is the
/// capture scale, so a 2x capture gets a head twice as many pixels long.
nonisolated enum ArrowGeometry {
    /// Half the angle at the tip.
    static let halfAngleDegrees: CGFloat = 28

    /// The head's length along the shaft: max(12 * scale, 4 * lineWidth), but never longer than
    /// the arrow, so a short arrow's head ends at its tail.
    static func headLength(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> CGFloat {
        min(max(12 * scale, 4 * lineWidth), hypot(to.x - from.x, to.y - from.y))
    }

    /// The head triangle. `tip` is `to`. `left` and `right` are the corners of the base, which is
    /// square to the shaft `headLength` back from the tip; left and right are as seen travelling
    /// from `from` to `to` with y growing downward. A zero-length arrow gives three equal points.
    static func head(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> (tip: CGPoint, left: CGPoint, right: CGPoint) {
        guard let unit = direction(from: from, to: to) else { return (to, to, to) }
        let length = headLength(from: from, to: to, lineWidth: lineWidth, scale: scale)
        let halfWidth = length * tan(halfAngleDegrees * .pi / 180)
        let base = CGPoint(x: to.x - unit.dx * length, y: to.y - unit.dy * length)
        let left = CGPoint(x: base.x + unit.dy * halfWidth, y: base.y - unit.dx * halfWidth)
        let right = CGPoint(x: base.x - unit.dy * halfWidth, y: base.y + unit.dx * halfWidth)
        return (to, left, right)
    }

    /// Where the shaft stops: half the head's length back from the tip. That is past the base, so
    /// no gap shows, and the round cap stays inside the triangle: there the distance to each side
    /// is (length / 2) * sin(28°), at least 0.94 * lineWidth because length is at least
    /// 4 * lineWidth, against a cap radius of lineWidth / 2.
    static func shaftEnd(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> CGPoint {
        guard let unit = direction(from: from, to: to) else { return to }
        let back = headLength(from: from, to: to, lineWidth: lineWidth, scale: scale) / 2
        return CGPoint(x: to.x - unit.dx * back, y: to.y - unit.dy * back)
    }

    /// The unit vector from `from` to `to`, nil when they are equal.
    private static func direction(from: CGPoint, to: CGPoint) -> CGVector? {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return nil }
        return CGVector(dx: (to.x - from.x) / length, dy: (to.y - from.y) / length)
    }
}

/// Everything an annotation paints, in image pixels, so the canvas can invalidate it and skip the
/// drawings outside a dirty rect.
nonisolated enum AnnotationGeometry {
    /// Anti-aliasing can touch one pixel past the geometry.
    static let antialiasMargin: CGFloat = 1

    static func bounds(of annotation: Annotation, scale: CGFloat) -> CGRect {
        let painted: CGRect
        switch annotation {
        case .rectangle(let shape), .ellipse(let shape):
            // The stroke sits inside the rect.
            painted = shape.rect.standardized
        case .line(let segment):
            let cap = segment.lineWidth / 2
            painted = enclosing([segment.from, segment.to]).insetBy(dx: -cap, dy: -cap)
        case .arrow(let segment):
            let head = ArrowGeometry.head(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
            let end = ArrowGeometry.shaftEnd(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
            let cap = segment.lineWidth / 2
            let shaft = enclosing([segment.from, end]).insetBy(dx: -cap, dy: -cap)
            painted = shaft.union(enclosing([head.tip, head.left, head.right]))
        case .pencil(let stroke), .highlighter(let stroke):
            painted = strokeBounds(of: stroke)
        case .text(let box):
            // The padding holds the glyphs' overhang.
            painted = TextLayout.frame(for: box)
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            painted = region.rect.standardized
        case .spotlight(let shape):
            // The overlay changes only inside the hole.
            painted = shape.rect.standardized
        case .counter(let mark):
            // The ring sits inside the circle.
            painted = circleBox(of: mark)
        }
        return painted.insetBy(dx: -antialiasMargin, dy: -antialiasMargin)
    }

    /// The rect the selection outline dashes around, in image pixels: an effect's or a spotlight's
    /// rect, a stroke's outline, a text's frame, or a counter's bounding square; nil for a
    /// rectangle, ellipse, arrow or line, whose handles show where it is. Exhaustive, so a new kind
    /// decides here.
    static func selectionOutline(of annotation: Annotation) -> CGRect? {
        switch annotation {
        case .rectangle, .ellipse, .arrow, .line:
            nil
        case .pencil(let stroke), .highlighter(let stroke):
            strokeBounds(of: stroke)
        case .text(let box):
            TextLayout.frame(for: box)
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            region.rect
        case .spotlight(let shape):
            shape.rect
        case .counter(let mark):
            circleBox(of: mark)
        }
    }

    /// The square around a counter's circle.
    private static func circleBox(of mark: CounterMark) -> CGRect {
        let radius = mark.diameter / 2
        return CGRect(x: mark.center.x - radius, y: mark.center.y - radius, width: mark.diameter, height: mark.diameter)
    }

    /// A stroke's smoothed path grown by half its width. The path is built here and dropped (the
    /// canvas, which draws it too, keeps its own and calls `strokeBounds(ofPath:lineWidth:)`).
    /// Catmull-Rom can overshoot its points a little, so the bounds come from the curve, not from
    /// the points.
    static func strokeBounds(of stroke: Stroke) -> CGRect {
        guard !stroke.points.isEmpty else { return .null }
        return strokeBounds(ofPath: StrokeSmoothing.path(for: stroke.points), lineWidth: stroke.lineWidth)
    }

    /// `strokeBounds(of:)` for a stroke whose smoothed path the caller already holds.
    static func strokeBounds(ofPath path: CGPath, lineWidth: CGFloat) -> CGRect {
        path.boundingBoxOfPath.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
    }

    /// The box the selection outline draws around a stroke; nil for every other annotation.
    static func strokeOutline(of annotation: Annotation) -> CGRect? {
        switch annotation {
        case .pencil(let stroke), .highlighter(let stroke): strokeBounds(of: stroke)
        default: nil
        }
    }

    /// The smallest rect holding `points`; it may have zero width or height.
    private static func enclosing(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }
}
