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

/// A freehand stroke: Pencil and Highlighter. `points` are the pointer samples after
/// `StrokeSmoothing.decimated`, in image pixels. The smoothed curve is rebuilt from them each time
/// it is drawn or hit (`StrokeSmoothing.path(for:)`); no CGPath is stored.
nonisolated struct Stroke: Codable, Equatable, Sendable {
    let id: UUID
    var points: [CGPoint]
    var color: RGBA
    var lineWidth: CGFloat
}

/// The area an effect covers.
nonisolated struct Region: Codable, Equatable, Sendable {
    let id: UUID
    var rect: CGRect
}

/// A text annotation. `origin` is the top-left corner of its frame (`TextLayout.frame(for:)`), and
/// `fontSize` is in image pixels: the points chosen in the UI times the capture scale. Lines are
/// split at newlines only; nothing wraps.
nonisolated struct TextBox: Codable, Equatable, Sendable {
    let id: UUID
    var string: String
    var origin: CGPoint
    var fontSize: CGFloat
    var color: RGBA
}

/// One edit on a capture. Effects (redact, blur, pixelate) belong to the base layer and render
/// beneath every drawing; drawings (rectangle, ellipse, arrow, line, pencil, highlighter, text)
/// render above them.
nonisolated enum Annotation: Identifiable, Codable, Equatable, Sendable {
    case rectangle(ShapeBox)
    case arrow(Segment)
    case ellipse(ShapeBox)
    case line(Segment)
    /// Freehand in the stroke colour.
    case pencil(Stroke)
    /// Freehand in a translucent colour that multiplies with what is beneath it.
    case highlighter(Stroke)
    case text(TextBox)
    case redact(Region, fill: RGBA)
    /// `radius` is the Gaussian sigma.
    case blur(Region, radius: CGFloat)
    case pixelate(Region, block: CGFloat)

    var id: UUID {
        switch self {
        case .rectangle(let box), .ellipse(let box): box.id
        case .arrow(let segment), .line(let segment): segment.id
        case .pencil(let stroke), .highlighter(let stroke): stroke.id
        case .text(let box): box.id
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _): region.id
        }
    }

    var isEffect: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pencil, .highlighter, .text: false
        case .redact, .blur, .pixelate: true
        }
    }

    /// The region an effect covers; nil for a drawing.
    var effectRect: CGRect? {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pencil, .highlighter, .text: nil
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
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .text: "Text"
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
        case .pencil(var stroke):
            stroke.points = stroke.points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
            return .pencil(stroke)
        case .highlighter(var stroke):
            stroke.points = stroke.points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
            return .highlighter(stroke)
        case .text(var box):
            box.origin = CGPoint(x: box.origin.x + delta.dx, y: box.origin.y + delta.dy)
            return .text(box)
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

    /// The same annotation under another id, for duplicate and paste. Every other field is kept.
    func withID(_ id: UUID) -> Annotation {
        switch self {
        case .rectangle(let box):
            .rectangle(ShapeBox(id: id, rect: box.rect, color: box.color, lineWidth: box.lineWidth))
        case .ellipse(let box):
            .ellipse(ShapeBox(id: id, rect: box.rect, color: box.color, lineWidth: box.lineWidth))
        case .arrow(let segment):
            .arrow(Segment(id: id, from: segment.from, to: segment.to, color: segment.color, lineWidth: segment.lineWidth))
        case .line(let segment):
            .line(Segment(id: id, from: segment.from, to: segment.to, color: segment.color, lineWidth: segment.lineWidth))
        case .pencil(let stroke):
            .pencil(Stroke(id: id, points: stroke.points, color: stroke.color, lineWidth: stroke.lineWidth))
        case .highlighter(let stroke):
            .highlighter(Stroke(id: id, points: stroke.points, color: stroke.color, lineWidth: stroke.lineWidth))
        case .text(let box):
            .text(TextBox(id: id, string: box.string, origin: box.origin, fontSize: box.fontSize, color: box.color))
        case .redact(let region, let fill):
            .redact(Region(id: id, rect: region.rect), fill: fill)
        case .blur(let region, let radius):
            .blur(Region(id: id, rect: region.rect), radius: radius)
        case .pixelate(let region, let block):
            .pixelate(Region(id: id, rect: region.rect), block: block)
        }
    }

    /// Every position and size times `factor`, around image pixel (0, 0): a paste from a capture
    /// at another scale keeps the annotation's size in points. A pixel block stays a whole pixel
    /// count of at least 1. Unchanged for a factor of 1 or a factor that is not a positive number.
    func scaled(by factor: CGFloat) -> Annotation {
        guard factor != 1, factor > 0, factor.isFinite else { return self }
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * factor, y: p.y * factor) }
        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * factor, y: r.minY * factor, width: r.width * factor, height: r.height * factor)
        }
        switch self {
        case .rectangle(var box):
            box.rect = rect(box.rect)
            box.lineWidth *= factor
            return .rectangle(box)
        case .ellipse(var box):
            box.rect = rect(box.rect)
            box.lineWidth *= factor
            return .ellipse(box)
        case .arrow(var segment):
            segment.from = point(segment.from)
            segment.to = point(segment.to)
            segment.lineWidth *= factor
            return .arrow(segment)
        case .line(var segment):
            segment.from = point(segment.from)
            segment.to = point(segment.to)
            segment.lineWidth *= factor
            return .line(segment)
        case .pencil(var stroke):
            stroke.points = stroke.points.map(point)
            stroke.lineWidth *= factor
            return .pencil(stroke)
        case .highlighter(var stroke):
            stroke.points = stroke.points.map(point)
            stroke.lineWidth *= factor
            return .highlighter(stroke)
        case .text(var box):
            box.origin = point(box.origin)
            box.fontSize *= factor
            return .text(box)
        case .redact(var region, let fill):
            region.rect = rect(region.rect)
            return .redact(region, fill: fill)
        case .blur(var region, let radius):
            region.rect = rect(region.rect)
            return .blur(region, radius: radius * factor)
        case .pixelate(var region, let block):
            region.rect = rect(region.rect)
            return .pixelate(region, block: max(1, (block * factor).rounded()))
        }
    }

    /// The stroke colour of a shape or the fill of a redaction. A highlighter keeps its alpha of
    /// 0.45 whatever the colour's own. Blur and pixelate have no colour and come back unchanged.
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
        case .pencil(var stroke):
            stroke.color = color
            return .pencil(stroke)
        case .highlighter(var stroke):
            stroke.color = EditorPalette.highlighterColor(from: color)
            return .highlighter(stroke)
        case .text(var box):
            box.color = color
            return .text(box)
        case .redact(let region, _):
            return .redact(region, fill: color)
        case .blur, .pixelate:
            return self
        }
    }

    /// The line width of a shape, in image pixels. Effects and text come back unchanged: text has a
    /// size, not a line width.
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
        case .pencil(var stroke):
            stroke.lineWidth = width
            return .pencil(stroke)
        case .highlighter(var stroke):
            stroke.lineWidth = width
            return .highlighter(stroke)
        case .text, .redact, .blur, .pixelate:
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
        case .rectangle, .ellipse, .arrow, .line, .pencil, .highlighter, .text, .redact:
            return self
        }
    }

    /// A text annotation at `size` image pixels, keeping its top-left corner. Everything else comes
    /// back unchanged.
    func withFontSize(_ size: CGFloat) -> Annotation {
        guard case .text(var box) = self else { return self }
        box.fontSize = size
        return .text(box)
    }
}
