import AppKit
import Testing
@testable import TidyShot

/// Synthesized pointer and key events on a windowless `CanvasView` over an `EditorModel` with
/// `FakeTileRenderer` (spec 2.6, Phase 4b): what a letter, Space, a re-edit, a crop and object copy and paste do
/// on the canvas itself.
struct CanvasViewEventTests {
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)

    /// A canvas over an 800 x 600 capture at `scale`, fitted into 300 x 200 points.
    func makeCanvas(scale: CGFloat = 2) -> (canvas: CanvasView, model: EditorModel) {
        let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        let model = EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: scale),
                                renderer: FakeTileRenderer(), defaults: .standard)
        let canvas = CanvasView(model: model, baseView: BaseImageView(frame: .zero))
        canvas.setFrameSize(NSSize(width: 300, height: 200))
        return (canvas, model)
    }

    /// A left-button event at `point` in the canvas's own coordinates.
    func mouse(_ type: NSEvent.EventType, at point: CGPoint, in canvas: CanvasView) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                           pressure: type == .leftMouseUp ? 0 : 1)!
    }

    /// A press at `start`, one move to `end` and the release there, in view points.
    func drag(_ canvas: CanvasView, from start: CGPoint, to end: CGPoint) {
        canvas.mouseDown(with: mouse(.leftMouseDown, at: start, in: canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, in: canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: end, in: canvas))
    }

    func key(_ characters: String, _ keyCode: UInt16, up: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                         windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }

    func rect(of annotation: Annotation?) -> CGRect? {
        if case .rectangle(let box)? = annotation { return box.rect }
        return nil
    }

    /// The clipboard two editors share, standing in for the coordinator's (`EditorObjectClipboard`).
    final class ObjectClips {
        var data: Data?
        private(set) var writes = 0

        var clipboard: EditorObjectClipboard {
            EditorObjectClipboard(copy: { [self] in data = $0; writes += 1 }, paste: { [self] in data },
                                  canPaste: { [self] in data != nil })
        }
    }

    /// phase-4b :30, in part. A letter pressed in the middle of a drag does nothing; after the release the same
    /// letter picks its tool. By hand: the toolbar following the tool (the letters themselves are
    /// `KeyRoutingTests.lettersSelectTools`, `.editingTextSuppressesLetters`).
    @Test func aLetterPressedDuringADragKeepsTheTool() {
        let (canvas, model) = makeCanvas()
        canvas.keyDown(with: key("r", 15))
        #expect(model.tool == .rectangle)

        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 60), in: canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 120), in: canvas))
        canvas.keyDown(with: key("e", 14))
        #expect(model.tool == .rectangle)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 160, y: 120), in: canvas))
        #expect(model.document.annotations.count == 1)

        canvas.keyDown(with: key("e", 14))
        #expect(model.tool == .ellipse)
    }

    /// phase-4b :56. Re-editing a committed text puts the caret at the end of its string, in a text view at the
    /// text's own frame through the canvas's transform.
    @Test func reEditingATextPutsTheCaretAtTheEndInTheTextsFrame() async throws {
        let (canvas, model) = makeCanvas()
        let box = TextBox(id: UUID(), string: "Hello", origin: CGPoint(x: 200, y: 200), fontSize: 40, color: red)
        model.commit(model.document.appending(.text(box)), actionName: "Add Text")

        model.beginTextEditing(at: CGPoint(x: 210, y: 210), existing: box.id)
        // The canvas installs the text view on its next refresh, which the model's observation schedules.
        try await eventually { canvas.subviews.contains { $0 is NSTextView } }

        let view = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        #expect(view.string == "Hello")
        #expect(view.selectedRange() == NSRange(location: 5, length: 0))
        let frame = TextLayout.frame(for: box)
        #expect(view.frame.origin == model.transform.viewPoint(frame.origin))
        #expect(view.frame.width == frame.width * model.transform.zoom)
        #expect(view.frame.height == frame.height * model.transform.zoom)
    }

    /// phase-4b :82. With a crop applied, input stops at the crop's edge: a Rectangle dragged from inside out into the
    /// covered area ends on the edge, one dragged from the covered area in starts on it, and a click in the
    /// covered area with Text starts no text.
    @Test func drawingUnderAnAppliedCropStopsAtItsEdge() {
        let (canvas, model) = makeCanvas()
        let crop = CGRect(x: 200, y: 150, width: 400, height: 300)
        model.tool = .crop
        model.cropDraft = crop
        model.applyCrop()
        canvas.keyDown(with: key("r", 15))
        canvas.fitToView()
        let view = { (image: CGPoint) in model.transform.viewPoint(image) }

        drag(canvas, from: view(CGPoint(x: 300, y: 250)), to: view(CGPoint(x: 700, y: 550)))
        let outward = rect(of: model.document.annotations.last)
        #expect(abs((outward?.minX ?? 0) - 300) < 0.01)
        #expect(abs((outward?.maxX ?? 0) - crop.maxX) < 0.01)
        #expect(abs((outward?.maxY ?? 0) - crop.maxY) < 0.01)

        drag(canvas, from: view(CGPoint(x: 100, y: 100)), to: view(CGPoint(x: 400, y: 300)))
        let inward = rect(of: model.document.annotations.last)
        #expect(abs((inward?.minX ?? 0) - crop.minX) < 0.01)
        #expect(abs((inward?.minY ?? 0) - crop.minY) < 0.01)
        #expect(model.document.annotations.count == 2)

        canvas.keyDown(with: key("t", 17))
        let covered = view(CGPoint(x: 100, y: 100))
        canvas.mouseDown(with: mouse(.leftMouseDown, at: covered, in: canvas))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: covered, in: canvas))
        #expect(!model.isEditingText)
        #expect(model.document.annotations.count == 2)
    }

    /// phase-4b :91. An object copied in one editor pastes into another, selected, with the same string, colour and
    /// point size, also from a 2x capture into a 1x one: a text, a pencil stroke and a redaction. The first
    /// editor is unchanged, and only the second has unsaved changes.
    @Test func anObjectCopiedInOneCanvasPastesIntoAnotherAtItsPointSize() throws {
        let clips = ObjectClips()
        let (first, source) = makeCanvas(scale: 2)
        let (second, target) = makeCanvas(scale: 1)
        first.objectClipboard = clips.clipboard
        second.objectClipboard = clips.clipboard
        let text = Annotation.text(TextBox(id: UUID(), string: "Note", origin: CGPoint(x: 100, y: 100), fontSize: 40,
                                           color: red))
        let stroke = Annotation.pencil(Stroke(id: UUID(), points: [CGPoint(x: 100, y: 300), CGPoint(x: 160, y: 320),
                                                                   CGPoint(x: 220, y: 300)], color: red, lineWidth: 8))
        let redaction = Annotation.redact(Region(id: UUID(), rect: CGRect(x: 400, y: 100, width: 80, height: 40)),
                                          fill: RGBA(red: 0, green: 0, blue: 0, alpha: 1))
        source.commit(AnnotationDocument(annotations: [text, stroke, redaction]), actionName: "Add")
        source.markSaved()
        let before = source.document

        for original in [text, stroke, redaction] {
            source.selection = original.id
            first.copy(nil)
            second.paste(nil)
            let pasted = try #require(target.document.annotations.last)
            #expect(target.selection == pasted.id)
            switch (original, pasted) {
            case (.text(let from), .text(let to)):
                #expect(to.string == from.string)
                #expect(to.color == from.color)
                #expect(to.fontSize == from.fontSize / 2)
            case (.pencil(let from), .pencil(let to)):
                #expect(to.color == from.color)
                #expect(to.lineWidth == from.lineWidth / 2)
            case (.redact(let from, let fromFill), .redact(let to, let toFill)):
                #expect(toFill == fromFill)
                #expect(to.rect.size == CGSize(width: from.rect.width / 2, height: from.rect.height / 2))
            default:
                Issue.record("pasted \(pasted.title) for \(original.title)")
            }
        }

        #expect(clips.writes == 3)
        #expect(source.document == before)
        #expect(!source.hasUnsavedChanges)
        #expect(target.hasUnsavedChanges)
    }

    /// phase-4b :99, in part; phase-4b :100. Space pressed in the middle of a Rectangle drag starts no pan, the drag
    /// draws and the next drag draws again; Space let go mid-pan keeps panning until the release; after
    /// `endSpacePan()` (the window's resign-key) a press reaches the tool; with a crop pending, a Space-drag pans and
    /// leaves the draft where it was. By hand (phase-4b :99): the ⌘-Tab itself.
    @Test func spacePansOnlyBetweenDragsAndNeverMovesACropDraft() {
        let (canvas, model) = makeCanvas()
        let space = key(" ", 49)
        let spaceUp = key(" ", 49, up: true)
        canvas.keyDown(with: key("r", 15))
        let fitted = model.transform

        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 60), in: canvas))
        canvas.keyDown(with: space)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 120), in: canvas))
        canvas.keyUp(with: spaceUp)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 160, y: 120), in: canvas))
        #expect(model.document.annotations.count == 1)
        #expect(model.transform == fitted)
        drag(canvas, from: CGPoint(x: 120, y: 70), to: CGPoint(x: 170, y: 110))
        #expect(model.document.annotations.count == 2)

        canvas.keyDown(with: space)
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 60), in: canvas))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 130, y: 60), in: canvas))
        let panned = model.transform
        #expect(panned != fitted)
        canvas.keyUp(with: spaceUp)
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 60), in: canvas))
        #expect(model.transform != panned)
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 160, y: 60), in: canvas))
        #expect(model.document.annotations.count == 2)

        canvas.keyDown(with: space)
        canvas.endSpacePan()
        drag(canvas, from: CGPoint(x: 100, y: 60), to: CGPoint(x: 150, y: 100))
        #expect(model.document.annotations.count == 3)

        canvas.keyDown(with: key("c", 8))
        #expect(model.tool == .crop)
        let draft = CGRect(x: 100, y: 100, width: 300, height: 200)
        model.cropDraft = draft
        let beforePan = model.transform
        canvas.keyDown(with: space)
        let inside = model.transform.viewPoint(CGPoint(x: 250, y: 200))
        drag(canvas, from: inside, to: CGPoint(x: inside.x + 40, y: inside.y + 20))
        canvas.keyUp(with: spaceUp)
        #expect(model.cropDraft == draft)
        #expect(model.transform != beforePan)
    }
}
