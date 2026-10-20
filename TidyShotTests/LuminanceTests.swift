import CoreGraphics
import Testing
@testable import TidyShot

struct LuminanceTests {
    /// A `width` by `height` sRGB image; `paint` draws in CoreGraphics coordinates (origin bottom left).
    func image(width: Int = 40, height: Int = 40, _ paint: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        paint(context)
        return context.makeImage()!
    }

    func filled(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGImage {
        image { context in
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }
    }

    let whole = CGRect(x: 0, y: 0, width: 40, height: 40)

    @Test func whiteIsOneAndBlackIsZero() throws {
        #expect(abs(try #require(Luminance.mean(of: filled(1, 1, 1), in: whole)) - 1) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: filled(0, 0, 0), in: whole))) < 0.01)
    }

    @Test func greenWeighsMostAsInRec709() throws {
        #expect(abs(try #require(Luminance.mean(of: filled(0, 1, 0), in: whole)) - 0.7152) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: filled(0, 0, 1), in: whole)) - 0.0722) < 0.01)
    }

    /// Top half white in the image means the first 20 rows of `rect` coordinates, which start at the top.
    @Test func rectIsMeasuredFromTheTopLeft() throws {
        let topWhite = image { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 20, width: 40, height: 20))
        }
        #expect(abs(try #require(Luminance.mean(of: topWhite, in: CGRect(x: 0, y: 0, width: 40, height: 20))) - 1) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: topWhite, in: CGRect(x: 0, y: 20, width: 40, height: 20)))) < 0.01)
        #expect(abs(try #require(Luminance.mean(of: topWhite, in: whole)) - 0.5) < 0.02)
    }

    @Test func rectOutsideTheImageIsClippedOrNil() throws {
        // Only the visible 10 by 10 pixels at the top left count.
        #expect(abs(try #require(Luminance.mean(of: filled(1, 1, 1), in: CGRect(x: -30, y: -30, width: 40, height: 40))) - 1) < 0.01)
        #expect(Luminance.mean(of: filled(1, 1, 1), in: CGRect(x: 50, y: 50, width: 10, height: 10)) == nil)
    }

    /// A 2x snapshot samples 48 by 48 pixels; the buffer stays at 32 by 32 at most.
    @Test func largeRectsAreDownsampledToTheSameMean() throws {
        let big = image(width: 400, height: 400) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 400))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 200, y: 0, width: 200, height: 400))
        }
        #expect(abs(try #require(Luminance.mean(of: big, in: CGRect(x: 0, y: 0, width: 400, height: 400))) - 0.5) < 0.03)
    }

    @Test func crosshairStyleThresholds() {
        #expect(CrosshairStyle(luminance: nil) == .outlined)
        #expect(CrosshairStyle(luminance: 0.51) == .dark)
        #expect(CrosshairStyle(luminance: 1) == .dark)
        #expect(CrosshairStyle(luminance: 0.5) == .light)
        #expect(CrosshairStyle(luminance: 0) == .light)
    }
}
