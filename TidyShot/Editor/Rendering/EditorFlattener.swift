import CoreGraphics
import Foundation

/// Burns the effect tiles, the spotlight overlay and the drawings into a copy of the capture, at
/// the capture's own pixel size, or at the crop's when the document has one, for Save, Save As…,
/// Copy and Upload. `EditorModel.renderExport` calls it inside
/// `Task.detached(priority: .userInitiated)`. It uses no NSGraphicsContext, which is MainActor.
///
/// For an 8-bit RGB base, every pixel outside the effects, the drawings and the overlay equals the
/// base byte for byte, alpha included, and alpha survives everywhere, under the overlay too (spec
/// 2.12 amends 2.6 Export): window captures keep their transparent corners and shadow margins.
/// Each tile replaces the pixels of its rect (blend mode copy), so nothing of the base shows
/// through a tile, and a solid redaction over a transparent corner paints opaque pixels, which the
/// overlay then dims like any other.
nonisolated enum EditorFlattener {
    /// Nil when no bitmap can be made, or when an effect inside the image has no tile for its
    /// current value: the export fails rather than ship the pixels that effect should hide. An
    /// effect wholly outside the image needs no tile. `tiles` comes from
    /// `RedactionTileCache.allTiles(for:)`, one per effect, each covering
    /// `ImageRects.integral(effectRect, clippedTo:)` in native pixels.
    static func flatten(base: CGImage, tiles: [EffectTile], document: AnnotationDocument, scale: CGFloat) -> CGImage? {
        let width = base.width
        let height = base.height
        let size = CGSize(width: width, height: height)
        guard let context = makeContext(width: width, height: height, preferred: base.colorSpace) else { return nil }
        context.interpolationQuality = .none

        // 1. The base, copied in, in `ImageTiling` strips: drawing converts the pixels through a
        // buffer the size of what is drawn, so a 65,536 px capture drawn whole would briefly need
        // another 811 MB. CoreGraphics coordinates here: origin bottom left.
        context.setBlendMode(.copy)
        for strip in ImageTiling.crops(of: base) {
            context.draw(strip.image, in: ImageRects.bottomLeft(strip.rect, imageHeight: height))
        }

        // 2. The tiles in creation order, each replacing its rect.
        let tileByID = Dictionary(tiles.map { ($0.effect.id, $0) }, uniquingKeysWith: { _, last in last })
        for effect in document.effects {
            guard let effectRect = effect.effectRect else { continue }
            let rect = ImageRects.integral(effectRect, clippedTo: size)
            guard !rect.isEmpty else { continue }
            guard let tile = tileByID[effect.id], tile.effect == effect else { return nil }
            context.draw(tile.image, in: ImageRects.bottomLeft(rect, imageHeight: height))
        }

        // 3. The spotlight overlay, then the drawings, in top-left image pixels as on the canvas,
        // through the same routines. The overlay is one transparency layer as big as the clip, so
        // it is drawn once per `ImageTiling` strip: whole, a 65,536 px capture would allocate
        // another 811 MB layer on top of the bitmap. The strips are integral, so they meet without
        // a seam.
        context.setBlendMode(.normal)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        if !document.spotlights.isEmpty {
            let shapes = document.spotlights.compactMap(\.spotlightShape)
            let imageRect = CGRect(origin: .zero, size: size)
            for strip in ImageTiling.tiles(width: width, height: height) {
                context.saveGState()
                context.clip(to: strip)
                AnnotationDrawing.drawSpotlightOverlay(shapes, dim: document.effectiveSpotlightDim, in: context,
                                                       imageRect: imageRect, coverage: nil)
                context.restoreGState()
            }
        }
        for drawing in document.drawings {
            AnnotationDrawing.draw(drawing, in: context, scale: scale)
        }
        guard let flattened = context.makeImage() else { return nil }
        // 4. The crop, last. Effects and drawings render on the whole capture first, so a blur or a
        // redaction cut by the crop's edge has exactly the pixels it has uncropped. CGImage's
        // `cropping(to:)` takes the model's top-left rect as it is.
        guard let crop = CropGeometry.integralCrop(document.crop, in: size) else { return flattened }
        return flattened.cropping(to: crop)
    }

    /// An 8-bit premultiplied RGBA bitmap in the base's colour space when that space is RGB and
    /// CoreGraphics accepts it, otherwise in sRGB; drawing the base then converts it once. A grey
    /// base would otherwise give a grey bitmap and grey arrows.
    private static func makeContext(width: Int, height: Int, preferred: CGColorSpace?) -> CGContext? {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let preferred, preferred.model == .rgb,
           let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: preferred, bitmapInfo: info) {
            return context
        }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB, bitmapInfo: info)
    }
}
