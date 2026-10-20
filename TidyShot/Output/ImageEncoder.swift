import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageEncoder {
    enum EncodeError: LocalizedError {
        case destinationUnavailable
        case finalizeFailed

        var errorDescription: String? {
            switch self {
            case .destinationUnavailable: "Could not create a PNG encoder."
            case .finalizeFailed: "PNG encoding failed."
            }
        }
    }

    /// Encodes `image` as PNG with DPI metadata of `72 * scale`, so a 2x capture reports 144 DPI
    /// and displays at its point size when pasted.
    static func pngData(from image: CGImage, scale: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw EncodeError.destinationUnavailable
        }
        let dpi = 72.0 * Double(scale)
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError.finalizeFailed
        }
        return data as Data
    }

    /// Decodes PNG bytes (a capture's file, or its object downloaded for Copy Image) and reads the
    /// scale back from the DPI that `pngData(from:scale:)` writes: 144 DPI gives 2, and no DPI
    /// gives 1. PNG stores pixels per metre, so the DPI comes back a fraction off and is rounded.
    /// Nil when the bytes are not an image.
    static func decode(_ data: Data) -> (image: CGImage, scale: CGFloat)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double ?? 72
        return (image, max(1, (dpi / 72).rounded()))
    }
}
