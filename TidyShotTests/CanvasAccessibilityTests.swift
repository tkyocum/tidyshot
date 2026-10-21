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
}
