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
/// - `beginTextEditing` hands typing to the canvas; the edit commits when it ends, not on mouseUp.
protocol CanvasEditing: AnyObject {
    var document: AnnotationDocument { get }
    /// View points per image pixel.
    var zoom: CGFloat { get }
    /// The capture's backing scale: image pixels per point.
    var scale: CGFloat { get }
    /// The shape in progress. Never undoable.
    var transient: Annotation? { get set }
    var selection: UUID? { get set }
    /// The Crop tool's rect while cropping (4b), in image pixels; nil otherwise. Never undoable:
    /// Return applies it as one commit, Escape drops it.
    var cropDraft: CGRect? { get set }
    /// The capture's size in image pixels.
    var imageSize: CGSize { get }
    func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String?)
    func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation?
    /// Builds the freehand stroke for Pencil or Highlighter from the decimated points with the
    /// current colour and width, reusing the transient's id. Nil for fewer than two points and for
    /// any other tool.
    func makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation?
    /// Starts typing a text annotation: `existing` again, or a new box at `point` (4b).
    func beginTextEditing(at point: CGPoint, existing id: UUID?)
}

/// Turns pointer events into a transient shape and one commit per gesture; `makeTool(for:)` below
/// creates the tools.
protocol CanvasTool: AnyObject {
    var cursor: NSCursor { get }
    func mouseDown(_ input: ToolInput, on editing: any CanvasEditing)
    func mouseDragged(_ input: ToolInput, on editing: any CanvasEditing)
    func mouseUp(_ input: ToolInput, on editing: any CanvasEditing)
    /// Shift or Option changed without the mouse moving: re-apply them to the drag in progress.
    func flagsChanged(_ input: ToolInput, on editing: any CanvasEditing)
}

/// The tool object behind each `EditorTool`. The switch is exhaustive with no default, so a new
/// case does not compile until it is wired here. Text's tool only starts typing; the model commits
/// the text when the edit ends.
func makeTool(for tool: EditorTool) -> any CanvasTool {
    switch tool {
    case .select: return SelectTool()
    case .redact, .pixelate, .blur, .spotlight, .rectangle, .ellipse: return RectDragTool(tool: tool)
    case .arrow, .line: return TwoPointTool(tool: tool)
    case .pencil, .highlighter: return PencilTool(tool: tool)
    case .text: return TextTool()
    case .counter: return CounterTool()
    case .crop: return CropTool()
    }
}

extension CanvasEditing {
    /// Ends a gesture that adds `shape` with one commit, named `actionName` or else `Add <title>`,
    /// then clears the transient and selects the new shape. The commit runs while the transient
    /// still holds the same value, so the tile cache sees one key throughout and the live tile
    /// carries over (spec 2.6, Tiles). ⌥-drag, ⌘D and ⌘V use it too, so every new counter is
    /// numbered here (`renumbered(in:)`, spec 2.12), and a number is never repeated; the id, and so
    /// the selection, is unchanged.
    func commitNewShape(_ shape: Annotation, actionName: String? = nil) {
        let shape = shape.renumbered(in: document)
        commit(document.appending(shape), actionName: actionName ?? "Add \(shape.title)", coalescingKey: nil)
        transient = nil
        selection = shape.id
    }
}
