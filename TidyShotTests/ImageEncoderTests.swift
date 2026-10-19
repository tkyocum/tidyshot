import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import TidyShot

struct ImageEncoderTests {
    func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    func properties(of data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    }

    @Test func encodesPNGSignature() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 4, height: 4), scale: 1)
        #expect(Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    /// PNG stores pixels per metre as an integer, so read-back can be off by a fraction of a DPI.
    func dpi(_ props: [CFString: Any], _ key: CFString) -> Double {
        props[key] as? Double ?? 0
    }

    @Test func retinaScaleWrites144DPI() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 200, height: 100), scale: 2)
        let props = properties(of: data)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 100)
        #expect(abs(dpi(props, kCGImagePropertyDPIWidth) - 144) < 0.5)
        #expect(abs(dpi(props, kCGImagePropertyDPIHeight) - 144) < 0.5)
    }

    @Test func standardScaleWrites72DPI() throws {
        let data = try ImageEncoder.pngData(from: makeImage(width: 10, height: 10), scale: 1)
        let props = properties(of: data)
        #expect(abs(dpi(props, kCGImagePropertyDPIWidth) - 72) < 0.5)
    }
}
