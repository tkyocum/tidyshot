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

    /// Pin to screen shows a huge capture from `scaled`: a tall image stays whole, where
    /// `thumbnail(from:)` cuts it to its top rows.
    @Test func scaledKeepsATallImageWholeAndNeverUpscales() throws {
        let tall = makeImage(width: 100, height: 700)
        let whole = try #require(ThumbnailMaker.scaled(tall, maxSide: 350))
        #expect(whole.width == 50)
        #expect(whole.height == 350)
        #expect(whole.alphaInfo != .none && whole.alphaInfo != .noneSkipLast && whole.alphaInfo != .noneSkipFirst)
        // The thumbnail of the same image is its top 150 rows (`cropForThumbnail`), not the whole.
        let cut = try #require(ThumbnailMaker.thumbnail(from: tall, maxSide: 350))
        #expect(cut.width == 100)
        #expect(cut.height == 150)
        let small = try #require(ThumbnailMaker.scaled(makeImage(width: 100, height: 50), maxSide: 350))
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

    /// Taller than 3:1 is cut to the top `width * 3 / 2` rows (integer division); 3:1 and
    /// anything flatter are kept whole.
    @Test func cropForThumbnailKeepsTheTopOfTallImages() {
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 2560, height: 16384)) == CGRect(x: 0, y: 0, width: 2560, height: 3840))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 100, height: 301)) == CGRect(x: 0, y: 0, width: 100, height: 150))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 101, height: 1000)) == CGRect(x: 0, y: 0, width: 101, height: 151))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 100, height: 300)) == CGRect(x: 0, y: 0, width: 100, height: 300))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 2880, height: 1800)) == CGRect(x: 0, y: 0, width: 2880, height: 1800))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 0, height: 50)) == CGRect(x: 0, y: 0, width: 0, height: 50))
    }

    /// A 400 x 4000 page, red in its top 600 rows and blue below.
    func makeTallPage() throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 400, height: 4000, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 4000))
        // CGContext's y runs up, so the image's top 600 rows are the context's last 600.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 3400, width: 400, height: 600))
        return try #require(context.makeImage())
    }

    /// 213 x 320 and red, sampled down the middle column, to its last row.
    func expectTheTopOfTheTallPage(_ thumbnail: CGImage) throws {
        #expect(thumbnail.width == 213)
        #expect(thumbnail.height == 320)
        let data = try #require(thumbnail.dataProvider?.data) as Data
        for y in [0, 160, 319] {
            let offset = y * thumbnail.bytesPerRow + 106 * 4
            #expect(data[offset] > 250 && data[offset + 2] < 5, "row \(y) is red")
        }
    }

    /// The thumbnail is the top 400 x 600 scaled to fit 320.
    @Test func thumbnailOfATallImageShowsItsTop() throws {
        try expectTheTopOfTheTallPage(try #require(ThumbnailMaker.thumbnail(from: try makeTallPage())))
    }

    /// The ImageIO path (a record without a stored thumbnail yet, the hover preview) cuts a tall
    /// PNG to its top the same way, rather than scaling the whole page to a sliver.
    @Test func thumbnailOfATallPNGShowsItsTop() throws {
        let png = try ImageEncoder.pngData(from: try makeTallPage(), scale: 1)
        try expectTheTopOfTheTallPage(try #require(ThumbnailMaker.thumbnail(fromPNGData: png)))
        let preview = try #require(ThumbnailMaker.thumbnail(fromPNGData: png, maxSide: 1000))
        #expect(preview.width == 400)
        #expect(preview.height == 600)
    }

    /// A tall PNG is decoded subsampled (ImageIO takes 1, 2, 4 or 8) by as much as keeps the cut
    /// top at least as large as the result, so the hover preview of a 65,536 px capture does not
    /// decode 800 MB to show its top.
    @Test func subsampleFactorKeepsTheTopAtLeastTheTargetSize() {
        #expect(ThumbnailMaker.subsampleFactor(for: CGSize(width: 3094, height: 65_536), maxSide: 1200) == 2)
        #expect(ThumbnailMaker.subsampleFactor(for: CGSize(width: 3094, height: 65_536), maxSide: 320) == 8)
        #expect(ThumbnailMaker.subsampleFactor(for: CGSize(width: 400, height: 4000), maxSide: 320) == 1)
        #expect(ThumbnailMaker.subsampleFactor(for: CGSize(width: 400, height: 4000), maxSide: 100) == 4)
        #expect(ThumbnailMaker.subsampleFactor(for: CGSize(width: 2560, height: 1600), maxSide: 320) == 1)
        #expect(ThumbnailMaker.subsampleFactor(for: CGSize(width: 0, height: 0), maxSide: 320) == 1)
    }

    /// Subsampled by 4, the tall page's top still fills a 67 x 100 thumbnail, red to its last row.
    /// ImageIO's subsampling filters across rows, so the last row, at the page's red to blue edge,
    /// takes a trace of blue.
    @Test func aSubsampledTallPNGStillShowsItsTop() throws {
        let png = try ImageEncoder.pngData(from: try makeTallPage(), scale: 1)
        let thumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: png, maxSide: 100))
        #expect(thumbnail.width == 67)
        #expect(thumbnail.height == 100)
        let data = try #require(thumbnail.dataProvider?.data) as Data
        for (y, tolerance) in [(0, 5), (50, 5), (99, 30)] {
            let offset = y * thumbnail.bytesPerRow + 33 * 4
            #expect(Int(data[offset]) > 255 - tolerance && Int(data[offset + 2]) < tolerance,
                    "row \(y) is red: \(Array(data[offset..<offset + 4]))")
        }
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
