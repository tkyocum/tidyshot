import AppKit
import Testing
@testable import TidyShot

/// Stands in for EditorModel. It records commits and builds annotations the way the model does,
/// with fixed colours, widths and effect parameters.
final class FakeCanvasEditing: CanvasEditing {
    struct Commit {
        let document: AnnotationDocument
        let actionName: String
        let coalescingKey: String?
        /// The transient when the commit ran. Tools commit before they clear it.
        let transient: Annotation?
    }

    private(set) var document: AnnotationDocument
    var zoom: CGFloat = 1
    var scale: CGFloat = 2
    var transient: Annotation?
    var selection: UUID?
    var cropDraft: CGRect?
    var imageSize = CGSize(width: 64, height: 48)
    private(set) var commits: [Commit] = []
    private(set) var made: [(tool: EditorTool, from: CGPoint, to: CGPoint)] = []
    /// Each `beginTextEditing` call.
    private(set) var textBegun: [(point: CGPoint, existing: UUID?)] = []
    private(set) var strokes: [(tool: EditorTool, points: [CGPoint])] = []

    init(_ annotations: [Annotation] = []) {
        document = AnnotationDocument(annotations: annotations)
    }

    func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String?) {
        commits.append(Commit(document: new, actionName: actionName, coalescingKey: coalescingKey, transient: transient))
        document = new
    }

    func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation? {
        made.append((tool: tool, from: from, to: to))
        let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y))
        switch tool {
        case .redact: return .redact(Region(id: UUID(), rect: rect), fill: EditorPalette.defaultRedact)
        case .pixelate: return .pixelate(Region(id: UUID(), rect: rect), block: 20)
        case .blur: return .blur(Region(id: UUID(), rect: rect), radius: 16)
        case .rectangle:
            return .rectangle(ShapeBox(id: UUID(), rect: rect, color: EditorPalette.defaultStroke, lineWidth: 8))
        case .arrow:
            return .arrow(Segment(id: UUID(), from: from, to: to, color: EditorPalette.defaultStroke, lineWidth: 8))
        case .ellipse:
            return .ellipse(ShapeBox(id: UUID(), rect: rect, color: EditorPalette.defaultStroke, lineWidth: 8))
        case .line:
            return .line(Segment(id: UUID(), from: from, to: to, color: EditorPalette.defaultStroke, lineWidth: 8))
        default: return nil
        }
    }

    func makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation? {
        strokes.append((tool: tool, points: points))
        guard points.count >= 2 else { return nil }
        let stroke = Stroke(id: transient?.id ?? UUID(), points: points, color: EditorPalette.defaultStroke, lineWidth: 8)
        switch tool {
        case .pencil: return .pencil(stroke)
        case .highlighter: return .highlighter(stroke)
        default: return nil
        }
    }

    func beginTextEditing(at point: CGPoint, existing id: UUID?) {
        textBegun.append((point: point, existing: id))
    }
}

@MainActor
struct CanvasToolTests {
    let red = EditorPalette.defaultStroke

    func at(_ x: CGFloat, _ y: CGFloat, shift: Bool = false, option: Bool = false) -> ToolInput {
        ToolInput(point: CGPoint(x: x, y: y), shift: shift, option: option, clickCount: 1)
    }

    func rect(of annotation: Annotation?) -> CGRect? {
        switch annotation {
        case .rectangle(let box)?, .ellipse(let box)?: box.rect
        case .redact(let region, _)?, .pixelate(let region, _)?, .blur(let region, _)?: region.rect
        default: nil
        }
    }

    func segment(of annotation: Annotation?) -> Segment? {
        switch annotation {
        case .arrow(let segment)?, .line(let segment)?: return segment
        default: return nil
        }
    }

    func stroke(of annotation: Annotation?) -> Stroke? {
        switch annotation {
        case .pencil(let stroke)?, .highlighter(let stroke)?: stroke
        default: nil
        }
    }

    func arrow(_ from: CGPoint, _ to: CGPoint) -> Annotation {
        .arrow(Segment(id: UUID(), from: from, to: to, color: red, lineWidth: 8))
    }

