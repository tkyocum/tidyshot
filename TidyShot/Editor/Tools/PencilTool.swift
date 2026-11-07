import AppKit

/// Pencil and Highlighter: a freehand stroke. Every pointer sample is kept in `raw`; after each
/// event the stroke in `canvas.transient` is rebuilt from `StrokeSmoothing.decimated(raw, ...)`, so
/// the same samples always give the same points, and the last point is always the pointer. The
/// spacing is `spacingPoints / zoom` image pixels. The model keeps the transient's id across
/// rebuilds. A stroke whose points all lie within the tiny-drag distance of the first leaves
/// nothing. Modifier keys change nothing, so flagsChanged finds the same points and does nothing.
/// Recomputing from `raw` is quadratic in the samples of one stroke, which stays far below a
/// millisecond for a stroke of a few thousand.
final class PencilTool: DragShapeTool<[CGPoint]> {
    /// Every sample of the gesture in image pixels; empty when none runs.
    private var raw: [CGPoint] = []

    override func began(at point: CGPoint) {
        raw = [point]
    }

    override func moved(to point: CGPoint) {
        raw.append(point)
    }

    override func key(from start: CGPoint, to current: CGPoint, input: ToolInput, on canvas: any CanvasEditing) -> [CGPoint] {
        StrokeSmoothing.decimated(raw, minDistance: StrokeSmoothing.spacingPoints / canvas.zoom)
    }

    override func shape(for points: [CGPoint], on canvas: any CanvasEditing) -> Annotation? {
        guard isLongEnough(points, zoom: canvas.zoom) else { return nil }
        return canvas.makeStroke(tool, points: points)
    }

    /// Some point at least the tiny-drag distance from the first, so a loop that returns to its
    /// start still counts.
    private func isLongEnough(_ points: [CGPoint], zoom: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        return points.dropFirst().contains { DragGeometry.isLongEnough(from: first, to: $0, zoom: zoom) }
    }
}
