import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct AnnotationDocumentTests {
    let boxID = UUID()
    let redactID = UUID()
    let arrowID = UUID()
    let blurID = UUID()
    let pixelateID = UUID()
    let red = EditorPalette.defaultStroke
    let black = EditorPalette.defaultRedact
    let blue = RGBA(red: 0, green: 0, blue: 1)

    // One fixture per kind, each with a fixed id, so a test can build the value it expects.
    func box(rect: CGRect = CGRect(x: 10, y: 20, width: 30, height: 40), color: RGBA? = nil,
             lineWidth: CGFloat = 8) -> Annotation {
        .rectangle(ShapeBox(id: boxID, rect: rect, color: color ?? red, lineWidth: lineWidth))
    }

    func arrow(from: CGPoint = CGPoint(x: 5, y: 5), to: CGPoint = CGPoint(x: 60, y: 45), color: RGBA? = nil,
               lineWidth: CGFloat = 8) -> Annotation {
        .arrow(Segment(id: arrowID, from: from, to: to, color: color ?? red, lineWidth: lineWidth))
    }

    func redact(rect: CGRect = CGRect(x: 0, y: 0, width: 50, height: 10), fill: RGBA? = nil) -> Annotation {
        .redact(Region(id: redactID, rect: rect), fill: fill ?? black)
    }

    func blur(rect: CGRect = CGRect(x: 20, y: 30, width: 40, height: 20), radius: CGFloat = 16) -> Annotation {
        .blur(Region(id: blurID, rect: rect), radius: radius)
    }

    func pixelate(rect: CGRect = CGRect(x: 40, y: 0, width: 24, height: 24), block: CGFloat = 12) -> Annotation {
        .pixelate(Region(id: pixelateID, rect: rect), block: block)
    }

    /// Drawings and effects interleaved, in creation order.
    var mixed: AnnotationDocument {
        AnnotationDocument(annotations: [box(), redact(), arrow(), blur(), pixelate()])
    }

    @Test func appendKeepsCreationOrder() {
        let empty = AnnotationDocument()
        let one = empty.appending(box())
        let two = one.appending(redact())
        #expect(empty.annotations.isEmpty)
        #expect(one.annotations == [box()])
        #expect(two.annotations.map(\.id) == [boxID, redactID])
    }

    @Test func effectsAndDrawingsSplitInOrder() {
        #expect(mixed.effects == [redact(), blur(), pixelate()])
        #expect(mixed.drawings == [box(), arrow()])
        #expect(mixed.annotations.map(\.isEffect) == [false, true, false, true, true])
    }

    @Test func removingAndReplacingById() {
        let removed = mixed.removing(id: arrowID)
        #expect(removed.annotations == [box(), redact(), blur(), pixelate()])
        #expect(removed.annotation(id: arrowID) == nil)
        #expect(mixed.annotation(id: blurID) == blur())
        #expect(mixed.removing(id: UUID()) == mixed)

        let replaced = mixed.replacing(box(color: blue))
        #expect(replaced.annotations == [box(color: blue), redact(), arrow(), blur(), pixelate()])

        let stranger = Annotation.redact(Region(id: UUID(), rect: .zero), fill: black)
        #expect(mixed.replacing(stranger) == mixed)
    }

    @Test func movingShiftsRectAndSegmentEndpoints() {
        let delta = CGVector(dx: 3, dy: -2)
        let moved = mixed.moving(id: boxID, by: delta).moving(id: arrowID, by: delta).moving(id: blurID, by: delta)
        #expect(moved.annotations == [
            box(rect: CGRect(x: 13, y: 18, width: 30, height: 40)),
            redact(),
            arrow(from: CGPoint(x: 8, y: 3), to: CGPoint(x: 63, y: 43)),
            blur(rect: CGRect(x: 23, y: 28, width: 40, height: 20)),
            pixelate(),
        ])
        #expect(redact().moved(by: delta) == redact(rect: CGRect(x: 3, y: -2, width: 50, height: 10)))
        #expect(pixelate().moved(by: delta) == pixelate(rect: CGRect(x: 43, y: -2, width: 24, height: 24)))
        #expect(mixed.moving(id: UUID(), by: delta) == mixed)
    }

    @Test func jsonRoundTrip() throws {
        let data = try JSONEncoder().encode(mixed)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)
        #expect(decoded == mixed)
        #expect(decoded.effects.map(\.id) == [redactID, blurID, pixelateID])
    }

    @Test func equalityIsValueBased() {
        #expect(mixed == AnnotationDocument(annotations: [box(), redact(), arrow(), blur(), pixelate()]))
        #expect(mixed != mixed.replacing(box(color: blue)))
        #expect(mixed != mixed.replacing(blur(radius: 17)))
        // The same values under another id are another annotation.
        let twin = Annotation.redact(Region(id: UUID(), rect: CGRect(x: 0, y: 0, width: 50, height: 10)), fill: black)
        #expect(twin != redact())
        // Creation order is drawing order, so it counts.
        #expect(AnnotationDocument(annotations: [box(), arrow()]) != AnnotationDocument(annotations: [arrow(), box()]))
    }

    /// Colour, line width and effect parameter each change only the kinds they mean something for.
    @Test func editsTouchOnlyTheKindsTheyApplyTo() {
        #expect(box().withColor(blue) == box(color: blue))
        #expect(arrow().withColor(blue) == arrow(color: blue))
        #expect(redact().withColor(blue) == redact(fill: blue))
        #expect(blur().withColor(blue) == blur())
        #expect(pixelate().withColor(blue) == pixelate())

        #expect(box().withLineWidth(24) == box(lineWidth: 24))
        #expect(arrow().withLineWidth(24) == arrow(lineWidth: 24))
        #expect(redact().withLineWidth(24) == redact())
        #expect(blur().withLineWidth(24) == blur())

        #expect(blur().withEffectParameter(30) == blur(radius: 30))
        #expect(pixelate().withEffectParameter(30) == pixelate(block: 30))
        #expect(redact().withEffectParameter(30) == redact())
        #expect(box().withEffectParameter(30) == box())

        #expect(box().effectRect == nil)
        #expect(arrow().effectRect == nil)
        #expect(redact().effectRect == CGRect(x: 0, y: 0, width: 50, height: 10))
        #expect(pixelate().effectRect == CGRect(x: 40, y: 0, width: 24, height: 24))
        #expect(mixed.annotations.map(\.title) == ["Rectangle", "Redact", "Arrow", "Blur", "Pixelate"])
        #expect(mixed.annotations.map(\.id) == [boxID, redactID, arrowID, blurID, pixelateID])
    }
}
