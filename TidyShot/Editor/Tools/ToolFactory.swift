import Foundation

/// The tool object behind each `EditorTool`. The switch is exhaustive with no default, so a new
/// case does not compile until it is wired here. Text's tool only starts typing; the model commits
/// the text when the edit ends.
func makeTool(for tool: EditorTool) -> any CanvasTool {
    switch tool {
    case .select: return SelectTool()
    case .redact, .pixelate, .blur, .rectangle, .ellipse: return RectDragTool(tool: tool)
    case .arrow, .line: return TwoPointTool(tool: tool)
    case .pencil, .highlighter: return PencilTool(tool: tool)
    case .text: return TextTool()
    }
}

extension CanvasEditing {
    /// Ends a creation gesture with one commit named `Add <title>`, then clears the transient and
    /// selects the new shape. The commit runs while the transient still holds the same value, so the
    /// tile cache sees one key throughout and the live tile carries over (spec 2.6, Tiles).
    func commitNewShape(_ shape: Annotation) {
        commit(document.appending(shape), actionName: "Add \(shape.title)", coalescingKey: nil)
        transient = nil
        selection = shape.id
    }
}
