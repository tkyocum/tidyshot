import AppKit

/// Pencil and Highlighter: a freehand stroke. Every pointer sample is kept in `raw`; after each
/// event the stroke in `canvas.transient` is rebuilt from `StrokeSmoothing.decimated(raw, ...)`, so
/// the same samples always give the same points, and the last point is always the pointer. The
/// spacing is `spacingPoints / zoom` image pixels. The model keeps the transient's id across
/// rebuilds. mouseUp commits once through `commitNewShape` and selects the stroke. A stroke whose
/// points all lie within the tiny-drag distance of the first leaves nothing, and Escape (which
/// clears `canvas.transient`) ends the gesture, as in the other creation tools. Modifier keys do
/// nothing. Recomputing from `raw` is quadratic in the samples of one stroke, which stays far
/// below a millisecond for a stroke of a few thousand.
final class PencilTool: CanvasTool {
    let tool: EditorTool
    /// Every sample of the gesture in image pixels; empty when none runs.
    private var raw: [CGPoint] = []
    private var isDrawing = false
    /// The points behind `shown`, so an event that changes nothing keeps the same annotation.
    private var shownPoints: [CGPoint]?
    /// What this tool last put in `canvas.transient`. Anything else there means the gesture was
    /// cancelled, and the tool drops it.
    private var shown: Annotation?

    init(tool: EditorTool) {
        self.tool = tool
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        raw = [input.point]
        isDrawing = true
        shownPoints = nil
        shown = nil
        canvas.transient = nil
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard isDrawing else { return }
        raw.append(input.point)
        update(on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard isDrawing else { return }
        raw.append(input.point)
        update(on: canvas)
        let stroke = shown
        reset()
        if let stroke {
            canvas.commitNewShape(stroke)
        }
    }

    private func update(on canvas: any CanvasEditing) {
        guard canvas.transient == shown else {
            reset()
            return
        }
        let points = StrokeSmoothing.decimated(raw, minDistance: StrokeSmoothing.spacingPoints / canvas.zoom)
        guard points != shownPoints else { return }
        shownPoints = points
        shown = isLongEnough(points, zoom: canvas.zoom) ? canvas.makeStroke(tool, points: points) : nil
        canvas.transient = shown
    }

    /// Some point at least the tiny-drag distance from the first, so a loop that returns to its
    /// start still counts.
    private func isLongEnough(_ points: [CGPoint], zoom: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        return points.dropFirst().contains { DragGeometry.isLongEnough(from: first, to: $0, zoom: zoom) }
    }

    private func reset() {
        raw = []
        isDrawing = false
        shownPoints = nil
        shown = nil
    }
}
