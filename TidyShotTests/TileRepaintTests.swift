import CoreGraphics
import Testing
@testable import TidyShot

struct TileRepaintTests {
    func image() -> CGImage {
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    let rect = CGRect(x: 10, y: 20, width: 30, height: 40)

    @Test func sameImageAtTheSameRectNeedsNoRepaint() {
        let image = image()
        let tile = TileRepaint.Shown(image: image, rect: rect)
        #expect(TileRepaint.dirtyRect(old: tile, new: tile) == nil)
        #expect(TileRepaint.dirtyRect(old: nil, new: nil) == nil)
    }

    @Test func aReplacedImageRepaintsItsRect() {
        let old = TileRepaint.Shown(image: image(), rect: rect)
        let new = TileRepaint.Shown(image: image(), rect: rect)
        #expect(TileRepaint.dirtyRect(old: old, new: new) == rect)
    }

    @Test func aMovedTileRepaintsBothRects() {
        let image = image()
        let moved = CGRect(x: 100, y: 5, width: 30, height: 40)
        let dirty = TileRepaint.dirtyRect(old: .init(image: image, rect: rect), new: .init(image: image, rect: moved))
        #expect(dirty == rect.union(moved))
    }

    @Test func aTileAppearingOrGoingRepaintsItsRect() {
        let tile = TileRepaint.Shown(image: image(), rect: rect)
        #expect(TileRepaint.dirtyRect(old: nil, new: tile) == rect)
        #expect(TileRepaint.dirtyRect(old: tile, new: nil) == rect)
    }

    @Test func anEmptyRectAddsNothing() {
        let empty = TileRepaint.Shown(image: image(), rect: .zero)
        let tile = TileRepaint.Shown(image: image(), rect: rect)
        #expect(TileRepaint.dirtyRect(old: empty, new: tile) == rect)
        #expect(TileRepaint.dirtyRect(old: empty, new: nil) == nil)
    }
}
