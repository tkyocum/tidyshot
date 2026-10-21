import AppKit

/// Crop (C). Edits `canvas.cropDraft`, which the model sets to the applied crop, or the whole
/// capture, when the tool is picked. A press on one of the draft's eight handles resizes it (Shift
/// squares a corner), a press inside moves it (Shift keeps the dominant axis), and a press outside
/// drags out a new rect (Shift squares, Option grows it from the press point). Every rect stays
/// inside the image. The tool never commits: Return applies the draft as one undo step
/// (`EditorModel.applyCrop()`), Escape drops it, and picking another tool applies it.
final class CropTool: CanvasTool {
    private enum Gesture {
        /// `from` is where the handle sat at the press, so the handle keeps the grab offset.
        case resize(original: CGRect, handle: Int, from: CGPoint)
        case move(original: CGRect)
        /// A new rect from the press point; `original` stays until the new rect is large enough.
        case draw(original: CGRect)
    }

    private var gesture: Gesture?
    private var start = CGPoint.zero
    private var current = CGPoint.zero
    /// True once the pointer has travelled 2/zoom px, so a click changes nothing.
    private var hasMoved = false
    /// What this tool last put in `canvas.cropDraft`, or the draft at the press. Anything else
    /// there means Escape ended cropping, and the tool drops the gesture.
    private var shown: CGRect?

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        gesture = nil
        hasMoved = false
        start = input.point
        current = input.point
        shown = canvas.cropDraft
        guard let draft = canvas.cropDraft else { return }
        if let handle = CropGeometry.handle(of: draft, at: input.point, tolerance: HitTester.tolerance(zoom: canvas.zoom)) {
            gesture = .resize(original: draft, handle: handle, from: HitTester.boxHandles(draft)[handle])
        } else if draft.contains(input.point) {
            gesture = .move(original: draft)
        } else {
            gesture = .draw(original: draft)
        }
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {
        update(input, on: canvas)
    }

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
        gesture = nil
        shown = nil
        hasMoved = false
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let gesture else { return }
        guard canvas.cropDraft == shown else {
            self.gesture = nil
            shown = nil
            return
        }
        if !hasMoved {
            guard DragGeometry.isLongEnough(from: start, to: current, zoom: canvas.zoom) else { return }
            hasMoved = true
        }
        let size = canvas.imageSize
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let next: CGRect
        switch gesture {
        case .resize(let original, let handle, let from):
            let to = CGPoint(x: from.x + delta.dx, y: from.y + delta.dy)
            next = CropGeometry.clamped(HitTester.resizedRect(original, handle: handle, to: to, square: input.shift), to: size)
        case .move(let original):
            next = CropGeometry.moved(original, by: input.shift ? DragGeometry.axisLocked(delta) : delta, within: size)
        case .draw(let original):
            let drawn = CropGeometry.clamped(DragGeometry.rect(from: start, to: current, square: input.shift,
                                                               fromCentre: input.option), to: size)
            next = DragGeometry.isLargeEnough(drawn, zoom: canvas.zoom) ? drawn : original
        }
        // A handle dragged wholly off the image leaves nothing to keep: the last rect stays.
        guard DragGeometry.isLargeEnough(next, zoom: canvas.zoom), next != shown else { return }
        shown = next
        canvas.cropDraft = next
    }
}
