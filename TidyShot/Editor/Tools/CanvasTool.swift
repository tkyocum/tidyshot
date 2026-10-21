import AppKit

/// One pointer event for a tool: the point in image pixels (top-left origin) and the modifiers
/// that change a shape. `flagsChanged` repeats the last point with the new modifiers.
nonisolated struct ToolInput: Equatable, Sendable {
    var point: CGPoint
    var shift = false
    var option = false
    var clickCount = 1
}

/// What a tool may read and change. `EditorModel` adopts it; CanvasToolTests fake it.
///
/// - `commit` is the only write. A tool calls it once per completed gesture, on mouseUp, while
///   `transient` still holds the shape. A commit whose document contains the transient's id
///   clears `transient` itself, so an effect's tile carries over instead of rendering again.
/// - `makeAnnotation` builds the shape for a drag between two image points with the current
///   colours and sizes. It reuses the transient's id, so one drag keeps one id, and returns nil
///   for Select, an empty rect and a zero-length arrow.
/// - A nil `transient` at mouseUp means Escape abandoned the drag; the tool commits nothing.
protocol CanvasEditing: AnyObject {
    var document: AnnotationDocument { get }
    /// View points per image pixel.
    var zoom: CGFloat { get }
    /// The capture's backing scale: image pixels per point.
    var scale: CGFloat { get }
    /// The shape in progress. Never undoable.
    var transient: Annotation? { get set }
    var selection: UUID? { get set }
    func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String?)
    func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation?
    /// Builds the freehand stroke for Pencil or Highlighter from the decimated points with the
    /// current colour and width, reusing the transient's id. Nil for fewer than two points and for
    /// any other tool.
    func makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation?
}

/// Turns pointer events into a transient shape and one commit per gesture. `makeTool(for:)` in
/// ToolFactory.swift (Task 9) creates the tools.
protocol CanvasTool: AnyObject {
    var cursor: NSCursor { get }
    func mouseDown(_ input: ToolInput, on editing: any CanvasEditing)
    func mouseDragged(_ input: ToolInput, on editing: any CanvasEditing)
    func mouseUp(_ input: ToolInput, on editing: any CanvasEditing)
    /// Shift or Option changed without the mouse moving: re-apply them to the drag in progress.
    func flagsChanged(_ input: ToolInput, on editing: any CanvasEditing)
}
