import CoreGraphics
import Testing
@testable import TidyShot

struct WindowShadowTests {
    let frame = CGRect(x: 100, y: 80, width: 800, height: 600)
    let withShadow = CGRect(x: 60, y: 50, width: 880, height: 680)

    /// Shadow off: today's size, from the window's frame and the display's scale.
    @Test func withoutTheShadowTheSizeComesFromTheFrame() {
        let size = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 2,
                                                 displayScale: 2, includeShadow: false)
        #expect(size.width == 1600)
        #expect(size.height == 1200)
    }

    /// Shadow on: the filter's content rect times its point-pixel scale, rounded like
    /// `Geometry.pixelSize` rounds (half away from zero).
    @Test func withTheShadowTheSizeComesFromTheFilter() {
        let size = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 2,
                                                 displayScale: 2, includeShadow: true)
        #expect(size.width == 1760)
        #expect(size.height == 1360)
        let odd = CaptureEngine.windowPixelSize(frame: frame, contentRect: CGRect(x: 0, y: 0, width: 880.25, height: 680),
                                                pointPixelScale: 2, displayScale: 2, includeShadow: true)
        #expect(odd.width == 1761)
        let other = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 1.5,
                                                  displayScale: 2, includeShadow: true)
        #expect(other.width == 1320)
        #expect(other.height == 1020)
    }

    /// A filter that reports nothing useful must not produce a zero-sized capture.
    @Test func aDegenerateFilterFallsBackToTheFrame() {
        let empty = CaptureEngine.windowPixelSize(frame: frame, contentRect: .zero, pointPixelScale: 2,
                                                  displayScale: 2, includeShadow: true)
        #expect(empty.width == 1600)
        #expect(empty.height == 1200)
        let noScale = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 0,
                                                    displayScale: 2, includeShadow: true)
        #expect(noScale.width == 1600)
        #expect(noScale.height == 1200)
    }

    /// A content rect smaller than the frame cannot be the shadowed window; keep the frame.
    @Test func aContentRectSmallerThanTheFrameFallsBackToTheFrame() {
        let size = CaptureEngine.windowPixelSize(frame: frame, contentRect: CGRect(x: 100, y: 80, width: 700, height: 600),
                                                 pointPixelScale: 2, displayScale: 2, includeShadow: true)
        #expect(size.width == 1600)
        #expect(size.height == 1200)
    }
}
