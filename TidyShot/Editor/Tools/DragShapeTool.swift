import AppKit

/// The drag that makes one shape, shared by the rect, two-point and freehand tools. The press
/// starts the gesture; every drag and modifier change derives a `Key` from it and rebuilds the
/// shape in `canvas.transient` only when the key changed, so an event that changes nothing keeps
/// the same annotation, id included, and its tile is not rendered again. Anything else in
/// `canvas.transient` means Escape cancelled the gesture, and the tool drops it. mouseUp commits
/// once through `commitNewShape` and selects the shape; a shape too small to keep is nil and
/// commits nothing. A subclass gives the key and the shape, and may keep more of the gesture in
/// `began(at:)` and `moved(to:)`.
class DragShapeTool<Key: Equatable>: CanvasTool {
    let tool: EditorTool
    /// The press point in image pixels; nil when no gesture runs.
    private var start: CGPoint?
    /// The latest pointer position. flagsChanged reuses it, because the pointer has not moved.
    private var current = CGPoint.zero
    /// The key behind `shown`.
    private var shownKey: Key?
    /// What this tool last put in `canvas.transient`.
    private var shown: Annotation?

    init(tool: EditorTool) {
        self.tool = tool
    }

    var cursor: NSCursor { .crosshair }

    /// What the shape depends on, from the press at `start`, the pointer at `current` and the
    /// modifiers in `input`.
    func key(from start: CGPoint, to current: CGPoint, input: ToolInput, on canvas: any CanvasEditing) -> Key {
        fatalError("\(type(of: self)) gives the key")
    }

    /// The shape for `key`, or nil when it is too small to keep.
    func shape(for key: Key, on canvas: any CanvasEditing) -> Annotation? {
        fatalError("\(type(of: self)) gives the shape")
    }

    /// A gesture began with a press at `point`.
    func began(at point: CGPoint) {}

    /// The pointer moved to `point` during the gesture, or was released there.
    func moved(to point: CGPoint) {}

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        start = input.point
        current = input.point
        shownKey = nil
        shown = nil
        began(at: input.point)
        canvas.transient = nil
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard start != nil else { return }
        current = input.point
        moved(to: input.point)
        update(input, on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {
        update(input, on: canvas)
    }

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard start != nil else { return }
        current = input.point
        moved(to: input.point)
        update(input, on: canvas)
        // `update` ended the gesture when it found it cancelled, and then there is no shape.
        let completed = start == nil ? nil : shown
        end()
        if let completed {
            canvas.commitNewShape(completed)
        }
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let start else { return }
        guard canvas.transient == shown else {
            end()
            return
        }
        let key = key(from: start, to: current, input: input, on: canvas)
        guard key != shownKey else { return }
        shownKey = key
        shown = shape(for: key, on: canvas)
        canvas.transient = shown
    }

    private func end() {
        start = nil
        shownKey = nil
        shown = nil
    }
}
