import AppKit
import CoreGraphics
import Testing
@testable import TidyShot

/// The fit keeps following window resizes until the user pans or zooms. A scroll event that moves
/// nothing (a trackpad's may-begin, began and ended phases) is not a pan.
struct CanvasFitTests {
    /// A canvas over an 800x600 capture at scale 2, fitted into 300x200 points.
    func makeCanvas() -> (canvas: CanvasView, model: EditorModel) {
        let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let model = EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: 2),
                                renderer: FakeTileRenderer(), defaults: .standard)
        let canvas = CanvasView(model: model, baseView: BaseImageView(frame: .zero))
        canvas.setFrameSize(NSSize(width: 300, height: 200))
        return (canvas, model)
    }

    /// A pixel-unit scroll event with these deltas.
    func scroll(x: Int32, y: Int32) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: y, wheel2: x, wheel3: 0)!
        return NSEvent(cgEvent: event)!
    }

    /// The transform the canvas shows after a resize to 360x260, and the fit at that size.
    func afterResize(_ canvas: CanvasView, _ model: EditorModel) -> (shown: CanvasTransform, fit: CanvasTransform) {
        canvas.setFrameSize(NSSize(width: 360, height: 260))
        let shown = model.transform
        canvas.fitToView()
        return (shown, model.transform)
    }

    @Test func zeroDeltaScrollKeepsTheFitOnResize() {
        let (canvas, model) = makeCanvas()
        let fitted = model.transform
        canvas.scrollWheel(with: scroll(x: 0, y: 0))
        #expect(model.transform == fitted)
        let after = afterResize(canvas, model)
        #expect(after.shown == after.fit)
    }

    @Test func panStopsTheFitOnResize() {
        let (canvas, model) = makeCanvas()
        canvas.scrollWheel(with: scroll(x: 0, y: 12))
        let after = afterResize(canvas, model)
        #expect(after.shown != after.fit)
    }
}
