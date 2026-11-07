import AppKit

/// Drags out a rect for Redact, Pixelate, Blur, Rectangle and Ellipse. Shift squares the
/// rect, and Option grows it from the press point as the centre. Both are read from every event,
/// flagsChanged included. A rect that fails `DragGeometry.isLargeEnough` at the current zoom
/// leaves nothing.
final class RectDragTool: DragShapeTool<CGRect> {
    override func key(from start: CGPoint, to current: CGPoint, input: ToolInput, on canvas: any CanvasEditing) -> CGRect {
        DragGeometry.rect(from: start, to: current, square: input.shift, fromCentre: input.option)
    }

    override func shape(for rect: CGRect, on canvas: any CanvasEditing) -> Annotation? {
        guard DragGeometry.isLargeEnough(rect, zoom: canvas.zoom) else { return nil }
        return canvas.makeAnnotation(tool, from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
    }
}
