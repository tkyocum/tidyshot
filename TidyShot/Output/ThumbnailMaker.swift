import CoreGraphics
import Foundation
import ImageIO

/// Small previews of captures: longest side `maxSide` pixels (320 by default), aspect ratio kept,
/// never upscaled, alpha kept (window captures have transparent rounded corners, so PNG, not JPEG).
nonisolated enum ThumbnailMaker {
    static let maxSide = 320
    /// For the gallery's hover preview, built from the local file when there is one.
    static let previewMaxSide = 1200

    /// The size that fits `pixelSize` inside a `maxSide` square without upscaling. Sides are
    /// rounded to whole pixels and never below 1.
    static func targetSize(for pixelSize: CGSize, maxSide: Int) -> CGSize {
        let longest = max(pixelSize.width, pixelSize.height)
        let scale = longest > CGFloat(maxSide) ? CGFloat(maxSide) / longest : 1
        return CGSize(width: max(1, (pixelSize.width * scale).rounded()),
                      height: max(1, (pixelSize.height * scale).rounded()))
    }

    /// Draws `image` into a smaller bitmap. Used at capture time, when the CGImage is already in memory.
    static func thumbnail(from image: CGImage, maxSide: Int = maxSide) -> CGImage? {
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
    /// thumbnails existed and for the gallery's larger preview; the bytes come from
    /// `AppCoordinator.readLocalFile(of:)`, which holds the save folder's security scope, so there
    /// is no variant that opens a URL itself.
    static func thumbnail(fromPNGData data: Data, maxSide: Int = maxSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxSide: maxSide)
    }

    /// `kCGImageSourceThumbnailMaxPixelSize` bounds the longest side; ImageIO never upscales.
    static func thumbnail(from source: CGImageSource, maxSide: Int) -> CGImage? {
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
