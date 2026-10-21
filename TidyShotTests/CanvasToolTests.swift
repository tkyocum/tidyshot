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
    private(set) var commits: [Commit] = []
    private(set) var made: [(tool: EditorTool, from: CGPoint, to: CGPoint)] = []

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
}