    @Test func transientUpdatesDuringDrag() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .redact)
        #expect(tool is RectDragTool)

        tool.mouseDown(at(10, 10), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseDragged(at(50, 40), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 30))
        #expect(canvas.transient?.isEffect == true)
        #expect(canvas.made.last?.tool == .redact)
        #expect(canvas.made.last?.from == CGPoint(x: 10, y: 10))
        #expect(canvas.made.last?.to == CGPoint(x: 50, y: 40))

        tool.mouseDragged(at(60, 70), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 50, height: 60))

        // An event that gives the same rect keeps the same annotation, id included.
        let shown = try #require(canvas.transient)
        let calls = canvas.made.count
        tool.flagsChanged(at(60, 70), on: canvas)
        #expect(canvas.made.count == calls)
        #expect(canvas.transient == shown)

        // Dragging back past the press point passes the standardized corners.
        tool.mouseDragged(at(0, 5), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 0, y: 5, width: 10, height: 5))
        #expect(canvas.made.last?.from == CGPoint(x: 0, y: 5))
        #expect(canvas.made.last?.to == CGPoint(x: 10, y: 10))

        #expect(canvas.commits.isEmpty)
        #expect(canvas.document.annotations.isEmpty)
    }

    @Test func commitOnMouseUpOnly() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .rectangle)
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(40, 30), on: canvas)
        tool.mouseDragged(at(60, 50), on: canvas)
        let shape = try #require(canvas.transient)
        #expect(canvas.commits.isEmpty)

        tool.mouseUp(at(60, 50), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(commit.document == AnnotationDocument(annotations: [shape]))
        #expect(commit.actionName == "Add \(shape.title)")
        #expect(commit.coalescingKey == nil)
        #expect(commit.transient == shape)
        #expect(canvas.transient == nil)

        // A gesture cancelled mid-drag (Escape clears the transient) is not completed: no commit.
        tool.mouseDown(at(100, 100), on: canvas)
        tool.mouseDragged(at(140, 130), on: canvas)
        canvas.transient = nil
        tool.mouseDragged(at(150, 140), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseUp(at(150, 140), on: canvas)
        #expect(canvas.commits.count == 1)
    }

    @Test func tinyDragDiscarded() {
        let canvas = FakeCanvasEditing()
        let rectangle = makeTool(for: .rectangle)
        // At 100 % the rule is 2 px, so a 1 px wide drag leaves nothing.
        rectangle.mouseDown(at(10, 10), on: canvas)
        rectangle.mouseDragged(at(11, 40), on: canvas)
        #expect(canvas.transient == nil)
        rectangle.mouseUp(at(11, 40), on: canvas)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.selection == nil)

        let arrowTool = makeTool(for: .arrow)
        arrowTool.mouseDown(at(10, 10), on: canvas)
        arrowTool.mouseDragged(at(11, 10.5), on: canvas)
        #expect(canvas.transient == nil)
        arrowTool.mouseUp(at(11, 10.5), on: canvas)
        #expect(canvas.commits.isEmpty)

        // A level arrow has no height and is still kept.
        arrowTool.mouseDown(at(10, 10), on: canvas)
        arrowTool.mouseDragged(at(60, 10), on: canvas)
        arrowTool.mouseUp(at(60, 10), on: canvas)
        #expect(canvas.commits.count == 1)

        // At 400 % the rule is 0.5 px, so the same 1 px drag is kept.
        canvas.zoom = 4
        rectangle.mouseDown(at(10, 10), on: canvas)
        rectangle.mouseDragged(at(11, 40), on: canvas)
        rectangle.mouseUp(at(11, 40), on: canvas)
        #expect(canvas.commits.count == 2)
    }

    /// The stroke grows in `transient` under one id, keeps the pointer as its last point, drops
    /// samples closer than 2 px (at 100 %), and commits once on mouseUp.
    @Test func pencilDragsOneStrokeAndCommitsOnMouseUp() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .pencil)
        #expect(tool is PencilTool)

        tool.mouseDown(at(10, 10), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseDragged(at(20, 14), on: canvas)
        let first = try #require(stroke(of: canvas.transient))
        #expect(first.points == [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 14)])

        tool.mouseDragged(at(30, 18), on: canvas)
        tool.mouseDragged(at(30.5, 18.2), on: canvas)
        let near = try #require(stroke(of: canvas.transient))
        #expect(near.id == first.id)
        #expect(near.points.last == CGPoint(x: 30.5, y: 18.2))

        tool.mouseDragged(at(50, 12), on: canvas)
        #expect(canvas.commits.isEmpty)
        tool.mouseUp(at(50, 12), on: canvas)

        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(commit.actionName == "Add Pencil")
        #expect(commit.coalescingKey == nil)
        let committed = try #require(canvas.document.annotations.last)
        #expect(commit.transient == committed)
        let result = try #require(stroke(of: committed))
        #expect(result.id == first.id)
        #expect(result.points == [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 14), CGPoint(x: 30, y: 18), CGPoint(x: 50, y: 12)])
        #expect(canvas.transient == nil)
        #expect(canvas.selection == committed.id)
        #expect(canvas.strokes.allSatisfy { $0.tool == .pencil })
    }

    /// A click and a 1 px jiggle leave nothing; Escape mid-stroke (the model clears `transient`)
    /// ends the gesture; a real drag with the Highlighter commits `Add Highlighter`.
    @Test func tinyOrCancelledStrokeLeavesNothing() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .highlighter)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseUp(at(10, 10), on: canvas)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.transient == nil)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(11, 10.5), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseUp(at(11, 10.5), on: canvas)
        #expect(canvas.commits.isEmpty)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(40, 10), on: canvas)
        #expect(canvas.transient != nil)
        canvas.transient = nil
        tool.mouseDragged(at(80, 10), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseUp(at(80, 10), on: canvas)
        #expect(canvas.commits.isEmpty)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(60, 10), on: canvas)
        tool.mouseUp(at(60, 10), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(canvas.commits.first?.actionName == "Add Highlighter")
        guard case .highlighter? = canvas.document.annotations.last else {
            Issue.record("no highlighter")
            return
        }
    }

    @Test func shiftViaFlagsChangedSquares() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .rectangle)
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(50, 30), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 20))

        // Shift goes down with the mouse still: the shape squares without a drag event.
        tool.flagsChanged(at(50, 30, shift: true), on: canvas)
        let square = try #require(rect(of: canvas.transient))
        #expect(square == DragGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30),
                                            square: true, fromCentre: false))
        #expect(square.width == square.height)
        #expect(square.origin == CGPoint(x: 10, y: 10))

        tool.flagsChanged(at(50, 30), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 20))

        tool.flagsChanged(at(50, 30, shift: true), on: canvas)
        #expect(canvas.commits.isEmpty)
        tool.mouseUp(at(50, 30, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(rect(of: canvas.document.annotations.last) == square)
    }

    @Test func ellipseShiftMakesCircleAndLineSnapsTo45() throws {
        let canvas = FakeCanvasEditing()
        let ellipse = makeTool(for: .ellipse)
        #expect(ellipse is RectDragTool)
        ellipse.mouseDown(at(10, 10), on: canvas)
        ellipse.mouseDragged(at(50, 30), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 20))
        // Shift goes down with the mouse still: the ellipse becomes a circle.
        ellipse.flagsChanged(at(50, 30, shift: true), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 40))
        ellipse.mouseUp(at(50, 30, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(canvas.commits.first?.actionName == "Add Ellipse")
        #expect(rect(of: canvas.document.annotations.last) == CGRect(x: 10, y: 10, width: 40, height: 40))
        #expect(canvas.selection == canvas.document.annotations.last?.id)

        let line = makeTool(for: .line)
        #expect(line is TwoPointTool)
        line.mouseDown(at(10, 10), on: canvas)
        line.mouseDragged(at(60, 18), on: canvas)
        #expect(segment(of: canvas.transient)?.to == CGPoint(x: 60, y: 18))
        line.flagsChanged(at(60, 18, shift: true), on: canvas)
        #expect(segment(of: canvas.transient)?.from == CGPoint(x: 10, y: 10))
        #expect(segment(of: canvas.transient)?.to == CGPoint(x: 60, y: 10))
        line.mouseUp(at(60, 18, shift: true), on: canvas)
        #expect(canvas.commits.count == 2)
        #expect(canvas.commits.last?.actionName == "Add Line")
        #expect(segment(of: canvas.document.annotations.last)?.to == CGPoint(x: 60, y: 10))
    }

    @Test func optionDrawsFromCentre() {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .blur)
        tool.mouseDown(at(50, 50), on: canvas)
        tool.mouseDragged(at(70, 60), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 50, y: 50, width: 20, height: 10))

        // The press point becomes the centre.
        tool.flagsChanged(at(70, 60, option: true), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 30, y: 40, width: 40, height: 20))

        tool.mouseUp(at(70, 60, option: true), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(rect(of: canvas.document.annotations.last) == CGRect(x: 30, y: 40, width: 40, height: 20))
    }

    @Test func arrowShiftSnaps45() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .arrow)
        #expect(tool is TwoPointTool)
        let tail = CGPoint(x: 10, y: 10)
        let pointer = CGPoint(x: 110, y: 100)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(110, 100), on: canvas)
        #expect(segment(of: canvas.transient)?.from == tail)
        #expect(segment(of: canvas.transient)?.to == pointer)

        tool.flagsChanged(at(110, 100, shift: true), on: canvas)
        let snapped = DragGeometry.segmentEnd(from: tail, to: pointer, snap45: true)
        #expect(segment(of: canvas.transient)?.to == snapped)
        #expect(snapped.x > tail.x && snapped.y > tail.y)
        #expect(abs(abs(snapped.x - tail.x) - abs(snapped.y - tail.y)) < 0.001)

        tool.mouseUp(at(110, 100, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        let committed = try #require(segment(of: canvas.document.annotations.last))
        #expect(committed.from == tail)
        #expect(committed.to == snapped)
        #expect(canvas.made.last?.tool == .arrow)
    }

    @Test func newShapeSelected() throws {
        let existing = arrow(CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0))
        let canvas = FakeCanvasEditing([existing])
        canvas.selection = existing.id

        let pixelate = makeTool(for: .pixelate)
        pixelate.mouseDown(at(10, 10), on: canvas)
        pixelate.mouseDragged(at(80, 60), on: canvas)
        pixelate.mouseUp(at(80, 60), on: canvas)
        let region = try #require(canvas.document.annotations.last)
        #expect(region.isEffect)
        #expect(canvas.selection == region.id)

        let arrowTool = makeTool(for: .arrow)
        arrowTool.mouseDown(at(100, 100), on: canvas)
        arrowTool.mouseDragged(at(160, 120), on: canvas)
        arrowTool.mouseUp(at(160, 120), on: canvas)
        let drawn = try #require(canvas.document.annotations.last)
        #expect(segment(of: drawn) != nil)
        #expect(canvas.selection == drawn.id)
        #expect(canvas.document.annotations.count == 3)
        #expect(canvas.commits.count == 2)
    }

    @Test func selectPicksTopmost() {
        let blur = Annotation.blur(Region(id: UUID(), rect: CGRect(x: 0, y: 0, width: 200, height: 200)), radius: 16)
        let level = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let upright = arrow(CGPoint(x: 100, y: 20), CGPoint(x: 100, y: 180))
        let canvas = FakeCanvasEditing([blur, level, upright])
        let tool = makeTool(for: .select)
        #expect(tool is SelectTool)

        func click(_ x: CGFloat, _ y: CGFloat) {
            tool.mouseDown(at(x, y), on: canvas)
            tool.mouseUp(at(x, y), on: canvas)
        }
        click(100, 100)  // both arrows cross here; the later one is in front
        #expect(canvas.selection == upright.id)
        click(60, 100)
        #expect(canvas.selection == level.id)
        click(40, 40)  // away from both drawings, the blur beneath them is picked
        #expect(canvas.selection == blur.id)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.transient == nil)
    }

    @Test func moveCommitsOnceWithDelta() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)

        tool.mouseDown(at(100, 100), on: canvas)
        #expect(canvas.selection == original.id)
        tool.mouseDragged(at(110, 105), on: canvas)
        #expect(canvas.transient == original.moved(by: CGVector(dx: 10, dy: 5)))
        tool.mouseDragged(at(130, 120), on: canvas)
        #expect(canvas.transient?.id == original.id)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.document.annotations == [original])

        tool.mouseUp(at(130, 120), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        let moved = try #require(segment(of: commit.document.annotation(id: original.id)))
        #expect(moved.from == CGPoint(x: 50, y: 120))
        #expect(moved.to == CGPoint(x: 210, y: 120))
        #expect(commit.document.annotations.count == 1)
        #expect(commit.actionName == "Move \(original.title)")
        #expect(commit.coalescingKey == nil)
        #expect(canvas.transient == nil)
        #expect(canvas.selection == original.id)
    }

    @Test func shiftLocksMoveAxis() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)

        tool.mouseDown(at(100, 100), on: canvas)
        tool.mouseDragged(at(130, 110), on: canvas)
        #expect(segment(of: canvas.transient)?.from == CGPoint(x: 50, y: 110))

        // Shift mid-drag keeps the dominant horizontal travel and drops the vertical.
        tool.flagsChanged(at(130, 110, shift: true), on: canvas)
        #expect(segment(of: canvas.transient)?.from == CGPoint(x: 50, y: 100))

        tool.mouseUp(at(130, 110, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        let moved = try #require(segment(of: canvas.document.annotation(id: original.id)))
        #expect(moved.from == CGPoint(x: 50, y: 100))
        #expect(moved.to == CGPoint(x: 210, y: 100))
    }

    @Test func handleDragResizes() throws {
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 20, y: 20, width: 100, height: 80),
                                                color: red, lineWidth: 8))
        let canvas = FakeCanvasEditing([box])
        canvas.selection = box.id
        let handle = try #require(HitTester.handles(for: box).firstIndex(of: CGPoint(x: 120, y: 100)))
        let tool = makeTool(for: .select)

        tool.mouseDown(at(120, 100), on: canvas)
        tool.mouseDragged(at(170, 130), on: canvas)
        #expect(canvas.transient == HitTester.resized(box, handle: handle, to: CGPoint(x: 170, y: 130), square: false))
        #expect(canvas.commits.isEmpty)

        tool.mouseUp(at(170, 130), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(rect(of: commit.document.annotation(id: box.id)) == CGRect(x: 20, y: 20, width: 150, height: 110))
        #expect(commit.actionName == "Resize \(box.title)")
        #expect(canvas.selection == box.id)
        #expect(canvas.transient == nil)
    }

    @Test func clickEmptyDeselects() {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        canvas.selection = original.id
        let tool = makeTool(for: .select)

        tool.mouseDown(at(100, 300), on: canvas)
        #expect(canvas.selection == nil)
        tool.mouseDragged(at(150, 350), on: canvas)
        tool.mouseUp(at(150, 350), on: canvas)
        #expect(canvas.transient == nil)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.document.annotations == [original])
    }

    /// The Text tool starts typing on a click and never commits; the edit commits when it ends.
    @Test func textToolClickPlacesOrReEditsText() throws {
        let box = TextBox(id: UUID(), string: "Hello", origin: CGPoint(x: 100, y: 100), fontSize: 40, color: red)
        let canvas = FakeCanvasEditing([.text(box)])
        let tool = makeTool(for: .text)
        #expect(tool is TextTool)
        #expect(tool.cursor == NSCursor.iBeam)
        let inside = CGPoint(x: TextLayout.frame(for: box).midX, y: TextLayout.frame(for: box).midY)

        // A click on empty canvas starts a new box at the press, within the tiny-drag rule.
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseUp(at(10.5, 10), on: canvas)
        // A click on a text edits it again.
        tool.mouseDown(at(inside.x, inside.y), on: canvas)
        tool.mouseUp(at(inside.x, inside.y), on: canvas)
        // A drag places nothing.
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(40, 40), on: canvas)
        tool.mouseUp(at(40, 40), on: canvas)
        #expect(canvas.textBegun.map(\.point) == [CGPoint(x: 10, y: 10), inside])
        #expect(canvas.textBegun.map(\.existing) == [nil, box.id])
        #expect(canvas.commits.isEmpty)
        #expect(canvas.transient == nil)

        // With Select, a click selects the text and a double-click edits it again.
        let select = makeTool(for: .select)
        select.mouseDown(ToolInput(point: inside, clickCount: 1), on: canvas)
        select.mouseUp(ToolInput(point: inside, clickCount: 1), on: canvas)
        #expect(canvas.selection == box.id)
        #expect(canvas.textBegun.count == 2)
        select.mouseDown(ToolInput(point: inside, clickCount: 2), on: canvas)
        select.mouseUp(ToolInput(point: inside, clickCount: 2), on: canvas)
        #expect(canvas.textBegun.count == 3)
        #expect(canvas.textBegun.last?.existing == box.id)
        #expect(canvas.commits.isEmpty)
    }

    @Test func cropToolResizesMovesAndClamps() {
        let canvas = FakeCanvasEditing()
        canvas.cropDraft = CGRect(x: 10, y: 10, width: 20, height: 10)
        let tool = makeTool(for: .crop)
        #expect(tool is CropTool)

        // The bottom-right handle dragged past the image's corner stops at it.
        tool.mouseDown(at(30, 20), on: canvas)
        tool.mouseDragged(at(90, 70), on: canvas)
        tool.mouseUp(at(90, 70), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 10, y: 10, width: 54, height: 38))

        // A press inside moves it, size kept, held inside the image.
        tool.mouseDown(at(20, 20), on: canvas)
        tool.mouseDragged(at(-10, 20), on: canvas)
        tool.mouseUp(at(-10, 20), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 0, y: 10, width: 54, height: 38))

        // A click outside changes nothing; a drag outside draws a new rect.
        tool.mouseDown(at(62, 2), on: canvas)
        tool.mouseUp(at(62, 2), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 0, y: 10, width: 54, height: 38))
        tool.mouseDown(at(62, 2), on: canvas)
        tool.mouseDragged(at(40, 30), on: canvas)
        tool.mouseUp(at(40, 30), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 40, y: 2, width: 22, height: 28))

        // Escape (the draft cleared mid-drag) ends the gesture; the tool never commits.
        tool.mouseDown(at(50, 15), on: canvas)
        canvas.cropDraft = nil
        tool.mouseDragged(at(55, 20), on: canvas)
        tool.mouseUp(at(55, 20), on: canvas)
        #expect(canvas.cropDraft == nil)
        #expect(canvas.commits.isEmpty)
    }

    @Test func optionDragDuplicates() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)

        // An Option-click that never passes the tiny-drag rule changes nothing.
        tool.mouseDown(at(100, 100, option: true), on: canvas)
        tool.mouseUp(at(100, 100, option: true), on: canvas)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.selection == original.id)

        tool.mouseDown(at(100, 100, option: true), on: canvas)
        tool.mouseDragged(at(130, 120, option: true), on: canvas)
        let shown = try #require(canvas.transient)
        #expect(shown.id != original.id)
        #expect(shown == original.moved(by: CGVector(dx: 30, dy: 20)).withID(shown.id))
        #expect(canvas.document.annotations == [original])
        #expect(canvas.selection == original.id)

        tool.mouseUp(at(130, 120, option: true), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(commit.actionName == "Duplicate \(original.title)")
        #expect(commit.coalescingKey == nil)
        #expect(commit.document.annotations == [original, shown])
        #expect(canvas.selection == shown.id)
        #expect(canvas.transient == nil)
    }

    /// Option is live: released mid-drag the gesture is a move, pressed again the same copy returns.
    @Test func optionReleasedMidDragMoves() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)
        let moved = original.moved(by: CGVector(dx: 30, dy: 20))

        tool.mouseDown(at(100, 100, option: true), on: canvas)
        tool.mouseDragged(at(130, 120, option: true), on: canvas)
        let copyID = try #require(canvas.transient?.id)
        #expect(copyID != original.id)

        tool.flagsChanged(at(130, 120), on: canvas)
        #expect(canvas.transient == moved)
        tool.flagsChanged(at(130, 120, option: true), on: canvas)
        #expect(canvas.transient == moved.withID(copyID))
        tool.flagsChanged(at(130, 120), on: canvas)

        tool.mouseUp(at(130, 120), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(canvas.commits.first?.actionName == "Move \(original.title)")
        #expect(canvas.document.annotations == [moved])
        #expect(canvas.selection == original.id)
        #expect(canvas.transient == nil)
    }
}
