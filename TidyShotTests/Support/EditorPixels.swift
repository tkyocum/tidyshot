import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TidyShot

/// Pixel reads for the editor-seam tests (tests-editor.md 2.1). Test support only.
nonisolated enum EditorPixels {
    static func image(width: Int, height: Int, white: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(white ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    static func png(width: Int, height: Int, scale: CGFloat, white: Bool = false) throws -> Data {
        try ImageEncoder.pngData(from: image(width: width, height: height, white: white), scale: scale)
    }

    static func decoded(_ png: Data) throws -> (image: CGImage, scale: CGFloat) {
        try #require(ImageEncoder.decode(png))
    }

    static func dpiWidth(of png: Data) -> Double? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        return props[kCGImagePropertyDPIWidth] as? Double
    }

    static func rgba(_ image: CGImage) -> [UInt8] {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    static func pixel(_ image: CGImage, x: Int, y: Int) -> [Int] {
        let bytes = rgba(image)
        let base = (y * image.width + x) * 4
        return (0..<4).map { Int(bytes[base + $0]) }
    }

    static func pixel(_ png: Data, x: Int, y: Int) throws -> [Int] {
        pixel(try decoded(png).image, x: x, y: y)
    }

    static func changedPixels(_ image: CGImage, in rect: CGRect, from rgb: [Int]) -> Int {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let area = rect.integral.intersection(bounds)
        guard !area.isNull, !area.isEmpty else { return 0 }
        let bytes = rgba(image)
        var count = 0
        for y in Int(area.minY)..<Int(area.maxY) {
            for x in Int(area.minX)..<Int(area.maxX) {
                let base = (y * image.width + x) * 4
                if (0..<3).contains(where: { abs(Int(bytes[base + $0]) - rgb[$0]) > 16 }) { count += 1 }
            }
        }
        return count
    }

    /// The world's red as it reads back: `CoordinatorWorld.image` fills with a Generic RGB red, so an sRGB
    /// read gives [255, 38, 0, 255], not [255, 0, 0, 255].
    @MainActor static func worldRed() throws -> [Int] { pixel(try CoordinatorWorld.image(width: 1, height: 1), x: 0, y: 0) }

    static func isBlue(_ pixel: [Int]) -> Bool { pixel[0] < 40 && pixel[1] < 40 && pixel[2] > 200 }

    static func isBlue(_ image: CGImage) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return isBlue(bytes.map(Int.init))
    }

    static func isBlue(png: Data) throws -> Bool { isBlue(try decoded(png).image) }
}
