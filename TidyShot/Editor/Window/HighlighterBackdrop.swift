import CoreGraphics

/// The drawing behind `CanvasView.drawHighlighterBackdrops`, apart from the view so a test can
/// run it into a bitmap.
enum HighlighterBackdrop {
    /// Draws `layers` (a capture's base tiles, then the shown effect tiles; rects in image
    /// pixels, y-down, as the CTM) into the context's current clip. Anti-aliasing is off: at a
    /// fractional zoom the join between two strips falls inside a device row, and with it on both
    /// strips would cover that row only partly, leaving the backdrop partly transparent there, so
    /// the multiply that follows would show a hairline the export does not have. Callers save and
    /// restore the graphics state around it. Only the part of each layer that can show is drawn:
    /// the clip's integral bounds grown by 2 px (so the crop's edges lie outside the clip),
    /// not a whole 16,384-row strip.
    nonisolated static func draw(_ layers: [(rect: CGRect, image: CGImage)], in context: CGContext) {
        context.setShouldAntialias(false)
        let wanted = context.boundingBoxOfClipPath.integral.insetBy(dx: -2, dy: -2)
        for layer in layers {
            let area = wanted.intersection(layer.rect)
            guard !area.isNull, !area.isEmpty, layer.rect.width > 0, layer.rect.height > 0 else { continue }
            // Image pixels per rect unit, 1 when the layer's image is its rect's size.
            let scaleX = CGFloat(layer.image.width) / layer.rect.width
            let scaleY = CGFloat(layer.image.height) / layer.rect.height
            let local = CGRect(x: (area.minX - layer.rect.minX) * scaleX, y: (area.minY - layer.rect.minY) * scaleY,
                               width: area.width * scaleX, height: area.height * scaleY).integral
            guard let piece = layer.image.cropping(to: local) else { continue }
            let target = CGRect(x: layer.rect.minX + local.minX / scaleX, y: layer.rect.minY + local.minY / scaleY,
                                width: local.width / scaleX, height: local.height / scaleY)
            context.saveGState()
            // `CGContext.draw` assumes y-up and the CTM here is y-down: draw through a local flip.
            context.translateBy(x: target.minX, y: target.maxY)
            context.scaleBy(x: 1, y: -1)
            context.draw(piece, in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
            context.restoreGState()
        }
    }
}
