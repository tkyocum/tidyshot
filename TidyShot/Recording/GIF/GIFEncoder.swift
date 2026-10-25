import Foundation

/// GIF delays are whole centiseconds.
nonisolated enum GIFTiming {
    /// The delay field's maximum.
    static let maximumDelay = 65_535

    /// The time at the end of output frame `e - 1` (exclusive end `e`), `e × 100 / fps` rounded
    /// half up. A frame covering output frames `i..<e` lasts `centiseconds(through: e) −
    /// centiseconds(through: i)`, so the GIF's length is exact (7, 6, 7 cs at 15 fps).
    static func centiseconds(through e: Int, fps: Int) -> Int {
        (e * 200 + fps) / (2 * fps)
    }
}

nonisolated struct GIFEncoderSummary: Equatable, Sendable {
    var gifFrameCount: Int
    var transparentFrameCount: Int
    var opaqueFrameCount: Int
    var byteCount: Int
}

/// TidyShot's own GIF89a encoder: one global table and no local tables, a NETSCAPE2.0 loop
/// forever, and frames that are never disposed and hold only their changed rectangle, each
/// written transparent or opaque, whichever is smaller. A frame identical in palette space to the
/// one before lengthens its delay instead.
nonisolated struct GIFEncoder<Sink: GIFSink> {
    /// Where the bytes went; a test reads `GIFDataSink.bytes` here.
    private(set) var sink: Sink
    private let width: Int
    private let height: Int
    private let fps: Int
    private let transparentIndex: UInt8
    private let minimumCodeSize: Int
    private var differ: GIFFrameDiffer
    private var lzw = GIFLZWWriter()
    /// The change's two encodings, reused across frames.
    private var transparentData: [UInt8] = []
    private var opaqueData: [UInt8] = []
    /// A frame's graphic control extension and image descriptor.
    private var header: [UInt8] = []

    /// The output frame the last GIF frame started at, and where its delay field is, nil before
    /// the first frame.
    private var frameStart: Int?
    private var delayOffset = 0
    private var lastIndex = -1
    private var gifFrameCount = 0
    private var transparentFrameCount = 0
    private var opaqueFrameCount = 0

    /// Writes the header, the logical screen, the global table and the loop block.
    init(sink: Sink, width: Int, height: Int, fps: Int, palette: GIFPalette, hysteresis: Int = 4) throws {
        precondition((1...0xFFFF).contains(width) && (1...0xFFFF).contains(height), "GIF sizes are 16-bit")
        precondition(fps > 0)
        self.sink = sink
        self.width = width
        self.height = height
        self.fps = fps
        transparentIndex = palette.transparentIndex
        minimumCodeSize = max(2, palette.tableBits)
        differ = GIFFrameDiffer(width: width, height: height, palette: palette, hysteresis: hysteresis)

        var start = Array("GIF89a".utf8)
        // Logical screen: a global table of 2^tableBits entries, 8 bits a channel, unsorted.
        start += Self.uint16(width) + Self.uint16(height) + [0xF0 | UInt8(palette.tableBits - 1), 0, 0]
        start += palette.tableBytes
        // NETSCAPE2.0, loop count 0: forever.
        start += [0x21, 0xFF, 11] + Array("NETSCAPE2.0".utf8) + [3, 1] + Self.uint16(0) + [0]
        try write(start)
    }

    /// Output frame `index` shows `rgba` (4 bytes a pixel, the fourth ignored). Indices increase;
    /// a skipped index holds the previous frame. A frame that changes nothing in palette space
    /// lengthens the previous one; any other ends the previous frame's delay at `index` and is
    /// written as a new frame. The first frame starts at 0.
    mutating func add(rgba: UnsafeBufferPointer<UInt8>, at index: Int) throws {
        precondition(index > lastIndex, "Frames are added in increasing order")
        guard let change = differ.next(rgba: rgba) else {
            lastIndex = index
            return
        }
        if let frameStart { try endFrame(startedAt: frameStart, endingAt: index) }

        // The first frame is the whole frame, opaque. Later changes are encoded both ways, and the
        // smaller written, transparent on a tie.
        opaqueData.removeAll(keepingCapacity: true)
        change.opaque.withUnsafeBufferPointer { lzw.encode($0, minimumCodeSize: minimumCodeSize, into: &opaqueData) }
        var isTransparent = false
        if frameStart != nil {
            transparentData.removeAll(keepingCapacity: true)
            change.changedOnly.withUnsafeBufferPointer {
                lzw.encode($0, minimumCodeSize: minimumCodeSize, into: &transparentData)
            }
            isTransparent = transparentData.count <= opaqueData.count
        }
        try writeHeader(rect: change.rect, isTransparent: isTransparent, delay: 0)
        try write(isTransparent ? transparentData : opaqueData)

        frameStart = frameStart == nil ? 0 : index
        lastIndex = index
        gifFrameCount += 1
        if isTransparent { transparentFrameCount += 1 } else { opaqueFrameCount += 1 }
    }

    /// Ends the last frame's delay at `frameCount`, writes the trailer and closes the sink.
    mutating func finish(frameCount: Int) throws -> GIFEncoderSummary {
        guard let frameStart else { preconditionFailure("A GIF needs a frame") }
        precondition(frameCount > lastIndex, "The GIF ends after its last frame")
        try endFrame(startedAt: frameStart, endingAt: frameCount)
        try write([0x3B])
        try sink.close()
        return GIFEncoderSummary(gifFrameCount: gifFrameCount, transparentFrameCount: transparentFrameCount,
                                 opaqueFrameCount: opaqueFrameCount, byteCount: sink.count)
    }

    /// Closes the sink without the trailer, for a caller that stops early; the caller removes the
    /// file.
    mutating func abandon() {
        try? sink.close()
    }

    // MARK: Private

    /// Patches the delay of the frame that started at `start`. A delay over the field's maximum
    /// goes on in 1×1 transparent frames at (0, 0), which change no pixel.
    private mutating func endFrame(startedAt start: Int, endingAt end: Int) throws {
        var remaining = GIFTiming.centiseconds(through: end, fps: fps) - GIFTiming.centiseconds(through: start, fps: fps)
        let delay = min(remaining, GIFTiming.maximumDelay)
        try sink.overwrite(Self.uint16(delay), at: delayOffset)
        remaining -= delay
        while remaining > 0 {
            let part = min(remaining, GIFTiming.maximumDelay)
            try writeHeader(rect: GIFRect(x: 0, y: 0, width: 1, height: 1), isTransparent: true, delay: part)
            transparentData.removeAll(keepingCapacity: true)
            [transparentIndex].withUnsafeBufferPointer {
                lzw.encode($0, minimumCodeSize: minimumCodeSize, into: &transparentData)
            }
            try write(transparentData)
            gifFrameCount += 1
            transparentFrameCount += 1
            remaining -= part
        }
    }

    /// The graphic control extension (disposal 1, do not dispose) and the image descriptor (no
    /// local table, not interlaced). Records where the delay is, for `endFrame` to patch.
    private mutating func writeHeader(rect: GIFRect, isTransparent: Bool, delay: Int) throws {
        header.removeAll(keepingCapacity: true)
        header += [0x21, 0xF9, 4, isTransparent ? 0x05 : 0x04]
        delayOffset = sink.count + header.count
        header += Self.uint16(delay) + [transparentIndex, 0]
        header += [0x2C] + Self.uint16(rect.x) + Self.uint16(rect.y) + Self.uint16(rect.width)
            + Self.uint16(rect.height) + [0]
        try write(header)
    }

    private mutating func write(_ bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { try sink.write($0) }
    }

    private static func uint16(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]
    }
}
