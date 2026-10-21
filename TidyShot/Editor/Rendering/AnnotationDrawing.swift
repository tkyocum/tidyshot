import CoreGraphics
import CoreText

/// The one CoreGraphics routine for annotations. The canvas and the export both draw through it,
/// so the export equals the preview. `draw` and `drawPlaceholder` work in image pixels with a
/// top-left origin: the canvas concatenates `transform.affine` on its flipped view, and the
/// flattener flips its bitmap. `drawSelection` works in view space. Nothing here uses
/// NSGraphicsContext, so the export can run off the main actor.
nonisolated enum AnnotationDrawing {
    /// Selection handles are squares this many points wide at every zoom.
    static let handleSide: CGFloat = 8
    /// The dash pattern of a selected effect's outline, in points.
    static let outlineDash: [CGFloat] = [4, 4]

    /// Draws a drawing in image pixels. Effects draw nothing here, because they are tiles on the
    /// base layer. `scale` is the capture scale, which sizes the arrow head only; the other
    /// drawings are sized by their stored line widths.
    static func draw(_ annotation: Annotation, in context: CGContext, scale: CGFloat) {
        switch annotation {
        case .rectangle(let box):
            drawRectangle(box, in: context)
        case .arrow(let segment):
            drawArrow(segment, in: context, scale: scale)
        case .ellipse(let box):
            strokeEllipse(box, in: context)
        case .line(let segment):
            strokeLine(segment, in: context)
        case .pencil(let stroke):
            drawStroke(stroke, blend: .normal, in: context)
        case .highlighter(let stroke):
            drawStroke(stroke, blend: .multiply, in: context)
        case .text(let box):
            drawText(box, in: context)
        case .redact, .blur, .pixelate:
            break
        }
    }

    /// Stands in, in image pixels, for an effect whose tile has not rendered yet. A redaction
    /// shows its fill, always opaque, so a pending redaction hides what it covers. A blur or
    /// pixelate shows grey at 0.5 alpha. The rect is rounded out to whole pixels, as the tile's is.
    static func drawPlaceholder(for effect: Annotation, in context: CGContext) {
        guard let rect = effect.effectRect?.integral, !rect.isEmpty else { return }
        let colour: CGColor
        if case .redact(_, var fill) = effect {
            fill.alpha = 1
            colour = fill.cgColor
        } else {
            colour = CGColor(gray: 0.5, alpha: 0.5)
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(colour)
        context.fill(rect)
    }

    /// Selection chrome in view space, so it keeps its size at every zoom. A selected effect gets
    /// a dashed outline of its rect, white under black so it shows on any background, because a
    /// blur has no edge of its own. A selected stroke gets the same dashed outline around its
    /// bounds (it has no handles), and a selected text the same around its frame (text has no
    /// handles either). Every selection then gets an 8 pt white square with a dark
    /// border at each point of `HitTester.handles(for:)`. `scale` is the view's backing scale
    /// factor: edges snap to device pixels so the 1 pt lines stay sharp.
    static func drawSelection(for annotation: Annotation, transform: CanvasTransform, scale: CGFloat, in context: CGContext) {
        let device = max(scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * device).rounded() / device }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)
        if let rect = annotation.effectRect ?? AnnotationGeometry.strokeOutline(of: annotation) ?? textFrame(of: annotation) {
            let view = transform.viewRect(rect)
            let outline = CGRect(x: snap(view.minX), y: snap(view.minY),
                                 width: snap(view.maxX) - snap(view.minX),
                                 height: snap(view.maxY) - snap(view.minY)).insetBy(dx: 0.5, dy: 0.5)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.stroke(outline)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineDash(phase: 0, lengths: outlineDash)
            context.stroke(outline)
            context.setLineDash(phase: 0, lengths: [])
        }
        let half = handleSide / 2
        for point in HitTester.handles(for: annotation) {
            let centre = transform.viewPoint(point)
            let square = CGRect(x: snap(centre.x - half), y: snap(centre.y - half), width: handleSide, height: handleSide)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(square)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.6))
            context.stroke(square.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    /// A text annotation's frame, outlined when it is selected because text has no handles.
    private static func textFrame(of annotation: Annotation) -> CGRect? {
        guard case .text(let box) = annotation else { return nil }
        return TextLayout.frame(for: box)
    }

    /// Stroked inset by half the line width, so the stroke sits inside the rect. A box no wider
    /// or taller than the line is filled instead, because the inset rect would be empty.
    private static func drawRectangle(_ box: ShapeBox, in context: CGContext) {
        let rect = box.rect.standardized
        guard rect.width > 0, rect.height > 0, box.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if rect.width <= box.lineWidth || rect.height <= box.lineWidth {
            context.setFillColor(box.color.cgColor)
            context.fill(rect)
            return
        }
        context.setStrokeColor(box.color.cgColor)
        context.setLineWidth(box.lineWidth)
        context.setLineJoin(.miter)
        context.stroke(rect.insetBy(dx: box.lineWidth / 2, dy: box.lineWidth / 2))
    }

    /// A round-capped shaft from the tail to `ArrowGeometry.shaftEnd`, then the filled head
    /// triangle from `ArrowGeometry.head`.
    private static func drawArrow(_ segment: Segment, in context: CGContext, scale: CGFloat) {
        guard segment.from != segment.to, segment.lineWidth > 0 else { return }
        let head = ArrowGeometry.head(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
        let shaftEnd = ArrowGeometry.shaftEnd(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
        let colour = segment.color.cgColor
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(colour)
        context.setFillColor(colour)
        context.setLineWidth(segment.lineWidth)
        context.setLineCap(.round)
        context.move(to: segment.from)
        context.addLine(to: shaftEnd)
        context.strokePath()
        context.move(to: head.tip)
        context.addLine(to: head.left)
        context.addLine(to: head.right)
        context.closePath()
        context.fillPath()
    }

    /// CoreText on the bare context, which is in image pixels with a top-left origin (y down), so
    /// the text matrix flips the glyphs upright. Each line starts at its baseline origin from
    /// TextLayout, where CanvasView's NSTextView also put it while the text was typed. The text
    /// matrix is not part of the graphics state, so it is put back by hand.
    private static func drawText(_ box: TextBox, in context: CGContext) {
        guard box.fontSize > 0, !box.string.isEmpty else { return }
        let font = TextLayout.font(size: box.fontSize)
        let colour = box.color.cgColor
        let savedTextMatrix = context.textMatrix
        context.saveGState()
        defer {
            context.restoreGState()
            context.textMatrix = savedTextMatrix
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (text, origin) in zip(TextLayout.lines(of: box.string), TextLayout.baselineOrigins(for: box)) where !text.isEmpty {
            context.textPosition = origin
            CTLineDraw(TextLayout.line(text, font: font, color: colour), context)
        }
    }

    /// The smoothed path stroked once with round caps and joins. A single stroke operation paints
    /// the stroked outline as one shape, so a translucent highlighter that crosses itself is not
    /// painted twice. `.multiply` multiplies the colour with what is already in the context, so
    /// the highlighter can only darken: black stays black, white becomes the colour. The flattener
    /// draws into the capture's bitmap, where that is exactly what multiplies.
    private static func drawStroke(_ stroke: Stroke, blend: CGBlendMode, in context: CGContext) {
        guard !stroke.points.isEmpty, stroke.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(blend)
        context.setStrokeColor(stroke.color.cgColor)
        context.setLineWidth(stroke.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(StrokeSmoothing.path(for: stroke.points))
        context.strokePath()
    }

    /// Stroked inset by half the line width, so the stroke sits inside the rect, as the rectangle's
    /// does. An ellipse no wider or taller than the line is filled instead, because the inset
    /// ellipse would be empty.
    private static func strokeEllipse(_ box: ShapeBox, in context: CGContext) {
        let rect = box.rect.standardized
        guard rect.width > 0, rect.height > 0, box.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if rect.width <= box.lineWidth || rect.height <= box.lineWidth {
            context.setFillColor(box.color.cgColor)
            context.fillEllipse(in: rect)
            return
        }
        context.setStrokeColor(box.color.cgColor)
        context.setLineWidth(box.lineWidth)
        context.strokeEllipse(in: rect.insetBy(dx: box.lineWidth / 2, dy: box.lineWidth / 2))
    }

    /// A straight stroke from `from` to `to` with round caps and no head.
    private static func strokeLine(_ segment: Segment, in context: CGContext) {
        guard segment.from != segment.to, segment.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(segment.color.cgColor)
        context.setLineWidth(segment.lineWidth)
        context.setLineCap(.round)
        context.move(to: segment.from)
        context.addLine(to: segment.to)
        context.strokePath()
    }
}
