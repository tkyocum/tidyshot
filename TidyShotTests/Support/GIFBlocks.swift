import CoreGraphics
import Foundation
import ImageIO
@testable import TidyShot

/// Reads and builds GIF89a files for the encoder tests, written from the format itself. `parse`
/// walks the blocks for the fields ImageIO does not report (table flags, disposal, the transparent
/// index, sub-block lengths), and `codeStream` reads a frame's LZW codes to end-of-information;
/// `decodedFrames` and the delays go through `CGImageSource`.
nonisolated enum GIFBlocks {
    enum ParseError: Error {
        case truncated
        case notAGIF
        case unknownBlock(UInt8)
        /// The code stream ran out before end-of-information.
        case noEndOfInformation
        /// A whole byte or more follows end-of-information.
        case bytesAfterEndOfInformation
        /// A code that is neither a root, clear, end-of-information nor in the table.
        case undefinedCode(Int)
    }

    struct GIFFile {
        var width: Int
        var height: Int
        var hasGlobalTable: Bool
        /// The global table's entry count, `2^(size + 1)` from the logical screen's packed field.
        var globalTableEntries: Int
        /// The global table's colours, every entry the file holds; empty without one.
        var globalTable: [GIFColour]
        /// The NETSCAPE2.0 block's loop count, nil without one.
        var loopCount: Int?
        var frames: [Frame]
        /// The last byte is the trailer, `0x3B`.
        var endsWithTrailer: Bool
    }

    struct Frame {
        /// The graphic control extension before the image, nil without one.
        var control: Control?
        var x: Int
        var y: Int
        var width: Int
        var height: Int
        var hasLocalTable: Bool
        var isInterlaced: Bool
        var minimumCodeSize: Int
        /// Every sub-block's length, the closing zero-length block included.
        var subBlockLengths: [Int]
        /// The LZW code stream: the sub-blocks' bytes, joined.
        var codeBytes: [UInt8]

        var rect: GIFRect { GIFRect(x: x, y: y, width: width, height: height) }
    }

    /// A frame's code stream as `codeStream(of:)` reads it.
    struct CodeStream {
        /// The colour indices the codes stand for.
        var indices: [UInt8]
        /// Clear codes read, a leading one included.
        var clearCount: Int
        /// Data codes read since the last clear code.
        var codesInLastSegment: Int
        /// The width the last data code was read at, 0 without one.
        var lastCodeWidth: Int
        /// The width end-of-information was read at.
        var endWidth: Int
        /// The bits left in the last byte after end-of-information.
        var paddingBits: Int
    }

    struct Control {
        var disposal: Int
        var isTransparent: Bool
        var transparentIndex: Int
        /// Centiseconds.
        var delay: Int
    }

    static func parse(_ bytes: [UInt8]) throws -> GIFFile {
        var reader = Reader(bytes: bytes)
        let signature = String(decoding: try reader.take(6), as: UTF8.self)
        guard signature == "GIF89a" || signature == "GIF87a" else { throw ParseError.notAGIF }
        let width = try reader.uint16()
        let height = try reader.uint16()
        let packed = try reader.byte()
        _ = try reader.take(2)   // background colour index, pixel aspect ratio
        let hasGlobalTable = packed & 0x80 != 0
        let globalTableEntries = 1 << (Int(packed & 0x07) + 1)
        var globalTable: [GIFColour] = []
        if hasGlobalTable {
            let table = try reader.take(globalTableEntries * 3)
            globalTable = (0..<globalTableEntries).map {
                GIFColour(r: table[$0 * 3], g: table[$0 * 3 + 1], b: table[$0 * 3 + 2])
            }
        }

        var file = GIFFile(width: width, height: height, hasGlobalTable: hasGlobalTable,
                           globalTableEntries: globalTableEntries, globalTable: globalTable, loopCount: nil,
                           frames: [], endsWithTrailer: false)
        var control: Control?
        while !reader.isAtEnd {
            let introducer = try reader.byte()
            switch introducer {
            case 0x21:
                let label = try reader.byte()
                switch label {
                case 0xF9:
                    let size = try reader.byte()
                    let fields = try reader.take(Int(size))
                    guard fields.count >= 4 else { throw ParseError.truncated }
                    control = Control(disposal: Int(fields[0] >> 2) & 0x07,
                                      isTransparent: fields[0] & 0x01 != 0,
                                      transparentIndex: Int(fields[3]),
                                      delay: Int(fields[1]) | Int(fields[2]) << 8)
                    _ = try reader.subBlocks()
                case 0xFF:
                    let size = try reader.byte()
                    let identifier = String(decoding: try reader.take(Int(size)), as: UTF8.self)
                    let blocks = try reader.subBlocks()
                    if identifier == "NETSCAPE2.0", let first = blocks.data.first, first.count >= 3, first[0] == 1 {
                        file.loopCount = Int(first[1]) | Int(first[2]) << 8
                    }
                default:
                    _ = try reader.subBlocks()
                }
            case 0x2C:
                let x = try reader.uint16()
                let y = try reader.uint16()
                let frameWidth = try reader.uint16()
                let frameHeight = try reader.uint16()
                let imagePacked = try reader.byte()
                let hasLocalTable = imagePacked & 0x80 != 0
                if hasLocalTable { _ = try reader.take((1 << (Int(imagePacked & 0x07) + 1)) * 3) }
                let minimumCodeSize = Int(try reader.byte())
                let blocks = try reader.subBlocks()
                file.frames.append(Frame(control: control, x: x, y: y, width: frameWidth, height: frameHeight,
                                         hasLocalTable: hasLocalTable, isInterlaced: imagePacked & 0x40 != 0,
                                         minimumCodeSize: minimumCodeSize, subBlockLengths: blocks.lengths,
                                         codeBytes: blocks.data.flatMap { $0 }))
                control = nil
            case 0x3B:
                file.endsWithTrailer = reader.isAtEnd
                return file
            default:
                throw ParseError.unknownBlock(introducer)
            }
        }
        return file
    }

    /// Reads a frame's code stream as GIF89a's LZW defines it, as a decoder does. Codes are packed
    /// LSB first and start at `minimumCodeSize + 1` bits. Each data code after the first since a
    /// clear adds a table entry: the previous code's string plus the first index of this one's (of
    /// the previous string when this code is the entry being added). Once the next free code
    /// reaches `2^width`, the width grows, up to 12 bits; a full table takes no entries until a
    /// clear. It throws unless end-of-information is read and ends in the data's last byte.
    static func codeStream(of frame: Frame) throws -> CodeStream {
        let bytes = frame.codeBytes
        let clearCode = 1 << frame.minimumCodeSize, endCode = clearCode + 1
        let roots = (0..<clearCode).map { [UInt8($0)] } + [[], []]
        var table = roots
        var width = frame.minimumCodeSize + 1
        var previous: [UInt8]?
        var stream = CodeStream(indices: [], clearCount: 0, codesInLastSegment: 0, lastCodeWidth: 0,
                                endWidth: 0, paddingBits: 0)
        var bits = 0, bitCount = 0, nextByte = 0
        while true {
            while bitCount < width {
                guard nextByte < bytes.count else { throw ParseError.noEndOfInformation }
                bits |= Int(bytes[nextByte]) << bitCount
                nextByte += 1
                bitCount += 8
            }
            let code = bits & (1 << width - 1)
            bits >>= width
            bitCount -= width

            if code == clearCode {
                table = roots
                width = frame.minimumCodeSize + 1
                previous = nil
                stream.clearCount += 1
                stream.codesInLastSegment = 0
                continue
            }
            if code == endCode {
                guard nextByte == bytes.count else { throw ParseError.bytesAfterEndOfInformation }
                stream.endWidth = width
                stream.paddingBits = bitCount
                return stream
            }
            let string: [UInt8]
            // Without a previous code the table holds only the roots, clear and end-of-information.
            if code < table.count {
                string = table[code]
            } else if code == table.count, let previous {
                string = previous + [previous[0]]
            } else {
                throw ParseError.undefinedCode(code)
            }
            if let previous, table.count < 4096 { table.append(previous + [string[0]]) }
            stream.indices += string
            stream.codesInLastSegment += 1
            stream.lastCodeWidth = width
            if table.count == 1 << width && width < 12 { width += 1 }
            previous = string
        }
    }

    /// A one-frame GIF around `imageData` (a `GIFLZWWriter` block): header, logical screen, the
    /// palette's global table, one image descriptor at (0, 0) and the trailer, with no `GIFEncoder`.
    static func oneFrame(palette: GIFPalette, width: Int, height: Int, imageData: [UInt8]) -> [UInt8] {
        var bytes = Array("GIF89a".utf8)
        bytes += uint16(width) + uint16(height)
        bytes += [0xF0 | UInt8(palette.tableBits - 1), 0, 0]
        bytes += palette.tableBytes
        bytes += [0x2C] + uint16(0) + uint16(0) + uint16(width) + uint16(height) + [0]
        bytes += imageData
        bytes += [0x3B]
        return bytes
    }

    /// Each frame as ImageIO composes it, drawn into 8-bit sRGB RGBA, row by row from the top.
    static func decodedFrames(_ data: Data) -> [[GIFColour]] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        return (0..<CGImageSourceGetCount(source)).map { index in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return [] }
            return pixels(of: image)
        }
    }

    /// Each frame's delay in centiseconds, from `kCGImagePropertyGIFUnclampedDelayTime`.
    static func delays(_ data: Data) -> [Int] {
        frameDelays(data, key: kCGImagePropertyGIFUnclampedDelayTime)
    }

    /// Each frame's delay in centiseconds, from the clamped `kCGImagePropertyGIFDelayTime`.
    static func clampedDelays(_ data: Data) -> [Int] {
        frameDelays(data, key: kCGImagePropertyGIFDelayTime)
    }

    /// The file's type, frame count, first frame's pixel size and loop count, as ImageIO reads them.
    static func summary(_ data: Data) -> (type: String?, frameCount: Int, width: Int?, height: Int?, loopCount: Int?) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return (nil, 0, nil, nil, nil) }
        let first = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let file = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let gif = file?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return (CGImageSourceGetType(source) as String?, CGImageSourceGetCount(source),
                first?[kCGImagePropertyPixelWidth] as? Int, first?[kCGImagePropertyPixelHeight] as? Int,
                gif?[kCGImagePropertyGIFLoopCount] as? Int)
    }

    /// `indices` as the colours a decoder shows for them.
    static func colours(_ indices: [UInt8], in palette: GIFPalette) -> [GIFColour] {
        indices.map { palette.colours[Int($0)] }
    }

    // MARK: Private

    private static func frameDelays(_ data: Data, key: CFString) -> [Int] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        return (0..<CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let seconds = gif?[key] as? Double ?? -1
            return Int((seconds * 100).rounded())
        }
    }

    private static func pixels(of image: CGImage) -> [GIFColour] {
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }
        return (0..<width * height).map { GIFColour(r: rgba[$0 * 4], g: rgba[$0 * 4 + 1], b: rgba[$0 * 4 + 2]) }
    }

    private static func uint16(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF)]
    }

    private struct Reader {
        let bytes: [UInt8]
        var position = 0

        var isAtEnd: Bool { position >= bytes.count }

        mutating func byte() throws -> UInt8 {
            guard position < bytes.count else { throw ParseError.truncated }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func uint16() throws -> Int {
            let low = try byte(), high = try byte()
            return Int(low) | Int(high) << 8
        }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard position + count <= bytes.count else { throw ParseError.truncated }
            defer { position += count }
            return Array(bytes[position..<position + count])
        }

        /// Sub-blocks up to and including the zero-length one.
        mutating func subBlocks() throws -> (lengths: [Int], data: [[UInt8]]) {
            var lengths: [Int] = []
            var data: [[UInt8]] = []
            while true {
                let length = Int(try byte())
                lengths.append(length)
                if length == 0 { return (lengths, data) }
                data.append(try take(length))
            }
        }
    }
}
