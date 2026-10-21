import CoreGraphics
import Testing
@testable import TidyShot

struct CanvasTransformTests {
    func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    /// viewPoint and imagePoint invert each other, as do viewRect and imageRect; `affine` maps
    /// like viewPoint; a pan moves every view point by its delta.
    @Test func pointAndRectRoundTrip() {
        let odd = CanvasTransform(zoom: 0.37, offset: CGPoint(x: 13.5, y: -42.25))
        let point = CGPoint(x: 123.4, y: 56.7)
        #expect(close(odd.imagePoint(odd.viewPoint(point)), point))
        #expect(close(point.applying(odd.affine), odd.viewPoint(point)))

        let half = CanvasTransform(zoom: 0.5, offset: CGPoint(x: 24, y: 10))
        #expect(half.viewPoint(CGPoint(x: 100, y: 40)) == CGPoint(x: 74, y: 30))
        let rect = CGRect(x: 10, y: 20, width: 64, height: 48)
        #expect(half.viewRect(rect) == CGRect(x: 29, y: 20, width: 32, height: 24))
        #expect(half.imageRect(half.viewRect(rect)) == rect)
        #expect(rect.applying(half.affine) == half.viewRect(rect))
        #expect(half.panned(by: CGPoint(x: 5, y: -3)).viewPoint(CGPoint(x: 100, y: 40)) == CGPoint(x: 79, y: 27))
    }

    /// A capture smaller than the window opens at 100 %, however much room there is.
    @Test func fittingNeverExceedsNaturalSize() {
        let small = CGSize(width: 200, height: 100)
        let view = CGSize(width: 1200, height: 800)
        let retina = CanvasTransform.fitting(imagePixelSize: small, in: view, inset: 24, captureScale: 2)
        #expect(retina.zoom == 0.5)
        #expect(retina.percent(captureScale: 2) == 100)
        #expect(CanvasTransform.fitting(imagePixelSize: small, in: view, inset: 24, captureScale: 1).zoom == 1)
    }

    /// A capture larger than the window shrinks into the room inside the inset, limited by the
    /// tighter side, and its centre lands on the view's centre.
    @Test func fittingCentres() {
        let view = CGSize(width: 1048, height: 548)
        #expect(CanvasTransform.fitting(imagePixelSize: CGSize(width: 4000, height: 2000), in: view, inset: 24, captureScale: 2)
                == CanvasTransform(zoom: 0.25, offset: CGPoint(x: 24, y: 24)))
        let wide = CanvasTransform.fitting(imagePixelSize: CGSize(width: 4000, height: 1000), in: view, inset: 24, captureScale: 2)
        #expect(wide == CanvasTransform(zoom: 0.25, offset: CGPoint(x: 24, y: 149)))
        #expect(wide.viewPoint(CGPoint(x: 2000, y: 500)) == CGPoint(x: 524, y: 274))
        #expect(CanvasTransform.fitting(imagePixelSize: CGSize(width: 1000, height: 4000), in: view, inset: 24, captureScale: 2)
                == CanvasTransform(zoom: 0.125, offset: CGPoint(x: 461.5, y: 24)))
    }

    /// The image pixel under the anchor stays under it, zooming in and back out.
    @Test func zoomedKeepsAnchorFixed() {
        let limits = CanvasTransform.zoomLimits(captureScale: 2)
        let start = CanvasTransform(zoom: 0.5, offset: CGPoint(x: 30, y: 40))
        let anchor = CGPoint(x: 230, y: 140)
        #expect(start.imagePoint(anchor) == CGPoint(x: 400, y: 200))
        let zoomedIn = start.zoomed(by: 1.25, around: anchor, limits: limits)
        #expect(zoomedIn == CanvasTransform(zoom: 0.625, offset: CGPoint(x: -20, y: 15)))
        #expect(zoomedIn.viewPoint(CGPoint(x: 400, y: 200)) == anchor)
        let back = zoomedIn.zoomed(by: 0.8, around: anchor, limits: limits)
        #expect(abs(back.zoom - 0.5) < 1e-12)
        #expect(close(back.imagePoint(anchor), CGPoint(x: 400, y: 200)))
    }

    /// 10 % to 800 % of the natural size. A clamped zoom still keeps the anchor fixed, and a zoom
    /// that starts below the limit (a fitted, very tall capture) never jumps against the gesture.
    @Test func zoomClampsToLimits() {
        let limits = CanvasTransform.zoomLimits(captureScale: 2)
        #expect(limits == 0.05...4)
        #expect(CanvasTransform.zoomLimits(captureScale: 1) == 0.1...8)
        let start = CanvasTransform(zoom: 0.5, offset: .zero)
        let anchor = CGPoint(x: 100, y: 100)
        let most = start.zoomed(by: 100, around: anchor, limits: limits)
        #expect(most.zoom == 4)
        #expect(close(most.imagePoint(anchor), start.imagePoint(anchor)))
        #expect(start.zoomed(by: 0.001, around: anchor, limits: limits).zoom == 0.05)

        let tiny = CanvasTransform(zoom: 1.0 / 64, offset: CGPoint(x: 7, y: 9))
        #expect(tiny.zoomed(by: 0.8, around: anchor, limits: limits) == tiny)
        #expect(tiny.zoomed(by: 1.25, around: anchor, limits: limits).zoom == 1.25 / 64)
    }

    @Test func snappedOffsetsLandOnDevicePixels() {
        let transform = CanvasTransform(zoom: 0.3, offset: CGPoint(x: 10.3, y: 7.76))
        #expect(transform.snapped(toBackingScale: 2) == CanvasTransform(zoom: 0.3, offset: CGPoint(x: 10.5, y: 8)))
        #expect(transform.snapped(toBackingScale: 1) == CanvasTransform(zoom: 0.3, offset: CGPoint(x: 10, y: 8)))
        // Zoomed in, the offset is negative; it snaps the same way.
        let negative = CanvasTransform(zoom: 2, offset: CGPoint(x: -3.3, y: -0.2))
        #expect(negative.snapped(toBackingScale: 2) == CanvasTransform(zoom: 2, offset: CGPoint(x: -3.5, y: 0)))
    }

    /// 100 % is the natural point size: one image pixel per `1 / captureScale` points.
    @Test func percentIsRelativeToNaturalSize() {
        #expect(CanvasTransform(zoom: 0.5, offset: .zero).percent(captureScale: 2) == 100)
        #expect(CanvasTransform(zoom: 1, offset: .zero).percent(captureScale: 2) == 200)
        #expect(CanvasTransform(zoom: 1, offset: .zero).percent(captureScale: 1) == 100)
        #expect(CanvasTransform(zoom: 1.0 / 3, offset: .zero).percent(captureScale: 1) == 33)
        #expect(CanvasTransform(zoom: 0.25 * 0.8, offset: .zero).percent(captureScale: 2) == 40)
        let limits = CanvasTransform.zoomLimits(captureScale: 2)
        #expect(CanvasTransform(zoom: limits.lowerBound, offset: .zero).percent(captureScale: 2) == 10)
        #expect(CanvasTransform(zoom: limits.upperBound, offset: .zero).percent(captureScale: 2) == 800)
    }
}
