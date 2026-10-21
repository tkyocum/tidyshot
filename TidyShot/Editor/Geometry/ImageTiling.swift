import CoreGraphics

/// Splits an image into rects no side of which exceeds a GPU texture, so the editor can show a
/// tall scrolling capture as stacked layers (`BaseImageView`) and copy it in strips
/// (`EditorFlattener`). Rects are in image pixels, top-left origin, as `CGImage.cropping(to:)`
/// takes them.
nonisolated enum ImageTiling {
    /// The longest side of one tile. Metal takes 16,384 px on Apple GPUs before family 9 and on the
    /// Intel Macs' GPUs, and 32,768 on the M5 Max this was measured on (`MTLTextureDescriptor`
    /// validation rejects 32,769), so 16,384 works on every Mac that runs macOS 26.
    static let maxTileSide = 16_384

    /// Rows of tiles, top to bottom, each row left to right. Every tile is `maxSide` square except
    /// along the right and bottom edges, which take the remainder. Together they cover the image
    /// exactly once. One tile for an image within `maxSide`; none for an empty image.
    static func tiles(width: Int, height: Int, maxSide: Int = maxTileSide) -> [CGRect] {
        guard width > 0, height > 0, maxSide > 0 else { return [] }
        return stride(from: 0, to: height, by: maxSide).flatMap { y in
            stride(from: 0, to: width, by: maxSide).map { x in
                CGRect(x: x, y: y, width: min(maxSide, width - x), height: min(maxSide, height - y))
            }
        }
    }

    /// `image` cut at `tiles(width:height:maxSide:)`. The crops share the image's pixels. An image
    /// within `maxSide` comes back as itself.
    static func crops(of image: CGImage, maxSide: Int = maxTileSide) -> [(rect: CGRect, image: CGImage)] {
        let rects = tiles(width: image.width, height: image.height, maxSide: maxSide)
        if rects.count == 1, let only = rects.first { return [(rect: only, image: image)] }
        return rects.compactMap { rect in image.cropping(to: rect).map { (rect: rect, image: $0) } }
    }
}
