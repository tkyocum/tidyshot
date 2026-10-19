import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageEncoder {
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
}
