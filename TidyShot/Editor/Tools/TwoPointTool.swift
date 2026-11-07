import AppKit

/// Arrow and Line: the tail at the press, the head at the pointer. Shift snaps the head to the
/// nearest 45 degrees, including through flagsChanged. Option has no effect in 4a. A segment
/// shorter than the tiny-drag rule leaves nothing.
final class TwoPointTool: DragShapeTool<CGPoint> {
    override func key(from start: CGPoint, to current: CGPoint, input: ToolInput, on canvas: any CanvasEditing) -> CGPoint {
        DragGeometry.segmentEnd(from: start, to: current, snap45: input.shift)
    }

    override func shape(for end: CGPoint, on canvas: any CanvasEditing) -> Annotation? {
        guard let start = tail, DragGeometry.isLongEnough(from: start, to: end, zoom: canvas.zoom) else { return nil }
        return canvas.makeAnnotation(tool, from: start, to: end)
    }

    /// The tail, which the shape needs beside the head.
    private var tail: CGPoint?

    override func began(at point: CGPoint) {
        tail = point
    }
}
