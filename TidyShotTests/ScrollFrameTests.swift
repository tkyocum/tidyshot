import Foundation
import Testing
@testable import TidyShot

struct ScrollFrameTests {
    /// BGRA bytes of one pixel.
    func pixel(r: UInt8, g: UInt8, b: UInt8) -> [UInt8] { [b, g, r, 255] }

    @Test func greyIsTheIntegerLuminanceOfEachPixel() {
        var pixels: [UInt8] = []
        for (r, g, b) in [(0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255), (30, 20, 10)] as [(UInt8, UInt8, UInt8)] {
            pixels += pixel(r: r, g: g, b: b)
        }
        let frame = ScrollFrame(bgra: Data(pixels), width: 3, height: 2, bytesPerRow: 12)
        // (77 R + 150 G + 29 B) >> 8
        #expect(frame.gray == [0, 255, 76, 149, 28, 21])
        #expect(frame.width == 3)
        #expect(frame.height == 2)
        #expect(frame.bgra == Data(pixels))
    }

    /// Rows from a `CVPixelBuffer` are padded; the frame packs them.
    @Test func paddedRowsAreRepacked() {
        let row0: [UInt8] = pixel(r: 10, g: 20, b: 30) + pixel(r: 40, g: 50, b: 60)
        let row1: [UInt8] = pixel(r: 70, g: 80, b: 90) + pixel(r: 100, g: 110, b: 120)
        let padding = [UInt8](repeating: 0xEE, count: 8)
        let padded = Data(row0 + padding + row1)
        let frame = ScrollFrame(bgra: padded, width: 2, height: 2, bytesPerRow: 16)
        #expect(frame.bgra == Data(row0 + row1))
        #expect(frame.gray.count == 4)
        let expected: Int = (77 * 70 + 150 * 80 + 29 * 90) >> 8
        #expect(Int(frame.gray[2]) == expected)
    }

    @Test func thePointerInitCopiesIntoTheFrame() {
        var bytes: [UInt8] = pixel(r: 1, g: 2, b: 3) + pixel(r: 4, g: 5, b: 6)
        let original = Data(bytes)
        let frame = bytes.withUnsafeBytes { ScrollFrame(bgra: $0.baseAddress!, width: 2, height: 1, bytesPerRow: 8) }
        bytes[0] = 99
        #expect(frame.bgra == original)
    }
}
