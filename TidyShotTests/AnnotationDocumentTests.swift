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

    /// Strokes are drawings; they move by shifting every point, recolour (a highlighter keeps its
    /// alpha), change width, ignore effect parameters, and survive an encode and decode.
    @Test func strokesMoveRecolourAndRoundTrip() throws {
        let id = UUID()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 0)]
        let pencil = Annotation.pencil(Stroke(id: id, points: points, color: red, lineWidth: 6))
        let marker = Annotation.highlighter(Stroke(id: id, points: points, color: EditorPalette.defaultHighlight, lineWidth: 24))

        #expect(!pencil.isEffect)
        #expect(!marker.isEffect)
        #expect(pencil.effectRect == nil)
        #expect(pencil.id == id)
        #expect(pencil.title == "Pencil")
        #expect(marker.title == "Highlighter")

        let shifted = points.map { CGPoint(x: $0.x + 3, y: $0.y - 2) }
        #expect(pencil.moved(by: CGVector(dx: 3, dy: -2)) == .pencil(Stroke(id: id, points: shifted, color: red, lineWidth: 6)))
        #expect(pencil.withColor(blue) == .pencil(Stroke(id: id, points: points, color: blue, lineWidth: 6)))
        #expect(marker.withColor(blue)
                == .highlighter(Stroke(id: id, points: points, color: RGBA(red: 0, green: 0, blue: 1, alpha: 0.45), lineWidth: 24)))
        #expect(pencil.withLineWidth(12) == .pencil(Stroke(id: id, points: points, color: red, lineWidth: 12)))
        #expect(marker.withEffectParameter(9) == marker)

        let document = AnnotationDocument(annotations: [pencil, box(), marker.withColor(blue)])
        #expect(document.drawings.count == 3)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded == document)
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

    /// A document written before 4b has no "crop" key and decodes with no crop; an uncropped
    /// document writes none; a crop round-trips; edits keep it.
    @Test func documentWithoutCropDecodes() throws {
        let old = try JSONDecoder().decode(AnnotationDocument.self, from: Data(#"{"annotations":[]}"#.utf8))
        #expect(old == AnnotationDocument(annotations: []))
        #expect(old.crop == nil)
        let json = try JSONEncoder().encode(mixed)
        let written = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(!written.keys.contains("crop"))

        let crop = CGRect(x: 4, y: 6, width: 30, height: 20)
        let cropped = mixed.withCrop(crop)
        #expect(cropped != mixed)
        #expect(try JSONDecoder().decode(AnnotationDocument.self, from: JSONEncoder().encode(cropped)) == cropped)
        #expect(cropped.removing(id: boxID).crop == crop)
        #expect(cropped.moving(id: arrowID, by: CGVector(dx: 1, dy: 1)).crop == crop)
        #expect(cropped.withCrop(nil) == mixed)
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
