import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The rect `AnnotationDrawing.drawSelection` outlines with dashes, in image pixels.
struct SelectionOutlineTests {
    let red = EditorPalette.defaultStroke
    let rect = CGRect(x: 10, y: 20, width: 30, height: 40)

    /// A counter has no handles, so its circle's bounding square is outlined, as text's frame is.
    @Test func counterOutlinesItsBoundingSquare() {
        let mark = Annotation.counter(CounterMark(id: UUID(), center: CGPoint(x: 50, y: 60), number: 4, diameter: 32,
                                                  color: red))
        #expect(AnnotationGeometry.selectionOutline(of: mark) == CGRect(x: 34, y: 44, width: 32, height: 32))
    }

    /// A spotlight's rect is outlined whichever its shape, besides its eight handles.
    @Test func spotlightOutlinesItsRect() {
        for isEllipse in [false, true] {
            let shape = Annotation.spotlight(SpotlightShape(id: UUID(), rect: rect, isEllipse: isEllipse))
            #expect(AnnotationGeometry.selectionOutline(of: shape) == rect)
        }
    }

    /// Every kind before 4c gets what `effectRect ?? strokeOutline ?? textFrame` gave: an effect's
    /// rect, a stroke's outline, a text's frame, and nothing for the shapes, whose handles show
    /// where they are.
    @Test func earlierKindsAreUnchanged() {
        let id = UUID()
        let stroke = Stroke(id: id, points: [CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), CGPoint(x: 200, y: 100)],
                            color: red, lineWidth: 8)
        let text = TextBox(id: id, string: "Hello\nworld", origin: CGPoint(x: 12, y: 30), fontSize: 40, color: red)
        let kinds: [Annotation] = [
            .rectangle(ShapeBox(id: id, rect: rect, color: red, lineWidth: 4)),
            .ellipse(ShapeBox(id: id, rect: rect, color: red, lineWidth: 4)),
            .arrow(Segment(id: id, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 60, y: 45), color: red, lineWidth: 8)),
            .line(Segment(id: id, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 60, y: 45), color: red, lineWidth: 8)),
            .pencil(stroke),
            .highlighter(stroke),
            .text(text),
            .redact(Region(id: id, rect: rect), fill: red),
            .blur(Region(id: id, rect: rect), radius: 16),
            .pixelate(Region(id: id, rect: rect), block: 12),
        ]
        for annotation in kinds {
            let textFrame: CGRect? = if case .text(let box) = annotation { TextLayout.frame(for: box) } else { nil }
            let before = annotation.effectRect ?? AnnotationGeometry.strokeOutline(of: annotation) ?? textFrame
            #expect(AnnotationGeometry.selectionOutline(of: annotation) == before, "\(annotation.title)")
        }
        #expect(kinds.prefix(4).allSatisfy { AnnotationGeometry.selectionOutline(of: $0) == nil })
        #expect(AnnotationGeometry.selectionOutline(of: .pencil(stroke)) == AnnotationGeometry.strokeBounds(of: stroke))
        #expect(AnnotationGeometry.selectionOutline(of: .text(text)) == TextLayout.frame(for: text))
        #expect(AnnotationGeometry.selectionOutline(of: .blur(Region(id: id, rect: rect), radius: 16)) == rect)
    }
}
