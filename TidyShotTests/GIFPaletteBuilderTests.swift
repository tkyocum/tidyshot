import Foundation
import Testing
@testable import TidyShot

struct GIFPaletteBuilderTests {
    /// RGBA bytes for `colours`, each repeated `times` pixels; the fourth byte is ignored.
    func rgba(_ colours: [GIFColour], times: Int = 1) -> [UInt8] {
        colours.flatMap { colour in
            Array(repeating: [colour.r, colour.g, colour.b, 255], count: times).flatMap { $0 }
        }
    }

    func build(_ bytes: [UInt8], into builder: inout GIFPaletteBuilder) {
        bytes.withUnsafeBufferPointer { builder.add(rgba: $0) }
    }

    func distance(_ a: GIFColour, _ b: GIFColour) -> Int {
        max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)))
    }

    /// The first 200 colours of the 6×6×6 grid (levels 0, 51, …, 255).
    var gridColours: [GIFColour] {
        let levels: [UInt8] = [0, 51, 102, 153, 204, 255]
        var colours: [GIFColour] = []
        for r in levels { for g in levels { for b in levels { colours.append(GIFColour(r: r, g: g, b: b)) } } }
        return Array(colours.prefix(200))
    }

    @Test func gridColoursComeBackExactlyWithOneEntryEach() {
        let colours = gridColours
        var builder = GIFPaletteBuilder()
        build(rgba(colours, times: 3), into: &builder)
        let palette = builder.build()

        #expect(palette.colours.count == 200)
        #expect(Set(palette.colours) == Set(colours))
        for colour in colours {
            #expect(palette.colours[Int(palette.nearest(colour))] == colour)
        }
    }

    /// H.264 leaves ±1 level of noise on flat backgrounds; the spread floor spends no entries on it.
    @Test func codecNoiseGetsNoEntries() {
        var random = SyntheticPage.LCG(seed: 11)
        var noisy: [GIFColour] = []
        for _ in 0..<(64 * 64) {
            func level() -> UInt8 { UInt8(240 + Int(random.next() % 3) - 1) }
            noisy.append(GIFColour(r: level(), g: level(), b: level()))
        }
        // 20 distinct colours, far from the grey and from each other.
        let distinct = gridColours.filter { $0.r <= 153 }.prefix(20)
        #expect(distinct.count == 20)
        var builder = GIFPaletteBuilder()
        build(rgba(noisy) + rgba(Array(distinct), times: 64), into: &builder)
        let palette = builder.build()

        let grey = GIFColour(r: 240, g: 240, b: 240)
        #expect(palette.colours.filter { distance($0, grey) <= 3 }.count == 1)
        #expect(palette.colours.count == 21)
        for colour in distinct {
            #expect(palette.colours[Int(palette.nearest(colour))] == colour)
        }
    }

    @Test func manyColoursFillAll255Entries() {
        var colours: [GIFColour] = []
        for y in 0..<64 {
            for x in 0..<64 {
                colours.append(GIFColour(r: UInt8(x * 4), g: UInt8(y * 4), b: UInt8((x + y) * 2)))
            }
        }
        #expect(Set(colours).count == 4_096)
        var builder = GIFPaletteBuilder()
        build(rgba(colours), into: &builder)
        let palette = builder.build()

        #expect(palette.colours.count == 255)
        #expect(Set(palette.colours).count == 255)
    }

    // MARK: Reserved colours (R3)

    let yellow = GIFColour(r: 255, g: 204, b: 0)
    let blue = GIFColour(r: 10, g: 133, b: 255)
    let black = GIFColour(r: 0, g: 0, b: 0)

    /// A 16 × 16 gradient of 256 colours, red and green in steps of 17 over a mid blue, each in a
    /// bin of its own and none a reserved colour.
    var gradientColours: [GIFColour] {
        (0..<256).map { GIFColour(r: UInt8($0 % 16 * 17), g: UInt8($0 / 16 * 17), b: 128) }
    }

    @Test func reservedColoursComeFirstExactlyAndTheSplitFillsTheRest() {
        var builder = GIFPaletteBuilder()
        build(rgba(gradientColours), into: &builder)
        let palette = builder.build(reserving: ClickRingColour.reservedGIFColours)

        #expect(Array(palette.colours.prefix(3)) == [yellow, blue, black])
        #expect(palette.colours.count == 255)
        #expect(Set(palette.colours).count == 255)
        // No sampled pixel was yellow or blue, and each still maps to its own entry.
        #expect(palette.nearest(yellow) == 0)
        #expect(palette.nearest(blue) == 1)
    }

    @Test func aReservedColourInTheFrameGetsNoSecondEntry() {
        var builder = GIFPaletteBuilder()
        build(rgba([yellow], times: 64), into: &builder)
        let palette = builder.build(reserving: ClickRingColour.reservedGIFColours)
        #expect(palette == GIFPalette(colours: [yellow, blue, black]))
    }

    @Test func reservedColoursAloneWhenThereAreNoPixels() {
        let palette = GIFPaletteBuilder().build(reserving: ClickRingColour.reservedGIFColours)
        #expect(palette == GIFPalette(colours: [yellow, blue, black]))
    }

    @Test func noReservedColoursIsR2sPalette() {
        var builder = GIFPaletteBuilder()
        build(rgba(gradientColours) + rgba(gridColours, times: 2), into: &builder)
        #expect(builder.build(reserving: []) == builder.build())
    }

    @Test func noPixelsGiveOneBlackEntry() {
        let palette = GIFPaletteBuilder().build()
        #expect(palette == GIFPalette(colours: [GIFColour(r: 0, g: 0, b: 0)]))
        #expect(palette.transparentIndex == 1)
    }

    @Test func transparentIndexIsTheColourCountAndTheTableIsTheNextPowerOfTwo() {
        func palette(_ count: Int) -> GIFPalette {
            GIFPalette(colours: (0..<count).map { GIFColour(r: UInt8($0), g: 0, b: 0) })
        }
        #expect(palette(1).tableBits == 1)
        #expect(palette(3).tableBits == 2)
        #expect(palette(4).tableBits == 3)
        #expect(palette(255).tableBits == 8)
        for count in [1, 3, 4, 255] {
            #expect(palette(count).transparentIndex == UInt8(count))
        }

        // The table holds 2^tableBits entries, padded with black.
        let three = palette(3)
        #expect(three.tableBytes == [0, 0, 0, 1, 0, 0, 2, 0, 0, 0, 0, 0])
        #expect(palette(255).tableBytes.count == 256 * 3)
        #expect(palette(255).tableBytes.suffix(3) == [0, 0, 0])
    }

    /// The nearest entry has the least squared RGB distance, the lowest index on a tie.
    @Test func nearestPicksTheClosestEntryAndTheLowestIndexOnATie() {
        let palette = GIFPalette(colours: [
            GIFColour(r: 10, g: 10, b: 10),
            GIFColour(r: 30, g: 10, b: 10),
            GIFColour(r: 200, g: 0, b: 0),
        ])
        #expect(palette.nearest(GIFColour(r: 12, g: 10, b: 10)) == 0)
        #expect(palette.nearest(GIFColour(r: 20, g: 10, b: 10)) == 0)
        #expect(palette.nearest(GIFColour(r: 21, g: 10, b: 10)) == 1)
        #expect(palette.nearest(GIFColour(r: 255, g: 0, b: 0)) == 2)
    }
}
