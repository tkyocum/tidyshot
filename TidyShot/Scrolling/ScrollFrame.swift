import Accelerate
import CoreGraphics
import Foundation

/// One captured frame of the scrolled area: tightly packed BGRA plus a grey plane for matching.
/// Built on the stream's sample-handler queue (spec 2.8, Frame source), so it is a plain value.
nonisolated struct ScrollFrame: Sendable {
    let width: Int
    let height: Int
    /// `width * height * 4` bytes, rows packed with no padding, blue first.
    let bgra: Data
    /// `width * height` bytes of luminance, `(77 R + 150 G + 29 B) >> 8` (white stays 255). Only
    /// ever compared with other frames' grey, never shown.
    let gray: [UInt8]
    /// The session's serial for this frame (`ScrollCaptureSession.frameSerial` when it took it), 0
    /// for a frame that has none. `ScrollCaptureSession.addLatestFrame` compares it with the serial
    /// of the frame last stitched; the diagnostics log it too.
    var serial = 0

    /// Copies `height` rows of `width` BGRA pixels out of `source`, whose rows are `bytesPerRow`
    /// apart, so the caller can release a `CVPixelBuffer` as soon as this returns. The grey plane is
    /// one vImage matrix multiply over the source rows, which keeps a Debug build's per-frame cost
    /// close to Release's.
    init(bgra source: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        precondition(width > 0 && height > 0 && bytesPerRow >= width * 4, "bad frame geometry")
        let rowBytes = width * 4
        var packed = Data(count: rowBytes * height)
        packed.withUnsafeMutableBytes { out in
            for y in 0..<height {
                (out.baseAddress! + y * rowBytes).copyMemory(from: source.advanced(by: y * bytesPerRow), byteCount: rowBytes)
            }
        }
        var plane = [UInt8](repeating: 0, count: width * height)
        plane.withUnsafeMutableBufferPointer { grey in
            var from = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source), height: vImagePixelCount(height),
                                     width: vImagePixelCount(width), rowBytes: bytesPerRow)
            var to = vImage_Buffer(data: grey.baseAddress!, height: vImagePixelCount(height),
                                   width: vImagePixelCount(width), rowBytes: width)
            // The matrix follows the memory order, B, G, R, A; the divisor keeps white at 255.
            let weights: [Int16] = [29, 150, 77, 0]
            let result = vImageMatrixMultiply_ARGB8888ToPlanar8(&from, &to, weights, 256, nil, 0, vImage_Flags(kvImageNoFlags))
            precondition(result == kvImageNoError, "grey conversion failed: \(result)")
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

extension ScrollFrame {
    /// A CGImage over packed BGRA rows (`bitsPerComponent` 8, `bytesPerRow` width x 4,
    /// `byteOrder32Little | noneSkipFirst`) without copying them, tagged with `colorSpace`. Nil for
    /// an empty size or too few bytes.
    nonisolated static func cgImage(bgra: Data, width: Int, height: Int, colorSpace: CGColorSpace,
                                    interpolate: Bool) -> CGImage? {
        guard width > 0, height > 0, bgra.count >= width * height * 4,
              let provider = CGDataProvider(data: bgra as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: interpolate, intent: .defaultIntent)
    }
}
