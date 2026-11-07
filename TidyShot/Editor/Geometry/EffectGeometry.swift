import CoreGraphics

/// Which image pixels an effect reads, in the model's top-left image pixels. A blur or pixelate
/// tile depends on the base and on every earlier effect, and every redact, whose tile meets its
/// sample rect: `RedactionTileCache` keys tiles by those effects, and `RedactionRenderer`
/// composites their tiles beneath.
nonisolated enum EffectGeometry {
    /// A Gaussian blur reads this many sigmas beyond its rect.
    static let blurReachInSigmas: CGFloat = 3

    /// The pixels `effect`'s tile depends on, integral and clipped to the image:
    /// - blur: the rect grown by `ceil(3 * radius)` on every side;
    /// - pixelate: `mosaicRect(rect, block:)`, the whole cells the rect touches;
    /// - redact: the rect itself.
    ///
    /// A drawing has no tile and samples nothing: `.zero`. Compare the result with
    /// `ImageRects.integral(_:clippedTo:)` of an earlier effect's rect, the pixels its tile covers.
    static func sampleRect(of effect: Annotation, imageSize: CGSize) -> CGRect {
        switch effect {
        case .redact(let region, _):
            return ImageRects.integral(region.rect, clippedTo: imageSize)
        case .blur(let region, let radius):
            let reach = (blurReachInSigmas * radius).rounded(.up)
            return ImageRects.integral(region.rect.insetBy(dx: -reach, dy: -reach), clippedTo: imageSize)
        case .pixelate(let region, let block):
            return ImageRects.integral(mosaicRect(region.rect, block: block), clippedTo: imageSize)
        default:
            return .zero
        }
    }

    /// `rect` grown outward to whole `block` by `block` cells of a grid anchored at image pixel
    /// (0, 0), the top-left corner, so the cells under a region stay put while it is dragged.
    /// Not clipped to the image. `block` is a whole number of pixels; below 1 it counts as 1.
    /// In Core Image's bottom-left space this grid is anchored at y = image height, so a renderer
    /// moves `ImageRects.bottomLeft(mosaicRect(...))` to the origin before scaling by `1 / block`.
    static func mosaicRect(_ rect: CGRect, block: CGFloat) -> CGRect {
        guard !rect.isEmpty, !rect.isInfinite else { return .zero }
        let cell = max(block, 1)
        let minX = (rect.minX / cell).rounded(.down) * cell
        let minY = (rect.minY / cell).rounded(.down) * cell
        let maxX = (rect.maxX / cell).rounded(.up) * cell
        let maxY = (rect.maxY / cell).rounded(.up) * cell
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
