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
}
