import CoreGraphics

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
    /// base layer. `scale` is the capture scale, which sizes the arrow head.
    static func draw(_ annotation: Annotation, in context: CGContext, scale: CGFloat) {
        switch annotation {
        case .rectangle(let box):
            drawRectangle(box, in: context)
        case .arrow(let segment):
            drawArrow(segment, in: context, scale: scale)
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
    /// blur has no edge of its own. Every selection then gets an 8 pt white square with a dark
    /// border at each point of `HitTester.handles(for:)`. `scale` is the view's backing scale
    /// factor: edges snap to device pixels so the 1 pt lines stay sharp.
    static func drawSelection(for annotation: Annotation, transform: CanvasTransform, scale: CGFloat, in context: CGContext) {
        let device = max(scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * device).rounded() / device }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)
        if let rect = annotation.effectRect {
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
}
