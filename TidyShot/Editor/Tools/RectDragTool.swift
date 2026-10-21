import AppKit

/// Drags out a rect for Redact, Pixelate, Blur and Rectangle (4b adds Ellipse). Shift squares the
/// rect, and Option grows it from the press point as the centre. Both are read from every event,
/// flagsChanged included. The shape lives in `canvas.transient` until mouseUp commits it once and
/// selects it. A rect that fails `DragGeometry.isLargeEnough` at the current zoom leaves nothing.
final class RectDragTool: CanvasTool {
    let tool: EditorTool
    /// The press point in image pixels; nil when no gesture runs.
    private var start: CGPoint?
    /// The latest pointer position. flagsChanged reuses it, because the pointer has not moved.
    private var current = CGPoint.zero
    /// The rect behind `shown`. An event that gives the same rect keeps the same annotation, id
    /// included, so its tile is not rendered again.
    private var shownRect: CGRect?
    /// What this tool last put in `canvas.transient`. Anything else there means the gesture was
    /// cancelled, and the tool drops it.
    private var shown: Annotation?

    init(tool: EditorTool) {
        self.tool = tool
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        start = input.point
        current = input.point
        shownRect = nil
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
        shownRect = nil
        shown = nil
        if let shape {
            canvas.commitNewShape(shape)
        }
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let start else { return }
        guard canvas.transient == shown else {
            self.start = nil
            shownRect = nil
            shown = nil
            return
        }
        let rect = DragGeometry.rect(from: start, to: current, square: input.shift, fromCentre: input.option)
        guard rect != shownRect else { return }
        shownRect = rect
        shown = DragGeometry.isLargeEnough(rect, zoom: canvas.zoom)
            ? canvas.makeAnnotation(tool, from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
            : nil
        canvas.transient = shown
    }
}
