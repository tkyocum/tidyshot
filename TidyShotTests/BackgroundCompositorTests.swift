import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct BackgroundCompositorTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let blue: [UInt8] = [0, 0, 255, 255]
    static let white: [UInt8] = [255, 255, 255, 255]
    static let clear: [UInt8] = [0, 0, 0, 0]

    /// A premultiplied RGBA image from a per-pixel closure, top-left origin.
    func makeImage(_ width: Int, _ height: Int, pixel: (Int, Int) -> [UInt8]) -> CGImage {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width { bytes += pixel(x, y) }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    func blueContent(_ width: Int = 100, _ height: Int = 80) -> CGImage {
        makeImage(width, height) { _, _ in Self.blue }
    }

    let white = RGBA(red: 1, green: 1, blue: 1)

    func style(fill: BackgroundFill? = nil, padding: Double = 20, radius: Double = 12,
               shadow: Bool = false, aspect: BackgroundAspect = .auto) -> BackgroundStyle {
        BackgroundStyle(fill: fill ?? .solid(white), padding: padding, cornerRadius: radius,
                        shadow: shadow, aspect: aspect)
    }

    func bitmap(_ image: CGImage?) throws -> EditorFlattenerTests.Bitmap {
        try EditorFlattenerTests.Bitmap(#require(image))
    }

    /// Whether every channel of `pixel` is within `tolerance` of `expected`.
    func close(_ pixel: [UInt8], _ expected: [UInt8], tolerance: Int = 3) -> Bool {
        zip(pixel, expected).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
    }

    @Test func outputSizeEqualsTheLayout() throws {
        let content = blueContent()
        let style = style(padding: 24, aspect: .square)
        let layout = try #require(BackgroundLayout.make(contentSize: CGSize(width: 100, height: 80),
                                                        style: style, scale: 2))
        let output = try #require(BackgroundCompositor.compose(content, style: style, scale: 2, fillImage: nil))
        #expect(CGSize(width: output.width, height: output.height) == layout.canvasSize)
    }

    /// The editor's preview renders the fill alone, as compose draws it under the content.
    @Test func fillAloneHasTheSizeAndTheFill() throws {
        let red = RGBA(red: 1, green: 0, blue: 0)
        let solid = try bitmap(BackgroundCompositor.fill(.solid(red), size: CGSize(width: 30, height: 20), fillImage: nil))
        #expect(solid.width == 30 && solid.height == 20)
        #expect(solid[0, 0] == [255, 0, 0, 255])
        #expect(solid[29, 19] == [255, 0, 0, 255])
        // The same canvas as a 10 px content with 10 px of padding: the same gradient corners.
        let gradient = try bitmap(BackgroundCompositor.fill(.gradient(0), size: CGSize(width: 30, height: 30), fillImage: nil))
        let composed = try bitmap(BackgroundCompositor.compose(blueContent(10, 10), style: style(fill: .gradient(0), padding: 10),
                                                               scale: 1, fillImage: nil))
        #expect(gradient[0, 0] == composed[0, 0])
        #expect(gradient[29, 29] == composed[29, 29])
        #expect(BackgroundCompositor.fill(.gradient(0), size: .zero, fillImage: nil) == nil)
    }

    @Test func solidFillShowsAtTheCorner() throws {
        let red = RGBA(red: 1, green: 0, blue: 0)
        let output = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(fill: .solid(red)),
                                                             scale: 1, fillImage: nil))
        #expect(output[0, 0] == [255, 0, 0, 255])
        #expect(output[output.width - 1, output.height - 1] == [255, 0, 0, 255])
    }

    @Test func contentPixelEqualsTheContent() throws {
        let content = makeImage(100, 80) { x, y in [UInt8(x), UInt8(y), 200, 255] }
        let output = try bitmap(BackgroundCompositor.compose(content, style: style(), scale: 1, fillImage: nil))
        // The content sits at (20, 20) on a 140 x 120 canvas.
        #expect(output.width == 140 && output.height == 120)
        #expect(output[20 + 50, 20 + 40] == [50, 40, 200, 255])
        #expect(output[20 + 99, 20 + 79 - 15] == [99, 64, 200, 255])
    }

    @Test func roundedClipLeavesTheCornerToTheFill() throws {
        let output = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(radius: 12),
                                                             scale: 1, fillImage: nil))
        for (x, y) in [(20, 20), (119, 20), (20, 99), (119, 99)] {
            #expect(output[x, y] == Self.white, "corner \(x),\(y)")
        }
        #expect(output[32, 32] == Self.blue)
    }

    @Test func shadowDarkensTheFillBelowTheContent() throws {
        let withShadow = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(shadow: true),
                                                                 scale: 1, fillImage: nil))
        let without = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(shadow: false),
                                                              scale: 1, fillImage: nil))
        // Two pixels under the content, in its middle.
        let shaded = withShadow[70, 102]
        #expect(without[70, 102] == Self.white)
        #expect(shaded[0] < 250 && shaded[1] < 250)
        // The content itself is untouched.
        #expect(withShadow[70, 60] == Self.blue)
    }

    @Test func shadowIsOffsetDownNotUp() throws {
        let output = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(padding: 40, shadow: true),
                                                             scale: 1, fillImage: nil))
        // Content at (40, 40) to (140, 120). Just above is lighter than just below.
        #expect(output[90, 38][0] > output[90, 122][0])
    }

    @Test func transparentContentCornerShowsTheFill() throws {
        let content = makeImage(100, 80) { x, y in x < 5 && y < 5 ? Self.clear : Self.blue }
        let output = try bitmap(BackgroundCompositor.compose(content, style: style(radius: 0),
                                                             scale: 1, fillImage: nil))
        #expect(output[20, 20] == Self.white)
        #expect(output[24, 24] == Self.white)
        #expect(output[25, 20] == Self.blue)
        #expect(output[20, 25] == Self.blue)
    }

    @Test func nilAboveTheLimit() {
        let wide = makeImage(16_385, 1) { _, _ in Self.blue }
        #expect(BackgroundCompositor.compose(wide, style: style(), scale: 1, fillImage: nil) == nil)
    }

    @Test func gradientRunsTopLeftToBottomRight() throws {
        let output = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(fill: .gradient(0), radius: 0),
                                                             scale: 1, fillImage: nil))
        let first = BackgroundPresets.gradients[0].first
        let second = BackgroundPresets.gradients[0].second
        func bytes(_ colour: RGBA) -> [UInt8] {
            [UInt8((colour.red * 255).rounded()), UInt8((colour.green * 255).rounded()),
             UInt8((colour.blue * 255).rounded()), 255]
        }
        #expect(close(output[0, 0], bytes(first), tolerance: 6))
        #expect(close(output[output.width - 1, output.height - 1], bytes(second), tolerance: 6))
        // The other two corners lie on the gradient's midline.
        #expect(!close(output[output.width - 1, 0], bytes(first), tolerance: 20))
        #expect(!close(output[output.width - 1, 0], bytes(second), tolerance: 20))
    }

    @Test func outOfRangeIndexDrawsPresetZero() throws {
        let zero = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(fill: .gradient(0)),
                                                           scale: 1, fillImage: nil))
        for index in [12, 99, -1] {
            let other = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(fill: .gradient(index)),
                                                                scale: 1, fillImage: nil))
            #expect(other.rows == zero.rows, "index \(index)")
        }
    }

    @Test func nilFillImageDrawsPresetZero() throws {
        let zero = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(fill: .gradient(0)),
                                                           scale: 1, fillImage: nil))
        for fill in [BackgroundFill.desktopPicture, .customImage] {
            let other = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(fill: fill),
                                                                scale: 1, fillImage: nil))
            #expect(other.rows == zero.rows)
        }
    }

    @Test func fillImageIsDrawnAspectFillAndCentred() throws {
        // 40 x 10: red on the left half, green on the right. On a 140 x 120 canvas it scales by 12
        // (to 480 x 120) and is cut equally left and right, so the canvas shows the middle 140
        // pixels: red left of the centre, green right of it.
        let picture = makeImage(40, 10) { x, _ in x < 20 ? [255, 0, 0, 255] : [0, 255, 0, 255] }
        let output = try bitmap(BackgroundCompositor.compose(blueContent(), style: style(fill: .desktopPicture),
                                                             scale: 1, fillImage: picture))
        #expect(output[2, 2] == [255, 0, 0, 255])
        #expect(output[137, 117] == [0, 255, 0, 255])
    }
}
