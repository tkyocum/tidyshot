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
        let parsed = try GIFBlocks.parse(file)
        let frame = try #require(parsed.frames.first)
        #expect(try GIFBlocks.codeStream(of: frame).indices == indices)
        return parsed
    }

    /// Encodes `indices` and reads the block back with `GIFBlocks.codeStream`, which throws unless
    /// end-of-information is read and ends in the last byte.
    func codeStream(_ indices: [UInt8], palette: GIFPalette) throws -> GIFBlocks.CodeStream {
        var writer = GIFLZWWriter()
        let block = encode(indices, palette: palette, writer: &writer)
        let file = try GIFBlocks.parse(GIFBlocks.oneFrame(palette: palette, width: indices.count, height: 1,
                                                          imageData: block))
        let stream = try GIFBlocks.codeStream(of: try #require(file.frames.first))
        #expect(stream.indices == indices)
        return stream
    }

    /// Indices whose consecutive pairs never repeat, so each one is a code of its own: 0, d, 2d, ...
    /// (mod 255) for each step d coprime to 255, 32,640 in all.
    static func distinctPairs(count: Int) -> [UInt8] {
        let steps = (1..<255).filter { $0 % 3 != 0 && $0 % 5 != 0 && $0 % 17 != 0 }
        let indices = steps.flatMap { step in (0..<255).map { UInt8($0 * step % 255) } }
        precondition(count <= indices.count)
        return Array(indices.prefix(count))
    }

    /// When the last code leaves the next free code at `2^width`, a decoder adds its entry and
    /// reads end-of-information one bit wider. At minimum code size 8 that is a last segment of 255,
    /// 767 or 1,791 codes; after 0 to 7 full segments it ends at every bit offset, the byte-aligned
    /// one included, where a narrow end-of-information leaves a decoder short of data.
    @Test func endOfInformationIsReadAtTheEndOfTheDataAtEachWidth() throws {
        let fullSegment = 4096 - 258
        for lastCodes in [255, 767, 1_791] {
            var paddings: Set<Int> = []
            for fullSegments in 0..<8 {
                let stream = try codeStream(Self.distinctPairs(count: fullSegments * fullSegment + lastCodes),
                                            palette: fullPalette)
                #expect(stream.clearCount == fullSegments + 1)
                #expect(stream.codesInLastSegment == lastCodes)
                #expect(stream.endWidth == stream.lastCodeWidth + 1)
                paddings.insert(stream.paddingBits)
            }
            #expect(paddings == Set(0..<8))
        }
    }

    /// The same at minimum code size 2, for every length of a seeded three-colour image up to 400,
    /// whose last codes fill each width from 3 to 6 bits. At 11 codes a 4-bit end-of-information
    /// would end byte-aligned.
    @Test func endOfInformationIsReadAtTheEndOfTheDataAtMinimumCodeSizeTwo() throws {
        let palette = GIFPalette(colours: [
            GIFColour(r: 255, g: 0, b: 0), GIFColour(r: 0, g: 255, b: 0), GIFColour(r: 0, g: 0, b: 255),
        ])
        var random = SyntheticPage.LCG(seed: 5)
        let image = (0..<400).map { _ in UInt8(random.next() % 3) }
        var widenedAt: Set<Int> = []
        for count in 1...image.count {
            let stream = try codeStream(Array(image.prefix(count)), palette: palette)
            if stream.endWidth > stream.lastCodeWidth { widenedAt.insert(stream.codesInLastSegment) }
        }
        #expect(widenedAt.isSuperset(of: [3, 11, 27, 59]))
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
