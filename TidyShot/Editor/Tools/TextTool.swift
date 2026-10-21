import AppKit

/// Text (T). A click places a new text box with its first line centred on the pointer, or, on a
/// text annotation, edits that text again. A drag places nothing. The typing happens in
/// CanvasView's NSTextView and `EditorModel.commitTextEditing()` commits it when editing ends, so
/// this tool never commits.
final class TextTool: CanvasTool {
    /// Where the press landed; nil when no gesture runs.
    private var start: CGPoint?

    var cursor: NSCursor { .iBeam }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        start = input.point
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let start else { return }
        self.start = nil
        // The tiny-drag rule, the other way round: only a click places or reopens text.
        guard !DragGeometry.isLongEnough(from: start, to: input.point, zoom: canvas.zoom) else { return }
        let tolerance = HitTester.tolerance(zoom: canvas.zoom)
        if let hit = HitTester.topmost(in: canvas.document, at: start, tolerance: tolerance),
           case .text? = canvas.document.annotation(id: hit.id) {
            canvas.beginTextEditing(at: start, existing: hit.id)
        } else {
            canvas.beginTextEditing(at: start, existing: nil)
        }
    }
}
