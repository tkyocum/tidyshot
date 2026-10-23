import AppKit

/// Counter (N). A press puts a new counter in `canvas.transient` at once: the next number, centred
/// on the press and clamped inside the image or the applied crop (`makeAnnotation`). Dragging moves
/// nothing. mouseUp commits it as one `Add Counter` at the press, however far the pointer went, and
/// selects it, but only while `transient` still holds it: Escape during the press clears it, and
/// nothing is placed.
final class CounterTool: CanvasTool {
    /// What this tool put in `canvas.transient` at the press; nil when no gesture runs.
    private var shown: Annotation?

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        // A fresh id: `makeAnnotation` reuses the transient's.
        canvas.transient = nil
        shown = canvas.makeAnnotation(.counter, from: input.point, to: input.point)
        canvas.transient = shown
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        let placed = shown
        shown = nil
        guard let placed, canvas.transient == placed else { return }
        canvas.commitNewShape(placed)
    }
}
