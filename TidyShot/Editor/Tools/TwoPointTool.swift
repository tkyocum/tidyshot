import AppKit

/// Arrow (4b adds Line): the tail at the press, the head at the pointer. Shift snaps the head to the
/// nearest 45 degrees, including through flagsChanged. Option has no effect in 4a. A segment
/// shorter than the tiny-drag rule leaves nothing.
final class TwoPointTool: CanvasTool {
    let tool: EditorTool
    /// The tail in image pixels; nil when no gesture runs.
    private var start: CGPoint?
    /// The latest pointer position. flagsChanged reuses it.
    private var current = CGPoint.zero
    /// The head behind `shown`, so an unchanged head keeps the same annotation and id.
    private var shownEnd: CGPoint?
    /// What this tool last put in `canvas.transient`. Anything else there means the gesture was
    /// cancelled.
    private var shown: Annotation?

    init(tool: EditorTool) {
        self.tool = tool
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        start = input.point
        current = input.point
        shownEnd = nil
        shown = nil
        canvas.transient = nil
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
        let shape = start == nil ? nil : shown
        start = nil
        shownEnd = nil
        shown = nil
        if let shape {
            canvas.commitNewShape(shape)
        }
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let start else { return }
        guard canvas.transient == shown else {
            self.start = nil
            shownEnd = nil
            shown = nil
            return
        }
        let end = DragGeometry.segmentEnd(from: start, to: current, snap45: input.shift)
        guard end != shownEnd else { return }
        shownEnd = end
        shown = DragGeometry.isLongEnough(from: start, to: end, zoom: canvas.zoom)
            ? canvas.makeAnnotation(tool, from: start, to: end)
            : nil
        canvas.transient = shown
    }
}
