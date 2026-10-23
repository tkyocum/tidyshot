import Foundation
import Testing
@testable import TidyShot

struct GIFEncoderTests {
    static let width = 64
    static let height = 48

    static let white = GIFColour(r: 255, g: 255, b: 255)
    static let black = GIFColour(r: 0, g: 0, b: 0)
    static let palette = GIFPalette(colours: [
        white, black,
        GIFColour(r: 220, g: 40, b: 40), GIFColour(r: 40, g: 200, b: 40),
        GIFColour(r: 40, g: 40, b: 220), GIFColour(r: 230, g: 220, b: 30),
    ])

    typealias Frame = [GIFColour]

    static func rgba(_ frame: Frame) -> [UInt8] {
        frame.flatMap { [$0.r, $0.g, $0.b, 255] }
    }

    /// A black 16×16 square moving diagonally over a still background of coloured noise, back to
    /// its start every fourth frame. The changed rectangle holds unchanged noise in its corners.
    static func movingSquare(frames: Int) -> [Frame] {
        var random = SyntheticPage.LCG(seed: 77)
        let background = (0..<width * height).map { _ in palette.colours[2 + Int(random.next() % 4)] }
        return (0..<frames).map { step in
            let left = 2 + step % 4 * 12, top = 1 + step % 4 * 9
            return (0..<width * height).map { index in
                let x = index % width, y = index / width
                return (left..<left + 16).contains(x) && (top..<top + 16).contains(y) ? black : background[index]
            }
        }
    }

    /// Rows of random black stripes on white, moving up a row each frame, like scrolling text.
    static func scrollingStripes(frames: Int) -> [Frame] {
        var random = SyntheticPage.LCG(seed: 4)
        let rows = (0..<height + frames).map { _ in
            (0..<width).map { _ in random.next() % 5 == 0 ? black : white }
        }
        return (0..<frames).map { step in
            (0..<height).flatMap { rows[$0 + step] }
        }
    }

    /// A frame of one colour.
    static func solid(_ colour: GIFColour) -> Frame {
        Array(repeating: colour, count: width * height)
    }

    /// Encodes `frames` at their output indices into memory.
    static func encode(_ frames: [(index: Int, frame: Frame)], frameCount: Int, fps: Int = 15,
                       palette: GIFPalette = palette) throws -> (summary: GIFEncoderSummary, bytes: [UInt8]) {
        var encoder = try GIFEncoder(sink: GIFDataSink(), width: width, height: height, fps: fps, palette: palette)
        for (index, frame) in frames {
            try rgba(frame).withUnsafeBufferPointer { try encoder.add(rgba: $0, at: index) }
        }
        let summary = try encoder.finish(frameCount: frameCount)
        return (summary, encoder.sink.bytes)
    }

    static func consecutive(_ frames: [Frame]) -> [(index: Int, frame: Frame)] {
        frames.enumerated().map { ($0.offset, $0.element) }
    }

    @Test func imageIOReadsAGIFWithTheSizeLoopAndFrameCount() throws {
        let (summary, bytes) = try Self.encode(Self.consecutive(Self.movingSquare(frames: 5)), frameCount: 5)
        let read = GIFBlocks.summary(Data(bytes))
        #expect(read.type == "com.compuserve.gif")
        #expect(read.width == Self.width)
        #expect(read.height == Self.height)
        #expect(read.loopCount == 0)
        #expect(read.frameCount == summary.gifFrameCount)
        #expect(summary.gifFrameCount == 5)
        #expect(summary.byteCount == bytes.count)
    }

