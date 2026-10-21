import Foundation

/// One captured frame of the scrolled area: tightly packed BGRA plus a grey plane for matching.
/// Built on the stream's sample-handler queue (spec 2.8, Frame source), so it is a plain value.
nonisolated struct ScrollFrame: Sendable {
    let width: Int
    let height: Int
    /// `width * height * 4` bytes, rows packed with no padding, blue first.
    let bgra: Data
    /// `width * height` bytes of luminance, `(77 R + 150 G + 29 B) >> 8` (white stays 255).
    let gray: [UInt8]

    /// Copies `height` rows of `width` BGRA pixels out of `source`, whose rows are `bytesPerRow`
    /// apart, so the caller can release a `CVPixelBuffer` as soon as this returns.
    init(bgra source: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        precondition(width > 0 && height > 0 && bytesPerRow >= width * 4, "bad frame geometry")
        let rowBytes = width * 4
        var plane = [UInt8](repeating: 0, count: width * height)
        var packed = Data(count: rowBytes * height)
        packed.withUnsafeMutableBytes { out in
            plane.withUnsafeMutableBufferPointer { grey in
                for y in 0..<height {
                    let row = source.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    (out.baseAddress! + y * rowBytes).copyMemory(from: row, byteCount: rowBytes)
                    for x in 0..<width {
                        let p = row + x * 4
                        grey[y * width + x] = UInt8((77 * Int(p[2]) + 150 * Int(p[1]) + 29 * Int(p[0])) >> 8)
                    }
                }
            }
        }
        self.width = width
        self.height = height
        self.bgra = packed
        self.gray = plane
    }

    init(bgra source: Data, width: Int, height: Int, bytesPerRow: Int) {
        precondition(source.count >= bytesPerRow * (height - 1) + width * 4, "bgra is too short")
        self = source.withUnsafeBytes {
            ScrollFrame(bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)
        }
    }
}
