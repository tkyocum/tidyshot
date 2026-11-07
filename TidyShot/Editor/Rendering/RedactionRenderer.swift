import CoreGraphics
import CoreImage
import Metal

/// One rendered effect. `image` covers `EffectTile.rect(for: effect, imageSize:)` of the base, in
/// native pixels, so it is drawn there with no scaling.
nonisolated struct EffectTile: Sendable {
    let effect: Annotation
    let image: CGImage

    /// The pixels a tile for `effect` covers: its rect rounded out to whole pixels and clipped to
    /// the image, top-left origin. Nil for a drawing, or when nothing of the rect is in the image.
    static func rect(for effect: Annotation, imageSize: CGSize) -> CGRect? {
        guard let rect = effect.effectRect else { return nil }
        let clipped = ImageRects.integral(rect, clippedTo: imageSize)
        return clipped.isEmpty ? nil : clipped
    }
}

/// Renders effect tiles. Under NonisolatedNonsendingByDefault a nonisolated `tile` runs on the
/// caller's executor, so a conformer that must leave the main actor is an actor (RedactionRenderer)
/// or marks the method `@concurrent` (the test fake).
nonisolated protocol TileRendering: Sendable {
    func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage?
}

/// Renders blur, pixelate and redact tiles with Core Image, off the main actor. It owns the app's
/// only CIContext; filters are built inside each call because CIFilter is not Sendable.
actor RedactionRenderer: TileRendering {
    static let shared = RedactionRenderer()

    private let context: CIContext
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: true, .name: "TidyShot.redaction"]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    /// The tile for `effect` over `base`, with every tile in `beneath` composited under it first,
    /// so a blur or pixelate over (or next to) a redaction samples the fill and never the pixels it
    /// hides. Nil for a drawing or a rect wholly outside the image.
    func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) -> CGImage? {
        let size = CGSize(width: base.width, height: base.height)
        guard let target = EffectTile.rect(for: effect, imageSize: size) else { return nil }
        let height = base.height
        let output: CIImage
        switch effect {
        case .redact(_, let fill):
            // Always opaque: a see-through redaction would not hide anything.
            guard let colour = CIColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: 1, colorSpace: sRGB) else {
                return nil
            }
            output = CIImage(color: colour)
        case .blur(_, let radius):
            // Only the sample rect is read. `beneath` holds every earlier effect and every redact,
            // earlier or later, that meets it, so a hidden pixel never reaches the blur, whatever
            // the reach of Core Image's kernel.
            let sample = ImageRects.bottomLeft(EffectGeometry.sampleRect(of: effect, imageSize: size), imageHeight: height)
            output = composite(base, beneath: beneath).cropped(to: sample)
                .clampedToExtent()
                .applyingGaussianBlur(sigma: Double(radius))
        case .pixelate(_, let block):
            output = mosaic(composite(base, beneath: beneath), block: block,
                            sample: EffectGeometry.sampleRect(of: effect, imageSize: size), imageHeight: height)
        default:
            return nil
        }
        let rect = ImageRects.bottomLeft(target, imageHeight: height)
        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        return context.createCGImage(output.cropped(to: rect), from: rect, format: .RGBA8, colorSpace: space, deferred: false)
    }

    /// Renders 1x1 blur and pixelate tiles, so the first real drag does not wait for Core Image
    /// to compile its kernels.
    func warmUp(with base: CGImage) {
        let pixel = Region(id: UUID(), rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        _ = tile(for: .blur(pixel, radius: 1), over: base, beneath: [])
        _ = tile(for: .pixelate(pixel, block: 1), over: base, beneath: [])
    }

    /// Frees the context's intermediates when the last editor closes.
    func clearCaches() {
        context.clearCaches()
    }

    /// `base` with each tile in `beneath` drawn over it at its own rect, in order.
    private func composite(_ base: CGImage, beneath: [EffectTile]) -> CIImage {
        let size = CGSize(width: base.width, height: base.height)
        var image = CIImage(cgImage: base)
        for tile in beneath {
            guard let rect = EffectTile.rect(for: tile.effect, imageSize: size) else { continue }
            let origin = ImageRects.bottomLeft(rect, imageHeight: base.height).origin
            image = CIImage(cgImage: tile.image)
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: image)
        }
        return image
    }

    /// An averaged mosaic: each `block` square of the grid anchored at image pixel (0,0) takes the
    /// mean of its pixels (exact for power-of-two blocks; Core Image's high-quality downsample
    /// widens the window slightly for other sizes). `sample` is the block-snapped rect clipped to
    /// the image, in top-left image pixels. Only it is read, and its edge pixels stand in for the
    /// part of a block outside the image, so every block stays opaque over opaque pixels.
    private func mosaic(_ input: CIImage, block: CGFloat, sample: CGRect, imageHeight: Int) -> CIImage {
        let side = max(1, block)
        let top = CGFloat(imageHeight)
        // Core Image's origin is the bottom left, so the grid is anchored at y = height. One pixel
        // of the small image is one block, and block edges land on whole small pixels.
        let toBlocks = CGAffineTransform(a: 1 / side, b: 0, c: 0, d: 1 / side, tx: 0, ty: -top / side)
        let fromBlocks = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: 0, ty: top)
        return input.cropped(to: ImageRects.bottomLeft(sample, imageHeight: imageHeight))
            .clampedToExtent()
            .transformed(by: toBlocks, highQualityDownsample: true)
            .samplingNearest()
            .transformed(by: fromBlocks)
    }
}
