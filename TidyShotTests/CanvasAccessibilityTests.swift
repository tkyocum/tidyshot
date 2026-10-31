import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct CanvasAccessibilityTests {
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)
    let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    func arrow(_ y: CGFloat) -> Annotation {
        .arrow(Segment(id: UUID(), from: CGPoint(x: 0, y: y), to: CGPoint(x: 50, y: y), color: red, lineWidth: 4))
    }

    func redaction(_ x: CGFloat) -> Annotation {
        .redact(Region(id: UUID(), rect: CGRect(x: x, y: 0, width: 10, height: 10)), fill: black)
    }

    /// A canvas over a 200 x 150 capture at scale 1, fitted into 300 x 200 points, with no window.
    func makeCanvas() -> (canvas: CanvasView, model: EditorModel) {
        let context = CGContext(data: nil, width: 200, height: 150, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
        let model = EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: 1),
                                renderer: FakeTileRenderer(), defaults: .standard)
        let canvas = CanvasView(model: model, baseView: BaseImageView(frame: .zero))
        canvas.setFrameSize(NSSize(width: 300, height: 200))
        return (canvas, model)
    }

    func elements(_ canvas: CanvasView) -> [AnnotationAccessibilityElement] {
        (canvas.accessibilityChildren() ?? []).compactMap { $0 as? AnnotationAccessibilityElement }
    }

    func element(_ id: UUID, in canvas: CanvasView) throws -> AnnotationAccessibilityElement {
        try #require(elements(canvas).first { $0.annotationID == id })
    }

    func key(_ characters: String, _ keyCode: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                         keyCode: keyCode)!
    }

    /// Effects paint first, so VoiceOver reads them first; each kind is numbered on its own.
    @Test func itemsFollowPaintingOrderAndNumberEachKind() {
        let firstArrow = arrow(10)
        let firstRedact = redaction(0)
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 5, y: 5, width: 20, height: 20),
                                                color: red, lineWidth: 4))
        let secondArrow = arrow(40)
        let secondRedact = redaction(30)
        let document = AnnotationDocument(annotations: [firstArrow, firstRedact, box, secondArrow, secondRedact])
        let items = CanvasAccessibility.items(in: document, scale: 1)
        #expect(items.map(\.id) == [firstRedact.id, secondRedact.id, firstArrow.id, box.id, secondArrow.id])
        #expect(items.map(\.label) == ["Redact 1", "Redact 2", "Arrow 1", "Rectangle 1", "Arrow 2"])
        #expect(items.allSatisfy { $0.value == nil })
        #expect(CanvasAccessibility.items(in: AnnotationDocument(annotations: []), scale: 1).isEmpty)
        #expect(CanvasAccessibility.canvasLabel == "Annotation canvas")
    }

    /// Spotlights paint between the effects and the drawings (spec 2.12), so VoiceOver reads them
    /// there, numbered on their own in creation order.
    @Test func spotlightsReadBetweenEffectsAndDrawings() {
        func spotlight(_ x: CGFloat) -> Annotation {
            .spotlight(SpotlightShape(id: UUID(), rect: CGRect(x: x, y: 0, width: 20, height: 20), isEllipse: x > 50))
        }
        let firstArrow = arrow(10)
        let firstSpotlight = spotlight(0)
        let redact = redaction(0)
        let secondSpotlight = spotlight(60)
        let document = AnnotationDocument(annotations: [firstArrow, firstSpotlight, redact, secondSpotlight])
        let items = CanvasAccessibility.items(in: document, scale: 1)
        #expect(items.map(\.id) == [redact.id, firstSpotlight.id, secondSpotlight.id, firstArrow.id])
        #expect(items.map(\.label) == ["Redact 1", "Spotlight 1", "Spotlight 2", "Arrow 1"])
        #expect(items.allSatisfy { $0.value == nil })
    }

    /// A counter reads its own number, not a count, and has no value, so after a middle counter is
    /// deleted VoiceOver still reads what the picture shows.
    @Test func countersReadTheirOwnNumbers() {
        func counter(_ number: Int) -> Annotation {
            .counter(CounterMark(id: UUID(), center: CGPoint(x: 20 * CGFloat(number), y: 20), number: number,
                                 diameter: 16, color: red))
        }
        let first = arrow(10)
        let one = counter(1)
        let two = counter(2)
        let three = counter(3)
        let document = AnnotationDocument(annotations: [one, first, two, three])
        let items = CanvasAccessibility.items(in: document, scale: 1)
        #expect(items.map(\.id) == [one.id, first.id, two.id, three.id])
        #expect(items.map(\.label) == ["Counter 1", "Arrow 1", "Counter 2", "Counter 3"])
        #expect(items.allSatisfy { $0.value == nil })

        let afterDelete = CanvasAccessibility.items(in: document.removing(id: two.id), scale: 1)
        #expect(afterDelete.map(\.label) == ["Counter 1", "Arrow 1", "Counter 3"])
        #expect(afterDelete.allSatisfy { $0.value == nil })
    }

    @Test func textItemReadsItsString() {
        let text = Annotation.text(TextBox(id: UUID(), string: "Click here", origin: CGPoint(x: 4, y: 4),
                                           fontSize: 40, color: red))
        let items = CanvasAccessibility.items(in: AnnotationDocument(annotations: [text]), scale: 1)
        #expect(items.map(\.label) == ["Text 1"])
        #expect(items.first?.value == "Click here")
    }

    /// With a crop applied the canvas shows only the crop, so VoiceOver lists only what reaches into it.
    @Test func cropHidesAnnotationsOutsideIt() {
        let inside = arrow(10)
        let straddling = redaction(90)
        let outside = redaction(300)
        let outsideArrow = arrow(250)
        let document = AnnotationDocument(annotations: [inside, straddling, outside, outsideArrow])
            .withCrop(CGRect(x: 0, y: 0, width: 100, height: 100))
        let items = CanvasAccessibility.items(in: document, scale: 1)
        #expect(items.map(\.id) == [straddling.id, inside.id])
        #expect(items.map(\.label) == ["Redact 1", "Arrow 1"])
        #expect(CanvasAccessibility.items(in: document.withCrop(nil), scale: 1).count == 4)
    }

    /// phase-4b :128. The canvas's elements follow edits at once: one element is kept for an annotation across a
    /// move and a resize, none is left for a deleted one, and a new one takes its place in painting order (a
    /// drawing last, an effect after the other effects).
    @Test func canvasElementsFollowMovesResizesDeletesAndAdds() throws {
        let (canvas, model) = makeCanvas()
        let line = arrow(10)
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 20, y: 40, width: 30, height: 20), color: red,
                                                lineWidth: 4))
        let hidden = redaction(100)
        model.commit(AnnotationDocument(annotations: [line, box, hidden]), actionName: "Add")
        let boxElement = try element(box.id, in: canvas)

        model.commit(model.document.moving(id: box.id, by: CGVector(dx: 10, dy: 5)), actionName: "Move")
        #expect(try element(box.id, in: canvas) === boxElement)
        let resized = Annotation.rectangle(ShapeBox(id: box.id, rect: CGRect(x: 30, y: 45, width: 60, height: 40),
                                                    color: red, lineWidth: 4))
        model.commit(model.document.replacing(resized), actionName: "Resize")
        #expect(try element(box.id, in: canvas) === boxElement)

        model.commit(model.document.removing(id: line.id), actionName: "Delete")
        #expect(!elements(canvas).contains { $0.annotationID == line.id })

        let ellipse = Annotation.ellipse(ShapeBox(id: UUID(), rect: CGRect(x: 60, y: 60, width: 20, height: 20),
                                                  color: red, lineWidth: 4))
        let blur = Annotation.blur(Region(id: UUID(), rect: CGRect(x: 120, y: 20, width: 20, height: 20)), radius: 8)
        model.commit(model.document.appending(ellipse).appending(blur), actionName: "Add")
        let ids = elements(canvas).map(\.annotationID)
        #expect(ids == CanvasAccessibility.items(in: model.document, scale: model.scale).map(\.id))
        #expect(ids == [hidden.id, blur.id, box.id, ellipse.id])
        #expect(try element(box.id, in: canvas) === boxElement)
    }

    /// phase-4b :129, phase-4b :131, phase-4c :209, in part. VO-Space (AXPress) on an element selects its annotation,
    /// which the canvas reports as selected, and pressing another moves that state; Delete, the arrow keys, ⌘C and
    /// ⌘D then act on it. By hand (phase-4c :209): VoiceOver itself, and the canvas's own list with a crop.
    @Test func anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection() throws {
        let (canvas, model) = makeCanvas()
        var writes = 0
        canvas.objectClipboard = EditorObjectClipboard(copy: { _ in writes += 1 }, paste: { nil }, canPaste: { false })
        let first = arrow(10)
        let second = arrow(60)
        let third = arrow(110)
        model.commit(AnnotationDocument(annotations: [first, second, third]), actionName: "Add")
        let firstElement = try element(first.id, in: canvas)
        let secondElement = try element(second.id, in: canvas)

        #expect(firstElement.accessibilityPerformPress())
        #expect(model.selection == first.id)
        #expect(firstElement.isAccessibilitySelected())
        #expect(!secondElement.isAccessibilitySelected())
        let selected = (canvas.accessibilitySelectedChildren() ?? []).compactMap { $0 as? AnnotationAccessibilityElement }
        #expect(selected.map(\.annotationID) == [first.id])

        #expect(secondElement.accessibilityPerformPress())
        #expect(model.selection == second.id)
        #expect(secondElement.isAccessibilitySelected())
        #expect(!firstElement.isAccessibilitySelected())

        canvas.moveLeft(nil)
        #expect(model.document.annotation(id: second.id) == second.moved(by: CGVector(dx: -1, dy: 0)))
        canvas.copy(nil)
        #expect(writes == 1)
        canvas.duplicate(nil)
        #expect(model.document.annotations.count == 4)
        #expect(try element(third.id, in: canvas).accessibilityPerformPress())
        canvas.deleteBackward(nil)
        #expect(model.document.annotation(id: third.id) == nil)
    }

    /// phase-4b :130, in part; phase-4c :209, in part. AXPress does nothing while the Crop tool is active or while a
    /// drag runs, and the selection stays. The listing under an applied crop is `cropHidesAnnotationsOutsideIt`.
    /// By hand (phase-4b :130): the list while the Crop tool is open over an applied crop.
    @Test func anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag() throws {
        let (canvas, model) = makeCanvas()
        let first = arrow(10)
        let second = arrow(60)
        model.commit(AnnotationDocument(annotations: [first, second]), actionName: "Add")
        let firstElement = try element(first.id, in: canvas)
        let secondElement = try element(second.id, in: canvas)

        canvas.keyDown(with: key("c", 8))
        #expect(model.tool == .crop)
        #expect(!secondElement.accessibilityPerformPress())
        #expect(model.selection == nil)
        canvas.cancelOperation(nil)

        canvas.keyDown(with: key("v", 9))
        #expect(firstElement.accessibilityPerformPress())
        let onFirst = canvas.convert(model.transform.viewPoint(CGPoint(x: 25, y: 10)), to: nil)
        canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: onFirst, modifierFlags: [], timestamp: 0,
                                                  windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                                                  pressure: 1)!)
        #expect(!secondElement.accessibilityPerformPress())
        #expect(model.selection == first.id)
        canvas.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: onFirst, modifierFlags: [], timestamp: 0,
                                                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                                                pressure: 0)!)
    }
}
