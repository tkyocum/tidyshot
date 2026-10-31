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

    /// A left-button event at `point` in the canvas's own coordinates.
    func mouse(_ type: NSEvent.EventType, at point: CGPoint, in canvas: CanvasView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                           pressure: type == .leftMouseUp ? 0 : 1)!
    }

    func key(_ characters: String, _ keyCode: UInt16, up: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    /// A solid background with a 48 pt margin, no corner radius and no shadow.
    func plainBackground() -> BackgroundStyle {
        BackgroundStyle(fill: .solid(RGBA(red: 1, green: 1, blue: 1, alpha: 1)), padding: 48, cornerRadius: 0, shadow: false)
    }

    /// True when `rect` (image pixels) shows centred in the view's inset box, inside it and touching it on one
    /// axis, within a point (the transform snaps to the backing scale).
    func isFitted(_ rect: CGRect, _ model: EditorModel, _ canvas: CanvasView) -> Bool {
        let shown = model.transform.viewRect(rect)
        let box = canvas.bounds.insetBy(dx: EditorWindowGeometry.inset, dy: EditorWindowGeometry.inset)
        let centred = abs(shown.midX - box.midX) <= 1 && abs(shown.midY - box.midY) <= 1
        let inside = shown.minX >= box.minX - 1 && shown.maxX <= box.maxX + 1
            && shown.minY >= box.minY - 1 && shown.maxY <= box.maxY + 1
        let touches = abs(shown.width - box.width) <= 1 || abs(shown.height - box.height) <= 1
        return centred && inside && touches
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

    /// phase-4b :101. A Space-drag at Fit moves the picture, and the fit no longer follows a resize, as after a
    /// scroll; Fit to View (⌘0) fits again, and the fit follows resizes again.
    @Test func aSpaceDragStopsTheFitOnResizeAndFitToViewBringsItBack() {
        let (canvas, model) = makeCanvas()
        canvas.keyDown(with: key(" ", 49))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100), in: canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 140, y: 120), in: canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 140, y: 120), in: canvas))
        canvas.keyUp(with: key(" ", 49, up: true))

        let after = afterResize(canvas, model)
        #expect(after.shown != after.fit)
        // `afterResize` ends with `fitToView()`, so the fit follows the next resize.
        canvas.setFrameSize(NSSize(width: 420, height: 300))
        let followed = model.transform
        canvas.fitToView()
        #expect(followed == model.transform)
    }

    /// phase-7c :144, phase-7c :157, phase-7c :199. At Fit the whole canvas (the background's margin included) fits
    /// the view and stays fitted while it resizes; actual size is the capture's natural scale; an aspect change
    /// at Fit refits; and with no background the fit is the bare capture's, as a canvas that never had one.
    @Test func theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange() async throws {
        let (canvas, model) = makeCanvas()
        let bare = model.transform
        model.setBackground(plainBackground())
        try await eventually { model.transform != bare }
        let shown = try #require(model.shownBackground)
        #expect(isFitted(shown.canvasRect, model, canvas))
        #expect(model.transform.zoom < bare.zoom)

        canvas.setFrameSize(NSSize(width: 420, height: 300))
        #expect(isFitted(shown.canvasRect, model, canvas))

        canvas.zoom(to: 1 / model.scale)
        #expect(abs(model.transform.zoom - 1 / model.scale) < 0.0001)

        canvas.fitToView()
        let before = model.transform
        var style = try #require(model.document.background)
        style.aspect = .square
        model.backgroundDraft = style
        model.commitBackgroundDraft()
        try await eventually { model.transform != before }
        let square = try #require(model.shownBackground)
        #expect(square.canvasRect.width == square.canvasRect.height)
        #expect(isFitted(square.canvasRect, model, canvas))

        model.setBackground(nil)
        let (fresh, freshModel) = makeCanvas()
        fresh.setFrameSize(NSSize(width: 420, height: 300))
        try await eventually { model.transform == freshModel.transform }
        #expect(model.shownBackground == nil)
    }

    /// phase-7c :156. With a background on, a Rectangle dragged from where the capture's corner is drawn starts at
    /// pixel (0, 0), not offset by the margin, so annotations land where the pointer is.
    @Test func aPointerOnTheCaptureMapsToItsPixelWithABackground() async throws {
        let (canvas, model) = makeCanvas()
        let bare = model.transform
        model.setBackground(plainBackground())
        try await eventually { model.transform != bare }
        canvas.keyDown(with: key("r", 15))
        let shown = try #require(model.shownBackground)
        let corner = model.transform.viewPoint(.zero)
        // The capture is drawn inside the canvas, by the margin.
        #expect(corner.x - model.transform.viewRect(shown.canvasRect).minX > 1)

        let end = model.transform.viewPoint(CGPoint(x: 200, y: 100))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: corner, in: canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, in: canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, in: canvas))

        guard case .rectangle(let drawn)? = model.document.annotations.last else {
            Issue.record("no rectangle")
            return
        }
        #expect(abs(drawn.rect.minX) < 0.01)
        #expect(abs(drawn.rect.minY) < 0.01)
        #expect(abs(drawn.rect.maxX - 200) < 0.01)
    }
}
