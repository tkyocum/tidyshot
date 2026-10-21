import AppKit

/// Select (V). A press first tests the selected annotation's handles, because only the selection
/// shows handles. Otherwise `HitTester.topmost` picks the front-most drawing, then the front-most
/// effect, and that annotation becomes the selection. A hit on another annotation's handle selects
/// and moves it. A press on empty space deselects. A drag moves the selection (Shift keeps the
/// dominant axis) or resizes it by the pressed handle (Shift squares a box). The changed copy lives
/// in `canvas.transient`, with the annotation's own id, until mouseUp commits it once.
final class SelectTool: CanvasTool {
    private enum Gesture {
        case move(original: Annotation)
        /// `from` is where the handle sat at the press, so the handle keeps the grab offset.
        case resize(original: Annotation, handle: Int, from: CGPoint)

        var original: Annotation {
            switch self {
            case .move(let original), .resize(let original, _, _): original
            }
        }

        var verb: String {
            switch self {
            case .move: "Move"
            case .resize: "Resize"
            }
        }
    }

    private var gesture: Gesture?
    private var start = CGPoint.zero
    private var current = CGPoint.zero
    /// What this tool last put in `canvas.transient`. It stays nil until the pointer passes the
    /// tiny-drag rule, so a click changes nothing.
    private var shown: Annotation?

    var cursor: NSCursor { .arrow }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        gesture = nil
        shown = nil
        start = input.point
        current = input.point
        canvas.transient = nil
        let tolerance = HitTester.tolerance(zoom: canvas.zoom)
        if let id = canvas.selection, let selected = canvas.document.annotation(id: id),
           case .handle(let index)? = HitTester.hit(selected, at: input.point, tolerance: tolerance) {
            gesture = .resize(original: selected, handle: index, from: HitTester.handles(for: selected)[index])
            return
        }
        guard let top = HitTester.topmost(in: canvas.document, at: input.point, tolerance: tolerance),
              let annotation = canvas.document.annotation(id: top.id) else {
            canvas.selection = nil
            return
        }
        canvas.selection = annotation.id
        gesture = .move(original: annotation)
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {
        update(input, on: canvas)
    }

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
        let ended = gesture
        let changed = shown
        gesture = nil
        shown = nil
        guard let ended, let changed else { return }
        guard changed != ended.original else {
            canvas.transient = nil
            return
        }
        canvas.commit(canvas.document.replacing(changed), actionName: "\(ended.verb) \(changed.title)",
                      coalescingKey: nil)
        canvas.transient = nil
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let gesture else { return }
        guard canvas.transient == shown else {
            self.gesture = nil
            shown = nil
            return
        }
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        guard shown != nil || DragGeometry.isLongEnough(from: start, to: current, zoom: canvas.zoom) else { return }
        switch gesture {
        case .move(let original):
            shown = original.moved(by: input.shift ? DragGeometry.axisLocked(delta) : delta)
        case .resize(let original, let handle, let from):
            let to = CGPoint(x: from.x + delta.dx, y: from.y + delta.dy)
            shown = HitTester.resized(original, handle: handle, to: to, square: input.shift)
        }
        canvas.transient = shown
    }
}
