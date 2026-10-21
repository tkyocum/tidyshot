import CoreGraphics
import Testing
@testable import TidyShot

/// A 64 by 48 fixture: the sides differ, so a swapped axis or a flip about the wrong side shows.
struct ImageRectsTests {
    let width = 64
    let height = 48
    let size = CGSize(width: 64, height: 48)

    func context(data: UnsafeMutableRawPointer? = nil) -> CGContext {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Black, with `rect` filled red in the context's own coordinates (origin bottom left).
    func image(redAt rect: CGRect) -> CGImage {
        let context = context()
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(rect)
        return context.makeImage()!
    }

    /// The red channel by row and column, row 0 first: the top row, as CGImage stores it.
    func redChannel(_ image: CGImage) -> [[UInt8]] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context(data: buffer.baseAddress).draw(image, in: CGRect(origin: .zero, size: size))
        }
        return (0..<height).map { row in (0..<width).map { column in pixels[(row * width + column) * 4] } }
    }

    /// A model rect, filled through `bottomLeft` in a Core Graphics context, lands on exactly
    /// those CGImage rows and columns.
    @Test func bottomLeftFlipsRows() {
        let topLeft = CGRect(x: 4, y: 6, width: 10, height: 8)
        let converted = ImageRects.bottomLeft(topLeft, imageHeight: height)
        #expect(converted == CGRect(x: 4, y: 34, width: 10, height: 8))
        let red = redChannel(image(redAt: converted))
        #expect(red.indices.filter { red[$0][4] == 255 } == Array(6..<14))
        #expect(red[6].indices.filter { red[6][$0] == 255 } == Array(4..<14))
    }

    @Test func topLeftInvertsBottomLeft() {
        let rects = [CGRect(x: 4, y: 6, width: 10, height: 8), CGRect(origin: .zero, size: size),
                     CGRect(x: 60.5, y: 0.25, width: 3.5, height: 47.75), CGRect(x: 0, y: 47, width: 1, height: 1)]
        for rect in rects {
            #expect(ImageRects.topLeft(ImageRects.bottomLeft(rect, imageHeight: height), imageHeight: height) == rect)
        }
        // The last top-left row is the first bottom-left row, and the other way round.
        #expect(ImageRects.bottomLeft(CGRect(x: 0, y: 47, width: 64, height: 1), imageHeight: height)
                == CGRect(x: 0, y: 0, width: 64, height: 1))
        #expect(ImageRects.topLeft(CGRect(x: 2, y: 40, width: 5, height: 8), imageHeight: height)
                == CGRect(x: 2, y: 0, width: 5, height: 8))
    }

    @Test func integralRoundsOutAndClips() {
        #expect(ImageRects.integral(CGRect(x: 3.2, y: 4.7, width: 10.1, height: 5.6), clippedTo: size)
                == CGRect(x: 3, y: 4, width: 11, height: 7))
        #expect(ImageRects.integral(CGRect(x: 8, y: 9, width: 10, height: 12), clippedTo: size)
                == CGRect(x: 8, y: 9, width: 10, height: 12))
        #expect(ImageRects.integral(CGRect(x: -5.5, y: 40.2, width: 20, height: 20), clippedTo: size)
                == CGRect(x: 0, y: 40, width: 15, height: 8))
        // A rect dragged up and to the left has a negative size; it is standardised.
        #expect(ImageRects.integral(CGRect(x: 20, y: 30, width: -10, height: -5), clippedTo: size)
                == CGRect(x: 10, y: 25, width: 10, height: 5))
    }

    @Test func emptyWhenOutside() {
        #expect(ImageRects.integral(CGRect(x: 70, y: 10, width: 5, height: 5), clippedTo: size) == .zero)
        // Touching the right edge, or ending at row 0, covers no pixel.
        #expect(ImageRects.integral(CGRect(x: 64, y: 0, width: 4, height: 4), clippedTo: size) == .zero)
        #expect(ImageRects.integral(CGRect(x: 10, y: -8, width: 5, height: 8), clippedTo: size) == .zero)
        #expect(ImageRects.integral(CGRect(x: 10, y: 10, width: 0, height: 5), clippedTo: size) == .zero)
        #expect(ImageRects.integral(.null, clippedTo: size) == .zero)
    }
}