    @Test func theBlocksAreOneGlobalTableAndUninterlacedFramesThatAreNeverDisposed() throws {
        let frames = Self.consecutive(Self.movingSquare(frames: 4) + Self.scrollingStripes(frames: 4))
        let (summary, bytes) = try Self.encode(frames, frameCount: frames.count)
        let file = try GIFBlocks.parse(bytes)

        #expect(file.width == Self.width)
        #expect(file.height == Self.height)
        #expect(file.hasGlobalTable)
        #expect(file.globalTableEntries == 1 << Self.palette.tableBits)
        #expect(file.loopCount == 0)
        #expect(file.endsWithTrailer)
        #expect(file.frames.count == summary.gifFrameCount)
        for frame in file.frames {
            let control = try #require(frame.control)
            #expect(control.disposal == 1)
            #expect(control.transparentIndex == Self.palette.colours.count)
            #expect(!frame.hasLocalTable)
            #expect(!frame.isInterlaced)
            #expect(frame.minimumCodeSize == max(2, Self.palette.tableBits))
        }
        // The first frame is the whole frame, opaque.
        let first = try #require(file.frames.first)
        #expect(first.control?.isTransparent == false)
        #expect(first.rect == GIFRect(x: 0, y: 0, width: Self.width, height: Self.height))
        #expect(file.frames.filter { $0.control?.isTransparent == true }.count == summary.transparentFrameCount)
        #expect(summary.transparentFrameCount + summary.opaqueFrameCount == summary.gifFrameCount)
    }

    /// The decoded frames match, pixel for pixel, the palette colours of a differ fed the same frames.
    func expectExact(_ frames: [Frame]) throws -> GIFEncoderSummary {
        let (summary, bytes) = try Self.encode(Self.consecutive(frames), frameCount: frames.count)
        var reference = GIFFrameDiffer(width: Self.width, height: Self.height, palette: Self.palette)
        var expected: [[GIFColour]] = []
        for frame in frames where Self.rgba(frame).withUnsafeBufferPointer({ reference.next(rgba: $0) }) != nil {
            expected.append(GIFBlocks.colours(reference.shown, in: Self.palette))
        }
        let decoded = GIFBlocks.decodedFrames(Data(bytes))
        #expect(decoded.count == expected.count)
        #expect(summary.gifFrameCount == expected.count)
        for (shown, wanted) in zip(decoded, expected) {
            #expect(zip(shown, wanted).filter { $0 != $1 }.count == 0)
        }
        return summary
    }

    @Test func aMovingSquareDecodesExactlyAndUsesTransparentFrames() throws {
        let summary = try expectExact(Self.movingSquare(frames: 8))
        #expect(summary.transparentFrameCount > 0)
    }

    @Test func scrollingStripesDecodeExactlyAndUseOpaqueFrames() throws {
        let summary = try expectExact(Self.scrollingStripes(frames: 8))
        // The first frame is always opaque; later ones are too when that is smaller.
        #expect(summary.opaqueFrameCount > 1)
    }

    /// A rectangle where every pixel changed encodes the same both ways: the transparent one wins.
    @Test func aTieWritesTheTransparentEncoding() throws {
        let still = Self.movingSquare(frames: 1)[0]
        var moved = still
        moved[7 * Self.width + 5] = Self.white
        let (summary, bytes) = try Self.encode([(0, still), (1, moved)], frameCount: 2)
        let file = try GIFBlocks.parse(bytes)
        #expect(file.frames.count == 2)
        #expect(file.frames.last?.rect == GIFRect(x: 5, y: 7, width: 1, height: 1))
        #expect(file.frames.last?.control?.isTransparent == true)
        #expect(summary.transparentFrameCount == 1)
        #expect(summary.opaqueFrameCount == 1)
    }

