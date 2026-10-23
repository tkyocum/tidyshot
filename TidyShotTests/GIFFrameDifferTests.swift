import Foundation
import Testing
@testable import TidyShot

struct GIFFrameDifferTests {
    static let width = 12
    static let height = 10

    let palette = GIFPalette(colours: [
        GIFColour(r: 0, g: 0, b: 0),
        GIFColour(r: 255, g: 255, b: 255),
        GIFColour(r: 220, g: 30, b: 30),
        GIFColour(r: 30, g: 30, b: 220),
    ])

    /// A frame of `width` × `height` pixels, each `colour(x, y)`, as RGBA bytes.
    func frame(width: Int = width, height: Int = height, _ colour: (Int, Int) -> GIFColour) -> [UInt8] {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let c = colour(x, y)
                bytes += [c.r, c.g, c.b, 255]
            }
        }
        return bytes
    }

    /// Black and white checks, with a red and a blue pixel.
    func background(_ x: Int, _ y: Int) -> GIFColour {
        if x == 3, y == 4 { return GIFColour(r: 220, g: 30, b: 30) }
        if x == 8, y == 1 { return GIFColour(r: 30, g: 30, b: 220) }
        return (x + y) % 2 == 0 ? GIFColour(r: 0, g: 0, b: 0) : GIFColour(r: 255, g: 255, b: 255)
    }

    func next(_ differ: inout GIFFrameDiffer, _ bytes: [UInt8]) -> GIFFrameChange? {
        bytes.withUnsafeBufferPointer { differ.next(rgba: $0) }
    }

    func mapped(_ bytes: [UInt8]) -> [UInt8] {
        stride(from: 0, to: bytes.count, by: 4).map {
            palette.nearest(GIFColour(r: bytes[$0], g: bytes[$0 + 1], b: bytes[$0 + 2]))
        }
    }

    @Test func theFirstCallReturnsTheWholeFrame() throws {
        var differ = GIFFrameDiffer(width: Self.width, height: Self.height, palette: palette)
        #expect(differ.shown == Array(repeating: palette.transparentIndex, count: Self.width * Self.height))
        let bytes = frame(background)
        let change = try #require(next(&differ, bytes))

        #expect(change.rect == GIFRect(x: 0, y: 0, width: Self.width, height: Self.height))
        #expect(change.opaque == mapped(bytes))
        #expect(change.changedOnly == mapped(bytes))
        #expect(differ.shown == mapped(bytes))
    }

    @Test func theSameFrameAgainReturnsNil() {
        var differ = GIFFrameDiffer(width: Self.width, height: Self.height, palette: palette)
        let bytes = frame(background)
        _ = next(&differ, bytes)
        #expect(next(&differ, bytes) == nil)
        #expect(differ.shown == mapped(bytes))
    }

    @Test func onePixelChangedGivesAOneByOneRectangle() throws {
        var differ = GIFFrameDiffer(width: Self.width, height: Self.height, palette: palette)
        _ = next(&differ, frame(background))
        let change = try #require(next(&differ, frame { x, y in
            x == 5 && y == 7 ? GIFColour(r: 220, g: 30, b: 30) : background(x, y)
        }))
        #expect(change.rect == GIFRect(x: 5, y: 7, width: 1, height: 1))
        #expect(change.changedOnly == [2])
        #expect(change.opaque == [2])
    }

    @Test func twoPixelsFarApartGiveTheirBoundingBox() throws {
        var differ = GIFFrameDiffer(width: Self.width, height: Self.height, palette: palette)
        _ = next(&differ, frame(background))
        let before = differ.shown
        let bytes = frame { x, y in
            if x == 1, y == 2 { return GIFColour(r: 30, g: 30, b: 220) }
            if x == 9, y == 8 { return GIFColour(r: 220, g: 30, b: 30) }
            return background(x, y)
        }
        let change = try #require(next(&differ, bytes))

        #expect(change.rect == GIFRect(x: 1, y: 2, width: 9, height: 7))
        let t = palette.transparentIndex
        var expectedChanged = Array(repeating: t, count: 9 * 7)
        expectedChanged[0] = 3
        expectedChanged[9 * 7 - 1] = 2
        #expect(change.changedOnly == expectedChanged)

        var expectedOpaque: [UInt8] = []
        for y in 2..<9 { for x in 1..<10 { expectedOpaque.append(differ.shown[y * Self.width + x]) } }
        #expect(change.opaque == expectedOpaque)
        #expect(change.opaque.first == 3)
        #expect(change.opaque.last == 2)
        #expect(change.opaque[1] == before[2 * Self.width + 2])
    }

    func grey(_ level: UInt8) -> GIFColour { GIFColour(r: level, g: level, b: level) }

    /// A shown entry is kept while the source is within `hysteresis` of being as close to it as to
    /// the nearest entry, so codec noise does not flip pixels between neighbouring entries.
    @Test func hysteresisKeepsANearlyAsCloseShownEntry() throws {
        let greys = GIFPalette(colours: [grey(100), grey(103)])
        var differ = GIFFrameDiffer(width: 4, height: 3, palette: greys)
        _ = frame(width: 4, height: 3) { _, _ in grey(100) }.withUnsafeBufferPointer { differ.next(rgba: $0) }
        #expect(differ.shown == Array(repeating: 0, count: 12))
        let source = frame(width: 4, height: 3) { _, _ in grey(102) }
        #expect(source.withUnsafeBufferPointer { differ.next(rgba: $0) } == nil)
        #expect(differ.shown == Array(repeating: 0, count: 12))

        var strict = GIFFrameDiffer(width: 4, height: 3, palette: greys, hysteresis: 0)
        _ = frame(width: 4, height: 3) { _, _ in grey(100) }.withUnsafeBufferPointer { strict.next(rgba: $0) }
        let change = try #require(source.withUnsafeBufferPointer { strict.next(rgba: $0) })
        #expect(change.rect == GIFRect(x: 0, y: 0, width: 4, height: 3))
        #expect(change.opaque == Array(repeating: 1, count: 12))

        let apart = GIFPalette(colours: [grey(100), grey(110)])
        var far = GIFFrameDiffer(width: 4, height: 3, palette: apart)
        _ = frame(width: 4, height: 3) { _, _ in grey(100) }.withUnsafeBufferPointer { far.next(rgba: $0) }
        let moved = try #require(frame(width: 4, height: 3) { _, _ in grey(110) }.withUnsafeBufferPointer { far.next(rgba: $0) })
        #expect(moved.opaque == Array(repeating: 1, count: 12))
        #expect(far.shown == Array(repeating: 1, count: 12))
    }

    /// After each call `shown` is the previous `shown` with the change applied.
    @Test func shownIsThePreviousShownWithTheChangeApplied() {
        var differ = GIFFrameDiffer(width: Self.width, height: Self.height, palette: palette)
        var random = SyntheticPage.LCG(seed: 5)
        let colours = palette.colours
        var current = (0..<Self.width * Self.height).map { _ in colours[Int(random.next() % 4)] }
        for step in 0..<12 {
            // A few pixels change each step, and every fourth step none do.
            if step % 4 != 3 {
                for _ in 0..<(1 + Int(random.next() % 5)) {
                    current[Int(random.next() % UInt64(current.count))] = colours[Int(random.next() % 4)]
                }
            }
            let bytes = current.flatMap { [$0.r, $0.g, $0.b, UInt8(255)] }
            let before = differ.shown
            let change = next(&differ, bytes)
            var expected = before
            if let change {
                let t = palette.transparentIndex
                for y in 0..<change.rect.height {
                    for x in 0..<change.rect.width {
                        let index = (change.rect.y + y) * Self.width + change.rect.x + x
                        let changed = change.changedOnly[y * change.rect.width + x]
                        if changed != t { expected[index] = changed }
                        #expect(change.opaque[y * change.rect.width + x] == differ.shown[index])
                    }
                }
            }
            #expect(differ.shown == expected)
            #expect(differ.shown == mapped(bytes))
        }
    }
}
