import Foundation
import Testing
@testable import TidyShot

/// Each image is wrapped into a one-frame GIF by `GIFBlocks.oneFrame`, not `GIFEncoder`, and
/// decoded with ImageIO.
struct GIFLZWWriterTests {
    /// 255 distinct colours, for minimum code size 8.
    let fullPalette = GIFPalette(colours: (0..<255).map {
        GIFColour(r: UInt8($0), g: UInt8(255 - $0), b: UInt8($0 * 7 & 0xFF))
    })

    func encode(_ indices: [UInt8], palette: GIFPalette, writer: inout GIFLZWWriter) -> [UInt8] {
        var output: [UInt8] = []
        indices.withUnsafeBufferPointer {
            writer.encode($0, minimumCodeSize: max(2, palette.tableBits), into: &output)
        }
        return output
    }

    /// Encodes, wraps, decodes, and checks every pixel against its palette colour.
    @discardableResult
    func roundTrip(_ indices: [UInt8], width: Int, height: Int, palette: GIFPalette) throws -> GIFBlocks.GIFFile {
        var writer = GIFLZWWriter()
        let block = encode(indices, palette: palette, writer: &writer)
        let file = GIFBlocks.oneFrame(palette: palette, width: width, height: height, imageData: block)
        let frames = GIFBlocks.decodedFrames(Data(file))
        #expect(frames.count == 1)
        let decoded = try #require(frames.first)
        let expected = GIFBlocks.colours(indices, in: palette)
        #expect(decoded.count == expected.count)
        #expect(zip(decoded, expected).filter { $0 != $1 }.count == 0)
        return try GIFBlocks.parse(file)
    }

    @Test func oneColourThroughout() throws {
        try roundTrip(Array(repeating: 17, count: 300 * 200), width: 300, height: 200, palette: fullPalette)
    }

    /// Random indices use every code width up to 12 bits and fill the table many times over.
    @Test func aSeededRandomImage() throws {
        var random = SyntheticPage.LCG(seed: 2026)
        let indices = (0..<(512 * 512)).map { _ in UInt8(random.next() % 255) }
        let file = try roundTrip(indices, width: 512, height: 512, palette: fullPalette)
        let frame = try #require(file.frames.first)
        #expect(frame.minimumCodeSize == 8)
        #expect(frame.subBlockLengths.count > 1_000)
    }

    @Test func aOneByOneImage() throws {
        try roundTrip([200], width: 1, height: 1, palette: fullPalette)
    }

    @Test func aThreeColourPaletteAtMinimumCodeSizeTwo() throws {
        let palette = GIFPalette(colours: [
            GIFColour(r: 255, g: 0, b: 0), GIFColour(r: 0, g: 255, b: 0), GIFColour(r: 0, g: 0, b: 255),
        ])
        #expect(max(2, palette.tableBits) == 2)
        var random = SyntheticPage.LCG(seed: 3)
        let indices = (0..<(37 * 23)).map { _ in UInt8(random.next() % 3) }
        let file = try roundTrip(indices, width: 37, height: 23, palette: palette)
        #expect(file.frames.first?.minimumCodeSize == 2)
    }

    @Test func subBlocksAreAtMost255BytesAndEndWithAnEmptyOne() throws {
        var random = SyntheticPage.LCG(seed: 8)
        let indices = (0..<(200 * 150)).map { _ in UInt8(random.next() % 255) }
        for (pixels, width, height) in [(indices, 200, 150), ([UInt8(4)], 1, 1)] {
            var writer = GIFLZWWriter()
            let block = encode(pixels, palette: fullPalette, writer: &writer)
            let file = try GIFBlocks.parse(GIFBlocks.oneFrame(palette: fullPalette, width: width, height: height,
                                                              imageData: block))
            let lengths = try #require(file.frames.first?.subBlockLengths)
            #expect(lengths.last == 0)
            #expect(lengths.dropLast().allSatisfy { (1...255).contains($0) })
            #expect(file.endsWithTrailer)
        }
    }

    /// The writer keeps its table between frames; each encode starts afresh all the same.
    @Test func aReusedWriterWritesWhatAFreshOneWrites() {
        var random = SyntheticPage.LCG(seed: 21)
        let first = (0..<(64 * 64)).map { _ in UInt8(random.next() % 255) }
        let second = (0..<(40 * 30)).map { _ in UInt8(random.next() % 6) }
        var reused = GIFLZWWriter()
        _ = encode(first, palette: fullPalette, writer: &reused)
        let again = encode(second, palette: fullPalette, writer: &reused)
        var fresh = GIFLZWWriter()
        #expect(again == encode(second, palette: fullPalette, writer: &fresh))
    }

    /// The writer appends to what is already in the output.
    @Test func encodeAppendsToTheOutput() {
        var writer = GIFLZWWriter()
        var output: [UInt8] = [1, 2, 3]
        [UInt8(0), 0, 0].withUnsafeBufferPointer { writer.encode($0, minimumCodeSize: 2, into: &output) }
        #expect(output.prefix(4) == [1, 2, 3, 2])
        #expect(output.last == 0)
    }
}
