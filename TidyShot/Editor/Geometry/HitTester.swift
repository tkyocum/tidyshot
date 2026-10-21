import CoreGraphics
import Foundation

/// What a click on the canvas lands on. Points are image pixels with a top-left origin; the
/// caller converts the tolerance from view points with `tolerance(zoom:)`.
nonisolated enum HitTester {
    enum Hit: Equatable, Sendable {
        /// The annotation itself: a drag moves it.
        case body
        /// A handle, by its index in `handles(for:)`: a drag resizes.
        case handle(Int)
    }

    /// The hit tolerance in view points, the same at every zoom.
    static let tolerancePoints: CGFloat = 8

    /// `tolerancePoints` in image pixels at `zoom` (view points per image pixel).
    static func tolerance(zoom: CGFloat) -> CGFloat {
        tolerancePoints / zoom
    }

    /// Boxes (the rectangle, the ellipse and every effect) have eight handles, clockwise from the
    /// top-left corner: 0 top-left, 1 top-middle, 2 top-right, 3 middle-right, 4 bottom-right,
    /// 5 bottom-middle, 6 bottom-left, 7 middle-left. Top is minY. A segment (arrow or line) has
    /// two: 0 the tail (`from`) and 1 the head (`to`).
    static func handles(for annotation: Annotation) -> [CGPoint] {
        switch annotation {
        case .rectangle(let shape), .ellipse(let shape):
            boxHandles(shape.rect)
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            boxHandles(region.rect)
        case .arrow(let segment), .line(let segment):
            [segment.from, segment.to]
        }
    }

    /// The nearest handle within `tolerance`, else the body, else nil.
    static func hit(_ annotation: Annotation, at point: CGPoint, tolerance: CGFloat) -> Hit? {
        if let index = handleIndex(of: annotation, at: point, tolerance: tolerance) {
            return .handle(index)
        }
        return bodyContains(annotation, point, tolerance: tolerance) ? .body : nil
    }

    /// Two passes, every handle first and then every body, each over the drawings front to back
    /// and then the effects front to back. Effects render beneath every drawing, so a drawing
    /// wins over an effect created after it, and a handle wins over a body in front of it.
    static func topmost(in document: AnnotationDocument, at point: CGPoint, tolerance: CGFloat) -> (id: UUID, hit: Hit)? {
        let frontToBack = Array((document.effects + document.drawings).reversed())
        for annotation in frontToBack {
            if let index = handleIndex(of: annotation, at: point, tolerance: tolerance) {
                return (annotation.id, .handle(index))
            }
        }
        for annotation in frontToBack where bodyContains(annotation, point, tolerance: tolerance) {
            return (annotation.id, .body)
        }
        return nil
    }

    /// The annotation with handle `handle` dragged to `point`. A box handle goes through
    /// `resizedRect`; an arrow end moves, snapped to 45 degrees around the other end when
    /// `square` (Shift) is held. Id, colour, line width and effect parameter are kept.
    static func resized(_ annotation: Annotation, handle: Int, to point: CGPoint, square: Bool) -> Annotation {
        switch annotation {
        case .rectangle(var shape):
            shape.rect = resizedRect(shape.rect, handle: handle, to: point, square: square)
            return .rectangle(shape)
        case .arrow(var segment):
            switch handle {
            case 0: segment.from = DragGeometry.segmentEnd(from: segment.to, to: point, snap45: square)
            case 1: segment.to = DragGeometry.segmentEnd(from: segment.from, to: point, snap45: square)
            default: break
            }
            return .arrow(segment)
        case .ellipse(var shape):
            shape.rect = resizedRect(shape.rect, handle: handle, to: point, square: square)
            return .ellipse(shape)
        case .line(var segment):
            switch handle {
            case 0: segment.from = DragGeometry.segmentEnd(from: segment.to, to: point, snap45: square)
            case 1: segment.to = DragGeometry.segmentEnd(from: segment.from, to: point, snap45: square)
            default: break
            }
            return .line(segment)
        case .redact(var region, let fill):
            region.rect = resizedRect(region.rect, handle: handle, to: point, square: square)
            return .redact(region, fill: fill)
        case .blur(var region, let radius):
            region.rect = resizedRect(region.rect, handle: handle, to: point, square: square)
            return .blur(region, radius: radius)
        case .pixelate(var region, let block):
            region.rect = resizedRect(region.rect, handle: handle, to: point, square: square)
            return .pixelate(region, block: block)
        }
    }

    /// `rect` with box handle `handle` dragged to `point`, standardized. The opposite corner (for
    /// a corner handle) or edge (for an edge handle) stays put. `square` applies to corner
    /// handles only, as in `DragGeometry.rect`. Any other index returns `rect`.
    static func resizedRect(_ rect: CGRect, handle: Int, to point: CGPoint, square: Bool) -> CGRect {
        let r = rect.standardized
        func span(_ anchor: CGPoint, _ moving: CGPoint, square: Bool = false) -> CGRect {
            DragGeometry.rect(from: anchor, to: moving, square: square, fromCentre: false)
        }
        switch handle {
        case 0: return span(CGPoint(x: r.maxX, y: r.maxY), point, square: square)
        case 1: return span(CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: point.y))
        case 2: return span(CGPoint(x: r.minX, y: r.maxY), point, square: square)
        case 3: return span(CGPoint(x: r.minX, y: r.minY), CGPoint(x: point.x, y: r.maxY))
        case 4: return span(CGPoint(x: r.minX, y: r.minY), point, square: square)
        case 5: return span(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: point.y))
        case 6: return span(CGPoint(x: r.maxX, y: r.minY), point, square: square)
        case 7: return span(CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: point.x, y: r.minY))
        default: return r
        }
    }

    /// Whether `point` is inside or on the ellipse inscribed in `rect`. An empty or null rect
    /// holds nothing, so a rect inset past its own size has no hollow and the ring is a disc,
    /// as `AnnotationDrawing` fills an ellipse that small.
    private static func ellipseContains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return false }
        let dx = (point.x - rect.midX) / (rect.width / 2)
        let dy = (point.y - rect.midY) / (rect.height / 2)
        return dx * dx + dy * dy <= 1
    }

    /// The distance from `point` to the segment from `a` to `b`; to `a` when they are equal.
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + t * abx), point.y - (a.y + t * aby))
    }

    private static func boxHandles(_ rect: CGRect) -> [CGPoint] {
        let r = rect.standardized
        return [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY),
        ]
    }

    /// The nearest handle within `tolerance` of `point`.
    private static func handleIndex(of annotation: Annotation, at point: CGPoint, tolerance: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, handle) in handles(for: annotation).enumerated() {
            let distance = hypot(point.x - handle.x, point.y - handle.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// A rectangle is hollow: its body is the stroke band, from `tolerance` outside the rect to
    /// `lineWidth + tolerance` inside it (the stroke sits inside the rect). An ellipse is hollow
    /// likewise: its body is the ring between the ellipse grown by `tolerance` and the ellipse of
    /// the rect inset by `lineWidth + tolerance`. An arrow's body is its shaft line, and a line's
    /// the whole segment, within `lineWidth / 2 + tolerance`. An effect is filled: its rect grown
    /// by `tolerance`.
    private static func bodyContains(_ annotation: Annotation, _ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch annotation {
        case .rectangle(let shape):
            let rect = shape.rect.standardized
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: shape.lineWidth + tolerance, dy: shape.lineWidth + tolerance)
            return outer.contains(point) && !inner.contains(point)
        case .ellipse(let shape):
            let rect = shape.rect.standardized
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: shape.lineWidth + tolerance, dy: shape.lineWidth + tolerance)
            return ellipseContains(outer, point) && !ellipseContains(inner, point)
        case .arrow(let segment), .line(let segment):
            return distance(from: point, toSegment: segment.from, segment.to) <= segment.lineWidth / 2 + tolerance
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            return region.rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }
}
