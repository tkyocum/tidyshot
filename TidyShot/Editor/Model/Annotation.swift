import CoreGraphics
import Foundation

// All geometry is in image pixels with a top-left origin (CGImage row 0). Line widths, blur radii
// and pixel blocks are image pixels too: the points chosen in the UI times the capture scale.

/// A rectangle outline. The stroke sits inside `rect`.
nonisolated struct ShapeBox: Codable, Equatable, Sendable {
    let id: UUID
    var rect: CGRect
    var color: RGBA
    var lineWidth: CGFloat
}

/// A two-point shape: an arrow in 4a, a line in 4b. The tail is `from`, the head `to`.
nonisolated struct Segment: Codable, Equatable, Sendable {
    let id: UUID
    var from: CGPoint
    var to: CGPoint
    var color: RGBA
    var lineWidth: CGFloat
}

/// The area an effect covers.
nonisolated struct Region: Codable, Equatable, Sendable {
    let id: UUID
    var rect: CGRect
}

/// One edit on a capture. Effects (redact, blur, pixelate) belong to the base layer and render
/// beneath every drawing; drawings (rectangle, ellipse, arrow, line) render above them.
nonisolated enum Annotation: Identifiable, Codable, Equatable, Sendable {
    case rectangle(ShapeBox)
    case arrow(Segment)
    case ellipse(ShapeBox)
    case line(Segment)
    case redact(Region, fill: RGBA)
    /// `radius` is the Gaussian sigma.
    case blur(Region, radius: CGFloat)
    case pixelate(Region, block: CGFloat)

    var id: UUID {
        switch self {
        case .rectangle(let box), .ellipse(let box): box.id
        case .arrow(let segment), .line(let segment): segment.id
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _): region.id
        }
    }

    var isEffect: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .line: false
        case .redact, .blur, .pixelate: true
        }
    }

    /// The region an effect covers; nil for a drawing.
    var effectRect: CGRect? {
        switch self {
        case .rectangle, .ellipse, .arrow, .line: nil
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _): region.rect
        }
    }

    /// The name of the tool that makes this kind, for undo action names.
    var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .redact: "Redact"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }

    /// The same annotation shifted by `delta`: a rect's origin, or both ends of a segment.
    func moved(by delta: CGVector) -> Annotation {
        switch self {
        case .rectangle(var box):
            box.rect = box.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .rectangle(box)
        case .arrow(var segment):
            segment.from = CGPoint(x: segment.from.x + delta.dx, y: segment.from.y + delta.dy)
            segment.to = CGPoint(x: segment.to.x + delta.dx, y: segment.to.y + delta.dy)
            return .arrow(segment)
        case .ellipse(var box):
            box.rect = box.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .ellipse(box)
        case .line(var segment):
            segment.from = CGPoint(x: segment.from.x + delta.dx, y: segment.from.y + delta.dy)
            segment.to = CGPoint(x: segment.to.x + delta.dx, y: segment.to.y + delta.dy)
            return .line(segment)
        case .redact(var region, let fill):
            region.rect = region.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .redact(region, fill: fill)
        case .blur(var region, let radius):
            region.rect = region.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .blur(region, radius: radius)
        case .pixelate(var region, let block):
            region.rect = region.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .pixelate(region, block: block)
        }
    }

    /// The stroke colour of a shape or the fill of a redaction. Blur and pixelate have no colour
    /// and come back unchanged.
    func withColor(_ color: RGBA) -> Annotation {
        switch self {
        case .rectangle(var box):
            box.color = color
            return .rectangle(box)
        case .arrow(var segment):
            segment.color = color
            return .arrow(segment)
        case .ellipse(var box):
            box.color = color
            return .ellipse(box)
        case .line(var segment):
            segment.color = color
            return .line(segment)
        case .redact(let region, _):
            return .redact(region, fill: color)
        case .blur, .pixelate:
            return self
        }
    }

    /// The line width of a shape, in image pixels. Effects come back unchanged.
    func withLineWidth(_ width: CGFloat) -> Annotation {
        switch self {
        case .rectangle(var box):
            box.lineWidth = width
            return .rectangle(box)
        case .arrow(var segment):
            segment.lineWidth = width
            return .arrow(segment)
        case .ellipse(var box):
            box.lineWidth = width
            return .ellipse(box)
        case .line(var segment):
            segment.lineWidth = width
            return .line(segment)
        case .redact, .blur, .pixelate:
            return self
        }
    }

    /// A blur's radius or a pixelate's block, in image pixels. Everything else comes back
    /// unchanged.
    func withEffectParameter(_ value: CGFloat) -> Annotation {
        switch self {
        case .blur(let region, _):
            return .blur(region, radius: value)
        case .pixelate(let region, _):
            return .pixelate(region, block: value)
        case .rectangle, .ellipse, .arrow, .line, .redact:
            return self
        }
    }
}
