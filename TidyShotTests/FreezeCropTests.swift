import CoreGraphics
import Testing
@testable import TidyShot

struct FreezeCropTests {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let retinaImage = CGSize(width: 2880, height: 1800)

    @Test func aRetinaSelectionDoublesIntoPixels() {
        let rect = FreezeCrop.pixelRect(selection: CGRect(x: 100, y: 200, width: 300, height: 150),
                                        displayFrame: primary, scale: 2, imageSize: retinaImage)
        #expect(rect == CGRect(x: 200, y: 400, width: 600, height: 300))
    }

    /// The selection is in global points; the display's own origin is taken off first.
    @Test func aSelectionOnAnotherDisplayIsMadeLocalToIt() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: -500, y: 200, width: 100, height: 100),
                                     displayFrame: left, scale: 1, imageSize: CGSize(width: 1920, height: 1080))
                == CGRect(x: 1420, y: 200, width: 100, height: 100))
        let above = CGRect(x: 0, y: -900, width: 1440, height: 900)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: -890, width: 50, height: 50),
                                     displayFrame: above, scale: 2, imageSize: retinaImage)
                == CGRect(x: 20, y: 20, width: 100, height: 100))
    }

    /// A frozen crop and a live capture of the same rect must have the same pixel size.
    @Test func aFractionalRectHasTheSizeOfALiveCapture() throws {
        let selection = CGRect(x: 10.3, y: 20.2, width: 100.3, height: 50.4)
        let rect = try #require(FreezeCrop.pixelRect(selection: selection, displayFrame: primary, scale: 2,
                                                     imageSize: retinaImage))
        let live = Geometry.pixelSize(points: selection.size, scale: 2)
        #expect(Int(rect.width) == live.width)
        #expect(Int(rect.height) == live.height)
        #expect(rect == CGRect(x: 21, y: 40, width: 201, height: 101))
    }

    /// Rounding the origin up and the size up can run one pixel past the right edge; the origin
    /// moves back so the size stays that of a live capture.
    @Test func roundingPastTheFarEdgeMovesTheOriginBack() {
        let rect = FreezeCrop.pixelRect(selection: CGRect(x: 0.25, y: 0, width: 1439.75, height: 900),
                                        displayFrame: primary, scale: 2, imageSize: retinaImage)
        #expect(rect == CGRect(x: 0, y: 0, width: 2880, height: 1800))
    }

    /// The same on the vertical axis.
    @Test func roundingPastTheBottomEdgeMovesTheOriginBack() {
        let rect = FreezeCrop.pixelRect(selection: CGRect(x: 0, y: 0.25, width: 1440, height: 899.75),
                                        displayFrame: primary, scale: 2, imageSize: retinaImage)
        #expect(rect == CGRect(x: 0, y: 0, width: 2880, height: 1800))
    }

    /// At 1x a point is a pixel: the origin and size round to whole pixels, and the far edge is
    /// still held to the image.
    @Test func aNonRetinaSelectionRoundsToWholePixels() {
        let image = CGSize(width: 1440, height: 900)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10.3, y: 20.2, width: 100.3, height: 50.4),
                                     displayFrame: primary, scale: 1, imageSize: image)
                == CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 0.5, y: 0, width: 1439.5, height: 900),
                                     displayFrame: primary, scale: 1, imageSize: image)
                == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @Test func roundingPastTheNearEdgeClampsToZero() {
        let rect = FreezeCrop.pixelRect(selection: CGRect(x: -0.3, y: 0, width: 100, height: 100),
                                        displayFrame: primary, scale: 2, imageSize: retinaImage)
        #expect(rect == CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    /// More than a rounding pixel outside the image is not a crop of it: nil, so the caller
    /// captures live.
    @Test func aRectOutsideTheImageIsNil() {
        for selection in [CGRect(x: 2000, y: 0, width: 100, height: 100),
                          CGRect(x: -50, y: 0, width: 100, height: 100),
                          CGRect(x: 1400, y: 0, width: 100, height: 100),
                          CGRect(x: 0, y: 880, width: 100, height: 100)] {
            #expect(FreezeCrop.pixelRect(selection: selection, displayFrame: primary, scale: 2,
                                         imageSize: retinaImage) == nil)
        }
    }

    @Test func anEmptyOrDegenerateRectIsNil() {
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 0, height: 50),
                                     displayFrame: primary, scale: 2, imageSize: retinaImage) == nil)
        // 0.2 pt at scale 2 rounds to no pixel.
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 0.2, height: 50),
                                     displayFrame: primary, scale: 2, imageSize: retinaImage) == nil)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 50, height: 50),
                                     displayFrame: primary, scale: 0, imageSize: retinaImage) == nil)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 50, height: 50),
                                     displayFrame: primary, scale: 2, imageSize: .zero) == nil)
    }

    /// A 40 by 20 px image on a display of 20 by 10 pt at (100, 50), scale 2: top left red, top
    /// right green, bottom left blue, bottom right white.
    func quadrants() -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CoreGraphics y runs up, so the top half of the image is y 10 to 20.
        let paint: [(CGRect, [CGFloat])] = [
            (CGRect(x: 0, y: 10, width: 20, height: 10), [1, 0, 0]),
            (CGRect(x: 20, y: 10, width: 20, height: 10), [0, 1, 0]),
            (CGRect(x: 0, y: 0, width: 20, height: 10), [0, 0, 1]),
            (CGRect(x: 20, y: 0, width: 20, height: 10), [1, 1, 1]),
        ]
        for (rect, rgb) in paint {
            context.setFillColor(CGColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
            context.fill(rect)
        }
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y) counted from the top left.
    func rgba(_ image: CGImage, x: Int, y: Int) -> [Int] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let base = y * context.bytesPerRow + x * 4
        return (0..<4).map { Int(data[base + $0]) }
    }

    @Test func theCropHoldsTheSelectionsPixels() throws {
        let frame = CGRect(x: 100, y: 50, width: 20, height: 10)
        let topRight = try #require(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 110, y: 50, width: 10, height: 5),
                                                       displayFrame: frame, scale: 2))
        #expect(topRight.width == 20)
        #expect(topRight.height == 10)
        #expect(rgba(topRight, x: 5, y: 5) == [0, 255, 0, 255])
        let bottomLeft = try #require(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 100, y: 55, width: 10, height: 5),
                                                         displayFrame: frame, scale: 2))
        #expect(rgba(bottomLeft, x: 5, y: 5) == [0, 0, 255, 255])
        // A selection spanning two quadrants holds both.
        let across = try #require(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 105, y: 50, width: 10, height: 5),
                                                     displayFrame: frame, scale: 2))
        #expect(rgba(across, x: 2, y: 5) == [255, 0, 0, 255])
        #expect(rgba(across, x: 17, y: 5) == [0, 255, 0, 255])
    }

    @Test func croppingOutsideTheImageGivesNothing() {
        let frame = CGRect(x: 100, y: 50, width: 20, height: 10)
        #expect(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 130, y: 50, width: 10, height: 5),
                                   displayFrame: frame, scale: 2) == nil)
    }

    private func gradient(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * context.bytesPerRow + x * 4
                pixels[offset] = UInt8(x % 256)
                pixels[offset + 1] = UInt8(y % 256)
                pixels[offset + 2] = 7
                pixels[offset + 3] = 255
            }
        }
        return try #require(context.makeImage())
    }

    private func bytes(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: image.width * image.height * 4))
    }

    /// The crop owns its pixels: it does not keep the whole snapshot alive, and it holds exactly
    /// what the snapshot held at that rect.
    @Test func aCropOwnsItsPixelsAndKeepsThem() throws {
        let source = try gradient(width: 400, height: 300)
        let frame = CGRect(x: 0, y: 0, width: 200, height: 150)
        let selection = CGRect(x: 30, y: 20, width: 50, height: 40)
        let result = try #require(FreezeCrop.cropped(source, selection: selection, displayFrame: frame, scale: 2))
        #expect(result.width == 100)
        #expect(result.height == 80)
        #expect(result.bytesPerRow < source.bytesPerRow)
        #expect(result.dataProvider !== source.dataProvider)
        let expected = try #require(source.cropping(to: CGRect(x: 60, y: 40, width: 100, height: 80)))
        #expect(try bytes(result) == bytes(expected))
        #expect(FreezeCrop.cropped(source, selection: CGRect(x: 500, y: 0, width: 50, height: 40),
                                   displayFrame: frame, scale: 2) == nil)
    }
}
