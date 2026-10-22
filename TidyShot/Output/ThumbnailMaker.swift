import CoreGraphics
import Foundation
import ImageIO

/// Small previews of captures: longest side `maxSide` pixels (320 by default), aspect ratio kept,
/// never upscaled, alpha kept (window captures have transparent rounded corners, so PNG, not JPEG).
/// An image taller than three times its width is cut to its top first (cropForThumbnail).
nonisolated enum ThumbnailMaker {
    static let maxSide = 320
    /// For the Recent Captures hover preview, built from the local file when there is one.
    static let previewMaxSide = 1200

    /// The size that fits `pixelSize` inside a `maxSide` square without upscaling. Sides are
    /// rounded to whole pixels and never below 1.
    static func targetSize(for pixelSize: CGSize, maxSide: Int) -> CGSize {
        let longest = max(pixelSize.width, pixelSize.height)
        let scale = longest > CGFloat(maxSide) ? CGFloat(maxSide) / longest : 1
        return CGSize(width: max(1, (pixelSize.width * scale).rounded()),
                      height: max(1, (pixelSize.height * scale).rounded()))
    }

    /// The part of an image of `pixelSize` that its thumbnail shows, top-left origin as
    /// `CGImage.cropping(to:)` takes it: all of it, or for an image taller than three times its
    /// width (a scrolling capture) its top `width * 3 / 2` rows, so the thumbnail shows the start of
    /// the page instead of a sliver.
    static func cropForThumbnail(_ pixelSize: CGSize) -> CGRect {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > width * 3 else { return CGRect(origin: .zero, size: pixelSize) }
        return CGRect(x: 0, y: 0, width: width, height: width * 3 / 2)
    }

    /// How much ImageIO may subsample (1, 2, 4 or 8) when it decodes an image of `pixelSize` whose
    /// top `cropForThumbnail(_:)` cuts, so that the cut top is still at least as large as the result
    /// at `maxSide`; 1 for an image it does not cut. A 3094 x 65,536 capture's hover preview then decodes 200 MB, not 811 MB.
    static func subsampleFactor(for pixelSize: CGSize, maxSide: Int) -> Int {
        let crop = cropForThumbnail(pixelSize)
        guard crop.width > 0, crop.height > 0, crop.height < pixelSize.height else { return 1 }
        let target = targetSize(for: crop.size, maxSide: maxSide)
        return [8, 4, 2].first { factor in
            (crop.width / CGFloat(factor)).rounded(.down) >= target.width
                && (crop.height / CGFloat(factor)).rounded(.down) >= target.height
        } ?? 1
    }

    /// Draws `image`, cut by `cropForThumbnail(_:)`, into a smaller bitmap. Used at capture time,
    /// when the CGImage is already in memory.
    static func thumbnail(from image: CGImage, maxSide: Int = maxSide) -> CGImage? {
        let crop = cropForThumbnail(CGSize(width: image.width, height: image.height))
        let image = crop.height < CGFloat(image.height) ? (image.cropping(to: crop) ?? image) : image
        return scaled(image, maxSide: maxSide)
    }

    /// Draws all of `image` into a bitmap whose longest side is at most `maxSide` pixels: aspect
    /// kept, never upscaled, alpha kept (sRGB). Unlike `thumbnail(from:maxSide:)` it never cuts a
    /// tall image to its top. Pin to screen shows captures over 8,192 px from it.
    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage? {
        let size = targetSize(for: CGSize(width: image.width, height: image.height), maxSide: maxSide)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    /// Decodes PNG bytes into a thumbnail through ImageIO. Used for records from before
    /// thumbnails existed and for the larger hover preview; the bytes come from
    /// `SaveLocation.readScoped(_:folder:)`, which holds the save folder's security scope, so there
    /// is no variant that opens a URL itself.
    static func thumbnail(fromPNGData data: Data, maxSide: Int = maxSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxSide: maxSide)
    }

    /// `kCGImageSourceThumbnailMaxPixelSize` bounds the longest side; ImageIO never upscales. An
    /// image that `cropForThumbnail(_:)` would cut (a scrolling capture) is decoded, subsampled by
    /// `subsampleFactor(for:maxSide:)`, cut to its top and drawn by `thumbnail(from:maxSide:)`
    /// instead, so it shows the top of the page here too, not a sliver, before the capture-time
    /// thumbnail is written and in the hover preview. Drawing the top decodes the whole image, at
    /// the subsampled size.
    static func thumbnail(from source: CGImageSource, maxSide: Int) -> CGImage? {
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            let size = CGSize(width: width, height: height)
            if cropForThumbnail(size).height < CGFloat(height) {
                var decode: [CFString: Any] = [kCGImageSourceShouldCache: false]
                let factor = subsampleFactor(for: size, maxSide: maxSide)
                if factor > 1 { decode[kCGImageSourceSubsampleFactor] = factor }
                // The decoded size, not `size`: a format that cannot subsample ignores the factor.
                guard let full = CGImageSourceCreateImageAtIndex(source, 0, decode as CFDictionary),
                      let top = full.cropping(to: cropForThumbnail(CGSize(width: full.width, height: full.height)))
                else { return nil }
                return thumbnail(from: top, maxSide: maxSide)
            }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// PNG bytes for a thumbnail. 72 DPI: thumbnails are displayed, never pasted.
    static func pngData(_ image: CGImage) throws -> Data {
        try ImageEncoder.pngData(from: image, scale: 1)
    }
}
