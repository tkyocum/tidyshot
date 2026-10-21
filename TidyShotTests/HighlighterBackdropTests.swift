import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The highlighter's backdrop copies the capture's strips under the stroke so the multiply has
/// real pixels. At a fractional zoom a strip join falls inside a device row; the backdrop must
/// still be fully opaque there.
struct HighlighterBackdropTests {
    private let space = CGColorSpace(name: CGColorSpace.sRGB)!

    private func solid(width: Int, height: Int, red: UInt8) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: CGFloat(red) / 255, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// Renders two stacked 16 x 16 px strips at `zoom` into a transparent bitmap, y-down like the
    /// canvas, clipped to the whole of both, and returns the bitmap's alpha per row at column 5.
    private func alphaDown(zoom: CGFloat, strips: [(rect: CGRect, image: CGImage)], clip: CGRect, rows: Int) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: 30, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(rows))
        context.scaleBy(x: 1, y: -1)
        context.scaleBy(x: zoom, y: zoom)
        context.addRect(clip)
        context.clip()
        context.interpolationQuality = .low
        HighlighterBackdrop.draw(strips, in: context)
        let data = try #require(context.data)
        let bytesPerRow = context.bytesPerRow
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        return (0..<rows).map { pixels[$0 * bytesPerRow + 5 * 4 + 3] }
    }

    @Test func aJoinAtAFractionalZoomLeavesNoTransparentRow() throws {
        let top = (rect: CGRect(x: 0, y: 0, width: 16, height: 16), image: try solid(width: 16, height: 16, red: 200))
        let bottom = (rect: CGRect(x: 0, y: 16, width: 16, height: 16), image: try solid(width: 16, height: 16, red: 50))
        // 1.3 puts the join at device row 20.8; the bitmap covers 32 * 1.3 = 41.6 rows, so 41 are whole.
        let alpha = try alphaDown(zoom: 1.3, strips: [top, bottom], clip: CGRect(x: 0, y: 0, width: 16, height: 32), rows: 41)
        #expect(alpha.allSatisfy { $0 == 255 }, "alpha by row: \(alpha)")
    }

    @Test func onlyTheClipsNeighbourhoodIsDrawn() throws {
        // A stroke covering rows 10 ... 14 of a 64 px strip: the rest of the strip is not drawn.
        let strip = (rect: CGRect(x: 0, y: 0, width: 16, height: 64), image: try solid(width: 16, height: 64, red: 200))
        let alpha = try alphaDown(zoom: 1, strips: [strip], clip: CGRect(x: 0, y: 10, width: 16, height: 4), rows: 64)
        #expect(alpha[10..<14].allSatisfy { $0 == 255 })
        #expect(alpha[0..<10].allSatisfy { $0 == 0 })
        #expect(alpha[14..<64].allSatisfy { $0 == 0 })
    }
}
