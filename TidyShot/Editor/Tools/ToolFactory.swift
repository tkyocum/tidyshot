import Foundation

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
    // Places nothing until Task 3's CounterTool: `makeAnnotation` returns nil for it.
    case .counter: return RectDragTool(tool: tool)
    case .crop: return CropTool()
    }
}

extension CanvasEditing {
    /// Ends a gesture that adds `shape` with one commit, named `actionName` or else `Add <title>`,
    /// then clears the transient and selects the new shape. The commit runs while the transient
    /// still holds the same value, so the tile cache sees one key throughout and the live tile
    /// carries over (spec 2.6, Tiles). ⌥-drag, ⌘D and ⌘V use it too.
    func commitNewShape(_ shape: Annotation, actionName: String? = nil) {
        commit(document.appending(shape), actionName: actionName ?? "Add \(shape.title)", coalescingKey: nil)
        transient = nil
        selection = shape.id
    }
}
