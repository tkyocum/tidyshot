import AppKit
import CoreGraphics
import Testing
@testable import TidyShot

/// The editor shows a capture as layers no side of which exceeds `ImageTiling.maxTileSide`
/// (16,384 px, every Mac GPU's texture limit; the M5 Max accepts 32,768).
struct ImageTilingTests {
    /// The tiles cover the image exactly: inside it, no two overlapping, areas adding up to the
    /// image's, every side within `maxSide`, rows top to bottom and left to right within a row.
    func expectExactCover(_ tiles: [CGRect], width: Int, height: Int, maxSide: Int) {
        let image = CGRect(x: 0, y: 0, width: width, height: height)
        var area: CGFloat = 0
        for (index, tile) in tiles.enumerated() {
            #expect(tile == tile.integral)
            #expect(image.contains(tile))
            #expect(tile.width <= CGFloat(maxSide) && tile.height <= CGFloat(maxSide))
            #expect(tile.width > 0 && tile.height > 0)
            area += tile.width * tile.height
            for other in tiles[(index + 1)...] {
                #expect(tile.intersection(other).isEmpty, "\(tile) overlaps \(other)")
            }
        }
        #expect(area == CGFloat(width * height))
        #expect(tiles.reduce(CGRect.null) { $0.union($1) } == (tiles.isEmpty ? .null : image))
        let order: [CGPoint] = tiles.map { CGPoint(x: $0.minX, y: $0.minY) }
        let sorted = order.sorted { (a: CGPoint, b: CGPoint) -> Bool in a.y != b.y ? a.y < b.y : a.x < b.x }
        #expect(order == sorted)
    }

    @Test func anImageWithinTheLimitIsOneTile() {
        #expect(ImageTiling.maxTileSide == 16_384)
        #expect(ImageTiling.tiles(width: 2560, height: 1600) == [CGRect(x: 0, y: 0, width: 2560, height: 1600)])
        #expect(ImageTiling.tiles(width: 16_384, height: 16_384) == [CGRect(x: 0, y: 0, width: 16_384, height: 16_384)])
    }

    @Test func aCaptureAtTheScrollingCapIsFourStrips() {
        let tiles = ImageTiling.tiles(width: 3094, height: ScrollCaptureLimits.maxPixelHeight)
        #expect(tiles == (0..<4).map { CGRect(x: 0, y: $0 * 16_384, width: 3094, height: 16_384) })
        expectExactCover(tiles, width: 3094, height: ScrollCaptureLimits.maxPixelHeight, maxSide: 16_384)
    }

    @Test func aRemainderMakesAShorterLastStrip() {
        let tiles = ImageTiling.tiles(width: 1200, height: 40_000)
        #expect(tiles == [CGRect(x: 0, y: 0, width: 1200, height: 16_384),
                          CGRect(x: 0, y: 16_384, width: 1200, height: 16_384),
                          CGRect(x: 0, y: 32_768, width: 1200, height: 7232)])
        #expect(ImageTiling.tiles(width: 10, height: 16_385).map(\.height) == [16_384, 1])
    }

    @Test func aWideImageIsSplitIntoColumnsToo() {
        let tiles = ImageTiling.tiles(width: 20_000, height: 17_000)
        #expect(tiles.count == 4)
        #expect(tiles[1] == CGRect(x: 16_384, y: 0, width: 3616, height: 16_384))
        #expect(tiles[3] == CGRect(x: 16_384, y: 16_384, width: 3616, height: 616))
        expectExactCover(tiles, width: 20_000, height: 17_000, maxSide: 16_384)
    }

    @Test func otherLimitsAndOddSizesCoverExactly() {
        for (width, height, maxSide) in [(1, 1, 1), (7, 5, 2), (100, 1000, 64), (999, 13, 1000), (3, 50_000, 16_384)] {
            expectExactCover(ImageTiling.tiles(width: width, height: height, maxSide: maxSide),
                             width: width, height: height, maxSide: maxSide)
        }
    }

    @Test func anEmptyImageHasNoTiles() {
        #expect(ImageTiling.tiles(width: 0, height: 100).isEmpty)
        #expect(ImageTiling.tiles(width: 100, height: 0).isEmpty)
        #expect(ImageTiling.tiles(width: 100, height: 100, maxSide: 0).isEmpty)
    }

    /// The cropped images share the base's pixels row for row, and a small image is not cropped.
    @Test func cropsCutTheImageAtTheTiles() throws {
        let image = try makeImage(width: 3, height: 10)
        let small = ImageTiling.crops(of: image, maxSide: 16)
        #expect(small.count == 1)
        #expect(small.first?.image === image)
        let crops = ImageTiling.crops(of: image, maxSide: 4)
        #expect(crops.map(\.rect) == ImageTiling.tiles(width: 3, height: 10, maxSide: 4))
        #expect(crops.map(\.image.height) == [4, 4, 2])
        // Row y of the image has green y: each crop starts at its tile's first row.
        for crop in crops {
            let data = try #require(crop.image.dataProvider?.data) as Data
            #expect(data[1] == UInt8(crop.rect.minY))
        }
    }

    /// The base view shows a tall capture as stacked layers, one per tile, framed through the
    /// transform like the effect tiles, so zoom, pan and Fit move them together.
    @Test func baseImageViewStacksOneLayerPerTile() throws {
        let view = BaseImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.image = try makeImage(width: 8, height: 40_000)
        let transform = CanvasTransform(zoom: 0.01, offset: CGPoint(x: 5, y: 7))
        view.transform = transform
        let rects = ImageTiling.tiles(width: 8, height: 40_000)
        #expect(view.baseTiles.map(\.rect) == rects)
        let layers = view.contentLayers
        #expect(layers.count == 3)
        for (layer, rect) in zip(layers, rects) {
            let expected = transform.viewRect(rect)
            #expect(abs(layer.frame.minY - expected.minY) < 1e-6 && abs(layer.frame.height - expected.height) < 1e-6,
                    "\(layer.frame) is not \(expected)")
            #expect(layer.frame.minX == expected.minX && layer.frame.width == expected.width)
            let contents = try #require(layer.contents.map { $0 as! CGImage })
            #expect(contents.height == Int(rect.height))
            #expect(contents.width == 8)
        }
        view.image = try makeImage(width: 8, height: 100)
        #expect(view.contentLayers.count == 1)
        view.image = nil
        #expect(view.baseTiles.isEmpty)
    }

    /// An 8-bit RGBA image whose green channel is the row number modulo 256.
    func makeImage(width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width { bytes[(y * width + x) * 4 + 1] = UInt8(y % 256) }
        }
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                                    shouldInterpolate: false, intent: .defaultIntent))
    }
}