    @Test func delaysAreWholeCentisecondsSummingToTheLength() throws {
        let a = Self.solid(Self.white), b = Self.solid(Self.black), c = Self.solid(Self.palette.colours[2])

        // 1/15 s is 6.67 cs: 7, 6, 7.
        let (threeSummary, three) = try Self.encode([(0, a), (1, b), (2, c)], frameCount: 3)
        #expect(GIFBlocks.delays(Data(three)) == [7, 6, 7])
        #expect(GIFBlocks.clampedDelays(Data(three)) == [7, 6, 7])
        #expect(try GIFBlocks.parse(three).frames.map { $0.control?.delay } == [7, 6, 7])
        #expect(threeSummary.gifFrameCount == 3)

        // A skipped index holds the previous frame.
        let (_, skipped) = try Self.encode([(0, a), (2, b), (3, c)], frameCount: 5)
        #expect(GIFBlocks.delays(Data(skipped)) == [13, 7, 13])
        #expect(GIFBlocks.delays(Data(skipped)).reduce(0, +) == GIFTiming.centiseconds(through: 5, fps: 15))

        // A frame identical in palette space merges into the previous one.
        let (mergedSummary, merged) = try Self.encode([(0, a), (1, a), (2, b)], frameCount: 3)
        #expect(GIFBlocks.delays(Data(merged)) == [13, 7])
        #expect(GIFBlocks.clampedDelays(Data(merged)) == GIFBlocks.delays(Data(merged)))
        #expect(mergedSummary.gifFrameCount == 2)
        #expect(GIFBlocks.delays(Data(merged)).reduce(0, +) == GIFTiming.centiseconds(through: 3, fps: 15))
    }

    /// A delay over the field's maximum goes on in 1×1 transparent frames that change nothing.
    @Test func aDelayOverTheMaximumIsSplit() throws {
        let (summary, bytes) = try Self.encode(Self.consecutive([Self.movingSquare(frames: 1)[0]]),
                                               frameCount: 7_000, fps: 10)
        #expect(GIFBlocks.delays(Data(bytes)) == [65_535, 4_465])
        let file = try GIFBlocks.parse(bytes)
        #expect(file.frames.count == 2)
        let padding = try #require(file.frames.last)
        #expect(padding.rect == GIFRect(x: 0, y: 0, width: 1, height: 1))
        #expect(padding.control?.isTransparent == true)
        #expect(padding.control?.disposal == 1)
        #expect(padding.control?.delay == 4_465)
        #expect(summary == GIFEncoderSummary(gifFrameCount: 2, transparentFrameCount: 1, opaqueFrameCount: 1,
                                             byteCount: bytes.count))
        let decoded = GIFBlocks.decodedFrames(Data(bytes))
        #expect(decoded.count == 2)
        #expect(decoded.first == decoded.last)
    }

    /// Fails its third write: the encoder's first frame, after the header.
    struct FailingSink: GIFSink {
        struct WriteFailed: Error {}
        var writes = 0
        var count = 0
        mutating func write(_ bytes: UnsafeRawBufferPointer) throws {
            writes += 1
            if writes == 3 { throw WriteFailed() }
            count += bytes.count
        }
        mutating func overwrite(_ bytes: [UInt8], at offset: Int) throws {}
        mutating func close() throws {}
    }

    @Test func aFailingSinkMakesAddThrow() throws {
        var encoder = try GIFEncoder(sink: FailingSink(), width: Self.width, height: Self.height, fps: 15,
                                     palette: Self.palette)
        #expect(throws: FailingSink.WriteFailed.self) {
            try Self.rgba(Self.solid(Self.white)).withUnsafeBufferPointer { try encoder.add(rgba: $0, at: 0) }
        }
    }

    @Test func centisecondsRoundHalfUp() {
        #expect(GIFTiming.maximumDelay == 65_535)
        #expect((0...3).map { GIFTiming.centiseconds(through: $0, fps: 10) } == [0, 10, 20, 30])
        #expect(GIFTiming.centiseconds(through: 7_000, fps: 10) == 70_000)
        #expect((0...4).map { GIFTiming.centiseconds(through: $0, fps: 15) } == [0, 7, 13, 20, 27])
        #expect(GIFTiming.centiseconds(through: 15, fps: 15) == 100)
        #expect(GIFTiming.centiseconds(through: 155, fps: 15) == 1_033)
        #expect((0...3).map { GIFTiming.centiseconds(through: $0, fps: 20) } == [0, 5, 10, 15])
        #expect(GIFTiming.centiseconds(through: 20, fps: 20) == 100)
    }
}
