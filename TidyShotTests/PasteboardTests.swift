import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The clipboard's TIFF is uncompressed, so above 16,384 px on a side (a long scrolling capture)
/// only the PNG goes on the clipboard: at 3094 x 65,536 the TIFF would add about 580 MB, and
/// making it peaks over a gigabyte more.
struct PasteboardTests {
    @Test func theTIFFGoesAlongUpTo16384PixelsOnEachSide() {
        #expect(Pasteboard.tiffMaxSide == 16_384)
        #expect(Pasteboard.includesTIFF(pixelWidth: 2560, pixelHeight: 1600))
        #expect(Pasteboard.includesTIFF(pixelWidth: 3094, pixelHeight: 16_384))
        #expect(Pasteboard.includesTIFF(pixelWidth: 16_384, pixelHeight: 100))
        #expect(!Pasteboard.includesTIFF(pixelWidth: 3094, pixelHeight: 16_385))
        #expect(!Pasteboard.includesTIFF(pixelWidth: 3094, pixelHeight: ScrollCaptureLimits.maxPixelHeight))
        #expect(!Pasteboard.includesTIFF(pixelWidth: 16_385, pixelHeight: 100))
    }

    @Test func companionTIFFIsNilForATallImage() throws {
        #expect(Pasteboard.companionTIFF(of: try makeImage(width: 2, height: 16_384), scale: 2) != nil)
        #expect(Pasteboard.companionTIFF(of: try makeImage(width: 2, height: 16_385), scale: 2) == nil)
        // The PNG-failed fallback has nothing else to put on the clipboard, so it still makes one.
        #expect(Pasteboard.tiffData(of: try makeImage(width: 2, height: 16_385), scale: 2) != nil)
    }

    func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }
}
