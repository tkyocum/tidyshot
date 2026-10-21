import CoreGraphics
import Foundation
import Synchronization

/// Burns the effect tiles and the drawings into a copy of the capture, at the capture's own pixel
/// size, for Save, Save As…, Copy and Upload. `EditorModel.renderExport` calls it inside
/// `Task.detached(priority: .userInitiated)`. It uses no NSGraphicsContext, which is MainActor.
///
/// For an 8-bit RGB base, every pixel outside the effects and drawings equals the base byte for
/// byte, alpha included, so window captures keep their transparent corners. Each tile replaces
/// the pixels of its rect (blend mode copy), so nothing of the base shows through a tile, and a
/// solid redaction over a transparent corner paints opaque pixels.
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
        logColourSpaceOnce(base: base, output: context)
        context.interpolationQuality = .none

        // 1. The base, copied in. CoreGraphics coordinates here: origin bottom left.
        context.setBlendMode(.copy)
        context.draw(base, in: CGRect(origin: .zero, size: size))

        // 2. The tiles in creation order, each replacing its rect.
        let tileByID = Dictionary(tiles.map { ($0.effect.id, $0) }, uniquingKeysWith: { _, last in last })
        for effect in document.effects {
            guard let effectRect = effect.effectRect else { continue }
            let rect = ImageRects.integral(effectRect, clippedTo: size)
            guard !rect.isEmpty else { continue }
            guard let tile = tileByID[effect.id], tile.effect == effect else { return nil }
            context.draw(tile.image, in: ImageRects.bottomLeft(rect, imageHeight: height))
        }

        // 3. The drawings, in top-left image pixels as on the canvas, through the same routine.
        context.setBlendMode(.normal)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for drawing in document.drawings {
            AnnotationDrawing.draw(drawing, in: context, scale: scale)
        }
        return context.makeImage()
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

    #if DEBUG
    /// Set by the first flatten, so the colour space real captures carry is logged once per run.
    private static let loggedColourSpace = Atomic<Bool>(false)
    #endif

    private static func logColourSpaceOnce(base: CGImage, output: CGContext) {
        #if DEBUG
        guard !loggedColourSpace.exchange(true, ordering: .relaxed) else { return }
        let baseName = base.colorSpace?.name.map { $0 as String } ?? "none"
        let outputName = output.colorSpace?.name.map { $0 as String } ?? "none"
        NSLog("EditorFlattener: base colour space \(baseName), flattened in \(outputName)")
        #endif
    }
}
