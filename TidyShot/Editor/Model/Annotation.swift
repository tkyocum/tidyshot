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

/// A hole in the spotlight overlay: the rect, or the ellipse inscribed in it when `isEllipse`. It
/// has no colour and no line width; the document's `spotlightDim` sets how dark the rest gets.
nonisolated struct SpotlightShape: Codable, Equatable, Sendable {
    let id: UUID
    var rect: CGRect
    var isEllipse: Bool
}

/// A numbered circle (4c). `center` and `diameter` are image pixels; `number` is the step it shows.
nonisolated struct CounterMark: Codable, Equatable, Sendable {
    let id: UUID
    var center: CGPoint
    var number: Int
    var diameter: CGFloat
    var color: RGBA
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
/// beneath every drawing; drawings (rectangle, ellipse, arrow, line, pencil, highlighter, text,
/// counter) render above them. Spotlights are neither: they cut holes in one overlay painted
/// between the two.
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
    case spotlight(SpotlightShape)
    case counter(CounterMark)

    var id: UUID {
        switch self {
        case .rectangle(let box), .ellipse(let box): box.id
        case .arrow(let segment), .line(let segment): segment.id
        case .pencil(let stroke), .highlighter(let stroke): stroke.id
        case .text(let box): box.id
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _): region.id
        case .spotlight(let shape): shape.id
        case .counter(let mark): mark.id
        }
    }

    var isEffect: Bool {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pencil, .highlighter, .text, .spotlight, .counter: false
        case .redact, .blur, .pixelate: true
        }
    }

    /// The region an effect covers; nil for a drawing and a spotlight.
    var effectRect: CGRect? {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pencil, .highlighter, .text, .spotlight, .counter: nil
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _): region.rect
        }
    }

    var spotlightShape: SpotlightShape? {
        if case .spotlight(let shape) = self { return shape }
        return nil
    }

    var counterMark: CounterMark? {
        if case .counter(let mark) = self { return mark }
        return nil
    }

    var isSpotlight: Bool { spotlightShape != nil }

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
        case .spotlight: "Spotlight"
        case .counter: "Counter"
        }
    }

    /// `self` with its payload changed by the closure for the payload's type, run on a copy; a
    /// blur's radius and a pixelate's block go through `radius` and `block`. The twelve cases are
    /// seven payload types, so this is the one switch behind `moved`, `scaled`, `withColor`,
    /// `withLineWidth` and `HitTester.resized`; a kind whose closure is left out comes back
    /// unchanged.
    func mapping(box: (inout ShapeBox) -> Void = { _ in },
                 segment: (inout Segment) -> Void = { _ in },
                 stroke: (inout Stroke) -> Void = { _ in },
                 text: (inout TextBox) -> Void = { _ in },
                 region: (inout Region) -> Void = { _ in },
                 spotlight: (inout SpotlightShape) -> Void = { _ in },
                 counter: (inout CounterMark) -> Void = { _ in },
                 radius: (CGFloat) -> CGFloat = { $0 },
                 block: (CGFloat) -> CGFloat = { $0 }) -> Annotation {
        switch self {
        case .rectangle(var payload): box(&payload); return .rectangle(payload)
        case .ellipse(var payload): box(&payload); return .ellipse(payload)
        case .arrow(var payload): segment(&payload); return .arrow(payload)
        case .line(var payload): segment(&payload); return .line(payload)
        case .pencil(var payload): stroke(&payload); return .pencil(payload)
        case .highlighter(var payload): stroke(&payload); return .highlighter(payload)
        case .text(var payload): text(&payload); return .text(payload)
        case .redact(var payload, let fill): region(&payload); return .redact(payload, fill: fill)
        case .blur(var payload, let value): region(&payload); return .blur(payload, radius: radius(value))
        case .pixelate(var payload, let value): region(&payload); return .pixelate(payload, block: block(value))
        case .spotlight(var payload): spotlight(&payload); return .spotlight(payload)
        case .counter(var payload): counter(&payload); return .counter(payload)
        }
    }

    /// The same annotation shifted by `delta`: a rect's origin, both ends of a segment, or a
    /// counter's centre.
    func moved(by delta: CGVector) -> Annotation {
        func shifted(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + delta.dx, y: point.y + delta.dy) }
        func shifted(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: delta.dx, dy: delta.dy) }
        return mapping(box: { $0.rect = shifted($0.rect) },
                       segment: { $0.from = shifted($0.from); $0.to = shifted($0.to) },
                       stroke: { $0.points = $0.points.map(shifted) },
                       text: { $0.origin = shifted($0.origin) },
                       region: { $0.rect = shifted($0.rect) },
                       spotlight: { $0.rect = shifted($0.rect) },
                       counter: { $0.center = shifted($0.center) })
    }

    /// The same annotation under another id, for duplicate and paste. Every other field is kept,
    /// a counter's number included.
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
        case .spotlight(let shape):
            .spotlight(SpotlightShape(id: id, rect: shape.rect, isEllipse: shape.isEllipse))
        case .counter(let mark):
            .counter(CounterMark(id: id, center: mark.center, number: mark.number, diameter: mark.diameter, color: mark.color))
        }
    }

    /// Every position and size times `factor`, around image pixel (0, 0): a paste from a capture
    /// at another scale keeps the annotation's size in points. A pixel block stays a whole pixel
    /// count of at least 1, and a counter keeps its number. Unchanged for a factor of 1 or a factor
    /// that is not a positive number.
    func scaled(by factor: CGFloat) -> Annotation {
        guard factor != 1, factor > 0, factor.isFinite else { return self }
        func scaled(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * factor, y: point.y * factor) }
        func scaled(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * factor, y: rect.minY * factor, width: rect.width * factor, height: rect.height * factor)
        }
        return mapping(box: { $0.rect = scaled($0.rect); $0.lineWidth *= factor },
                       segment: { $0.from = scaled($0.from); $0.to = scaled($0.to); $0.lineWidth *= factor },
                       stroke: { $0.points = $0.points.map(scaled); $0.lineWidth *= factor },
                       text: { $0.origin = scaled($0.origin); $0.fontSize *= factor },
                       region: { $0.rect = scaled($0.rect) },
                       spotlight: { $0.rect = scaled($0.rect) },
                       counter: { $0.center = scaled($0.center); $0.diameter *= factor },
                       radius: { $0 * factor },
                       block: { max(1, ($0 * factor).rounded()) })
    }

    /// The stroke colour of a shape, the fill of a redaction or a counter. A highlighter keeps its
    /// alpha of 0.45 whatever the colour's own. Blur, pixelate and a spotlight have no colour and
    /// come back unchanged.
    func withColor(_ color: RGBA) -> Annotation {
        switch self {
        case .highlighter(var stroke):
            stroke.color = EditorPalette.highlighterColor(from: color)
            return .highlighter(stroke)
        case .redact(let region, _):
            return .redact(region, fill: color)
        case .blur, .pixelate, .spotlight:
            return self
        case .rectangle, .ellipse, .arrow, .line, .pencil, .text, .counter:
            return mapping(box: { $0.color = color }, segment: { $0.color = color }, stroke: { $0.color = color },
                           text: { $0.color = color }, counter: { $0.color = color })
        }
    }

    /// The line width of a shape, in image pixels. Effects, text, spotlights and counters come back
    /// unchanged: text and a counter have a size, not a line width, and a spotlight has no line.
    func withLineWidth(_ width: CGFloat) -> Annotation {
        mapping(box: { $0.lineWidth = width }, segment: { $0.lineWidth = width }, stroke: { $0.lineWidth = width })
    }

    /// A blur's radius or a pixelate's block, in image pixels. Everything else comes back
    /// unchanged.
    func withEffectParameter(_ value: CGFloat) -> Annotation {
        switch self {
        case .blur(let region, _):
            return .blur(region, radius: value)
        case .pixelate(let region, _):
            return .pixelate(region, block: value)
        case .rectangle, .ellipse, .arrow, .line, .pencil, .highlighter, .text, .redact, .spotlight, .counter:
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

    /// A spotlight whose hole is the ellipse in its rect when `isEllipse`, else the rect itself.
    /// Everything else comes back unchanged.
    func withSpotlightShape(isEllipse: Bool) -> Annotation {
        guard case .spotlight(var shape) = self else { return self }
        shape.isEllipse = isEllipse
        return .spotlight(shape)
    }

    /// A counter `diameter` image pixels across, about the same centre. Everything else comes back
    /// unchanged.
    func withCounterDiameter(_ diameter: CGFloat) -> Annotation {
        guard case .counter(var mark) = self else { return self }
        mark.diameter = diameter
        return .counter(mark)
    }

    /// A new annotation as it joins `document`: a counter takes the document's next number, whatever
    /// number it arrived with, so Add, duplicate and paste never repeat one (spec 2.12). Everything
    /// else, and the id, comes back unchanged.
    func renumbered(in document: AnnotationDocument) -> Annotation {
        guard case .counter(var mark) = self else { return self }
        mark.number = document.nextCounterNumber
        return .counter(mark)
    }
}
