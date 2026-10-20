import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct ThumbnailMakerTests {
    /// Opaque red with a transparent top-left quarter, so alpha handling is visible.
    func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.clear(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    @Test func targetSizeFitsTheLongestSide() {
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 2880, height: 1800), maxSide: 320) == CGSize(width: 320, height: 200))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 400, height: 640), maxSide: 320) == CGSize(width: 200, height: 320))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 1000, height: 999), maxSide: 320) == CGSize(width: 320, height: 320))
    }

    @Test func targetSizeNeverUpscalesOrReachesZero() {
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 100, height: 50), maxSide: 320) == CGSize(width: 100, height: 50))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 320, height: 320), maxSide: 320) == CGSize(width: 320, height: 320))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 5000, height: 1), maxSide: 320) == CGSize(width: 320, height: 1))
    }

    @Test func thumbnailFromImageKeepsAspectAndAlpha() throws {
        let thumbnail = try #require(ThumbnailMaker.thumbnail(from: makeImage(width: 640, height: 400)))
        #expect(thumbnail.width == 320)
        #expect(thumbnail.height == 200)
        #expect(thumbnail.alphaInfo != .none && thumbnail.alphaInfo != .noneSkipLast && thumbnail.alphaInfo != .noneSkipFirst)

        let small = try #require(ThumbnailMaker.thumbnail(from: makeImage(width: 100, height: 50)))
        #expect(small.width == 100)
        #expect(small.height == 50)
    }

    @Test func thumbnailFromPNGDataMatchesImageIOBounds() throws {
        let wide = try ImageEncoder.pngData(from: makeImage(width: 640, height: 400), scale: 2)
        let thumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: wide))
        #expect(thumbnail.width == 320)
        #expect(thumbnail.height == 200)

        let tall = try ImageEncoder.pngData(from: makeImage(width: 400, height: 640), scale: 1)
        let tallThumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: tall))
        #expect(tallThumbnail.width == 200)
        #expect(tallThumbnail.height == 320)

        let small = try ImageEncoder.pngData(from: makeImage(width: 100, height: 50), scale: 1)
        let smallThumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: small))
        #expect(smallThumbnail.width == 100)
        #expect(smallThumbnail.height == 50)

        #expect(ThumbnailMaker.thumbnail(fromPNGData: Data("not a png".utf8)) == nil)
    }

    @Test func thumbnailPNGRoundTrip() throws {
        let source = try ImageEncoder.pngData(from: makeImage(width: 1280, height: 800), scale: 2)
        let thumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: source, maxSide: 160))
        #expect(thumbnail.width == 160)
        #expect(thumbnail.height == 100)

        let png = try ThumbnailMaker.pngData(thumbnail)
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let reread = try #require(ThumbnailMaker.thumbnail(fromPNGData: png, maxSide: 1000))
        #expect(reread.width == 160)
        #expect(reread.height == 100)
    }
}
