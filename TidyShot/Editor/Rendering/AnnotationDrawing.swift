import CoreGraphics
import CoreText

/// The one CoreGraphics routine for annotations. The canvas and the export both draw through it,
/// so the export equals the preview. `draw`, `drawPlaceholder` and `drawSpotlightOverlay` work in
/// image pixels with a top-left origin: the canvas concatenates `transform.affine` on its flipped
/// view, and the flattener flips its bitmap. `drawSelection` and `drawSpotlightOutline` work in
/// view space. Nothing here uses NSGraphicsContext, so the export can run off the main actor.
nonisolated enum AnnotationDrawing {
    /// Selection handles are squares this many points wide at every zoom.
    static let handleSide: CGFloat = 8
    /// The dash pattern of a selected effect's outline, in points.
    static let outlineDash: [CGFloat] = [4, 4]
    /// The width of a counter's white ring, in points.
    static let counterRingPoints: CGFloat = 1.5

    /// Draws a drawing in image pixels. Effects draw nothing here, because they are tiles on the
    /// base layer, and neither does a spotlight, which the overlay draws. `scale` is the capture
    /// scale, which sizes the arrow head and a counter's ring only; the other drawings are sized by
    /// their stored line widths.
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
        case .counter(let mark):
            drawCounter(mark, in: context, scale: scale)
        case .redact, .blur, .pixelate, .spotlight:
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

    /// Selection chrome in view space, so it keeps its size at every zoom. The dashed outline,
    /// white under black so it shows on any background, goes around
    /// `AnnotationGeometry.selectionOutline(of:)`: a selected effect's rect, because a blur has no
    /// edge of its own; a stroke's bounds and a text's frame, which have no handles; a spotlight's
    /// rect, since its outline is never drawn into the image; and a counter's bounding square, as it
    /// has no handles either. Every selection then gets an 8 pt white square with a dark border at
    /// each point of `HitTester.handles(for:)`. `scale` is the view's backing scale factor: edges
    /// snap to device pixels so the 1 pt lines stay sharp.
    static func drawSelection(for annotation: Annotation, transform: CanvasTransform, scale: CGFloat, in context: CGContext) {
        if let rect = AnnotationGeometry.selectionOutline(of: annotation) {
            // Null when the rect is under a point wide or tall: then there is no outline to draw.
            let outline = snapped(transform.viewRect(rect), scale: scale).insetBy(dx: 0.5, dy: 0.5)
            if !outline.isNull { strokeTwoTone(CGPath(rect: outline, transform: nil), in: context) }
        }
        drawHandles(HitTester.handles(for: annotation), transform: transform, scale: scale, in: context)
    }

    /// The Spotlight tool's outline of one spotlight, in view space: the shape's own edge (the
    /// rect, or the ellipse in it), 1 pt, white under black dashes as the selection outline is
    /// drawn. Chrome only; the shape's edge is never drawn into the image. `scale` is the view's
    /// backing scale factor: the rect snaps to device pixels, as the selection outline's does.
    static func drawSpotlightOutline(_ shape: SpotlightShape, transform: CanvasTransform, scale: CGFloat,
                                     in context: CGContext) {
        let outline = snapped(transform.viewRect(shape.rect.standardized), scale: scale).insetBy(dx: 0.5, dy: 0.5)
        guard !outline.isNull else { return }
        strokeTwoTone(shape.isEllipse ? CGPath(ellipseIn: outline, transform: nil) : CGPath(rect: outline, transform: nil),
                      in: context)
    }

    /// `path` stroked 1 pt white, then in black `outlineDash` dashes over it, so it shows on any
    /// background.
    private static func strokeTwoTone(_ path: CGPath, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.strokePath()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineDash(phase: 0, lengths: outlineDash)
        context.strokePath()
    }

    /// The spotlight overlay (spec 2.12, Rendering), in image pixels with a top-left origin under
    /// whatever CTM the caller set up for them: black at `dim` over `imageRect`, with each shape (its
    /// rect, or the ellipse in it) cleared, so overlapping holes form one union. It is one
    /// transparency layer, which is as big as the clip, so it sets no clip of its own and every
    /// caller sets one. The state is saved and restored.
    ///
    /// The overlay darkens the picture, never its transparency:
    /// - `coverage` nil (the export): the layer composites with `.sourceAtop`, which keeps the
    ///   destination's alpha exactly and on an opaque pixel equals `.normal`. Probed at a 0.5 dim,
    ///   alpha 0 stays `[0,0,0,0]`, and alpha 128 stays 128 with its colour halved.
    /// - `coverage` set (the canvas): the canvas holds none of the capture's pixels, so `.sourceAtop`
    ///   would draw nothing and the layer composites with `.normal`. When the list is not empty
    ///   (the base tiles, then the shown effect tiles), it is drawn through `HighlighterBackdrop.draw`
    ///   into a nested layer composited `.destinationIn`, which multiplies the overlay's alpha by
    ///   the capture's: none over a transparent corner, the dim over opaque pixels, and full over a
    ///   redaction on a corner, as in the export. An empty list, for a base with no alpha channel,
    ///   skips that layer. Partly transparent pixels come out a little darker than in the export:
    ///   probed, alpha 128 shows as 160 on the canvas at a 0.5 dim.
    ///
    /// A blend mode set before a layer begins is the one it composites with; beginning a layer
    /// resets it to `.normal`, so each fill inside sets the mode it needs.
    static func drawSpotlightOverlay(_ shapes: [SpotlightShape], dim: Double, in context: CGContext, imageRect: CGRect,
                                     coverage: [(rect: CGRect, image: CGImage)]?) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(coverage == nil ? .sourceAtop : .normal)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setBlendMode(.normal)
        context.setFillColor(CGColor(gray: 0, alpha: dim))
        context.fill(imageRect)
        context.setBlendMode(.clear)
        for shape in shapes {
            let rect = shape.rect.standardized
            if shape.isEllipse {
                context.fillEllipse(in: rect)
            } else {
                context.fill(rect)
            }
        }
        if let coverage, !coverage.isEmpty {
            context.setBlendMode(.destinationIn)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setBlendMode(.normal)
            HighlighterBackdrop.draw(coverage, in: context)
            context.endTransparencyLayer()
        }
        context.endTransparencyLayer()
    }

    /// An 8 pt white square with a dark border at each of `points` (image pixels), in view space.
    /// `scale` is the view's backing scale factor; edges snap to device pixels.
    static func drawHandles(_ points: [CGPoint], transform: CanvasTransform, scale: CGFloat, in context: CGContext) {
        let device = max(scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * device).rounded() / device }
        let half = handleSide / 2
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)
        for point in points {
            let centre = transform.viewPoint(point)
            let square = CGRect(x: snap(centre.x - half), y: snap(centre.y - half), width: handleSide, height: handleSide)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(square)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.6))
            context.stroke(square.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    /// How dark the image outside a crop being edited gets: black at this alpha.
    static let cropDimAlpha: CGFloat = 0.5

    /// The Crop tool's chrome, in view space: the image outside `crop` dimmed, a 1 pt white edge on
    /// the crop, and its eight handles. `scale` is the view's backing scale factor.
    static func drawCropChrome(crop: CGRect, imageSize: CGSize, transform: CanvasTransform, scale: CGFloat,
                               in context: CGContext) {
        let image = snapped(transform.viewRect(CGRect(origin: .zero, size: imageSize)), scale: scale)
        let kept = snapped(transform.viewRect(crop), scale: scale)
        context.saveGState()
        defer { context.restoreGState() }
        context.addRect(image)
        context.addRect(kept)
        context.setFillColor(CGColor(gray: 0, alpha: cropDimAlpha))
        context.fillPath(using: .evenOdd)
        context.setLineWidth(1)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.stroke(kept.insetBy(dx: 0.5, dy: 0.5))
        drawHandles(HitTester.boxHandles(crop), transform: transform, scale: scale, in: context)
    }

    /// An applied crop, outside the Crop tool: everything in `bounds` (view space) outside `crop`
    /// is painted `color`, the window's background, so the canvas shows what export keeps. Drawings
    /// and tiles beneath are hidden, not removed.
    static func drawCropCover(keeping crop: CGRect, bounds: CGRect, transform: CanvasTransform, color: CGColor,
                              scale: CGFloat, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addRect(bounds)
        context.addRect(snapped(transform.viewRect(crop), scale: scale))
        context.setFillColor(color)
        context.fillPath(using: .evenOdd)
    }

    /// `rect`'s edges on device pixels at `scale`.
    private static func snapped(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let device = max(scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * device).rounded() / device }
        return CGRect(x: snap(rect.minX), y: snap(rect.minY),
                      width: snap(rect.maxX) - snap(rect.minX), height: snap(rect.maxY) - snap(rect.minY))
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

    /// A circle filled in the counter's colour, with a white ring `counterRingPoints × scale` wide
    /// stroked inset by half its width, so nothing paints outside the diameter. The number goes on
    /// top in `EditorPalette.contrastingTextColor(for:)`, at `CounterLayout.fontSize`, drawn as
    /// `drawText` draws: CoreText on the bare context, the text matrix flipping the glyphs upright
    /// and put back by hand. It is centred by the line's typographic width across and by the
    /// font's cap height down, so the digits sit on the centre.
    private static func drawCounter(_ mark: CounterMark, in context: CGContext, scale: CGFloat) {
        guard mark.diameter > 0 else { return }
        let radius = mark.diameter / 2
        let circle = CGRect(x: mark.center.x - radius, y: mark.center.y - radius, width: mark.diameter, height: mark.diameter)
        let ring = counterRingPoints * scale
        let savedTextMatrix = context.textMatrix
        context.saveGState()
        defer {
            context.restoreGState()
            context.textMatrix = savedTextMatrix
        }
        context.setFillColor(mark.color.cgColor)
        context.fillEllipse(in: circle)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(ring)
        context.strokeEllipse(in: circle.insetBy(dx: ring / 2, dy: ring / 2))

        let fontSize = CounterLayout.fontSize(number: mark.number, diameter: mark.diameter)
        guard fontSize > 0 else { return }
        let font = TextLayout.font(size: fontSize)
        let line = TextLayout.line(String(mark.number), font: font,
                                   color: EditorPalette.contrastingTextColor(for: mark.color).cgColor)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: mark.center.x - width / 2, y: mark.center.y + CTFontGetCapHeight(font) / 2)
        CTLineDraw(line, context)
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
