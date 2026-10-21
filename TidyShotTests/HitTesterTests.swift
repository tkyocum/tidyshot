import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct HitTesterTests {
    let red = EditorPalette.defaultStroke
    let id = UUID()
    /// minX 100, minY 50, maxX 300, maxY 150.
    let box = CGRect(x: 100, y: 50, width: 200, height: 100)

    func rectangle(_ rect: CGRect, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .rectangle(ShapeBox(id: id, rect: rect, color: red, lineWidth: lineWidth))
    }

    func arrow(_ from: CGPoint, _ to: CGPoint, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .arrow(Segment(id: id, from: from, to: to, color: red, lineWidth: lineWidth))
    }

    func blur(_ rect: CGRect, id: UUID = UUID()) -> Annotation {
        .blur(Region(id: id, rect: rect), radius: 16)
    }

    @Test func handlesBeforeBody() throws {
        let shape = rectangle(box)
        #expect(HitTester.handles(for: shape) == [
            CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 50), CGPoint(x: 300, y: 50), CGPoint(x: 300, y: 100),
            CGPoint(x: 300, y: 150), CGPoint(x: 200, y: 150), CGPoint(x: 100, y: 150), CGPoint(x: 100, y: 100),
        ])
        // The corner is on the stroke too; the handle wins.
        #expect(HitTester.hit(shape, at: CGPoint(x: 101, y: 51), tolerance: 8) == .handle(0))
        #expect(HitTester.hit(shape, at: CGPoint(x: 200, y: 52), tolerance: 8) == .handle(1))
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 52), tolerance: 8) == .body)
        // On a small box several handles are in range; the nearest wins.
        let small = rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(HitTester.hit(small, at: CGPoint(x: 1, y: 1), tolerance: 8) == .handle(0))
        #expect(HitTester.hit(small, at: CGPoint(x: 5, y: 1), tolerance: 8) == .handle(1))
        // Across the document every handle is tested before any body, so the corner of a blur
        // stays grabbable under an arrow that crosses it.
        let effect = blur(CGRect(x: 20, y: 20, width: 100, height: 60))
        let crossing = arrow(CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 200))
        let document = AnnotationDocument(annotations: [effect, crossing])
        let found = try #require(HitTester.topmost(in: document, at: CGPoint(x: 121, y: 81), tolerance: 4))
        #expect(found.id == effect.id)
        #expect(found.hit == .handle(4))
    }

    /// The caller passes `tolerance(zoom:)`, 8 view points in image pixels.
    @Test func toleranceScalesWithZoomInput() {
        #expect(HitTester.tolerance(zoom: 1) == 8)
        #expect(HitTester.tolerance(zoom: 4) == 2)
        #expect(HitTester.tolerance(zoom: 0.5) == 16)
        let shape = rectangle(box)
        // 6 px above the top edge, far from any handle.
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 44), tolerance: HitTester.tolerance(zoom: 1)) == .body)
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 44), tolerance: HitTester.tolerance(zoom: 4)) == nil)
        // On the 4 px stroke, inside the rect.
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 53), tolerance: HitTester.tolerance(zoom: 4)) == .body)
        // A rectangle is hollow: its middle is not its body.
        #expect(HitTester.hit(shape, at: CGPoint(x: 200, y: 100), tolerance: HitTester.tolerance(zoom: 1)) == nil)
    }

    @Test func arrowHitsAlongSegmentWithinWidth() {
        let shaft = arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), lineWidth: 10)
        // Within lineWidth / 2 + tolerance = 7 of the line.
        #expect(HitTester.hit(shaft, at: CGPoint(x: 50, y: 6), tolerance: 2) == .body)
        #expect(HitTester.hit(shaft, at: CGPoint(x: 50, y: -7), tolerance: 2) == .body)
        #expect(HitTester.hit(shaft, at: CGPoint(x: 50, y: 8), tolerance: 2) == nil)
        // Past the ends the distance is to the nearest end.
        #expect(HitTester.hit(shaft, at: CGPoint(x: 106, y: 0), tolerance: 2) == .body)
        #expect(HitTester.hit(shaft, at: CGPoint(x: -8, y: 0), tolerance: 2) == nil)
        #expect(HitTester.distance(from: CGPoint(x: 50, y: 6), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)) == 6)
        #expect(HitTester.distance(from: CGPoint(x: 103, y: 4), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)) == 5)
        #expect(HitTester.distance(from: CGPoint(x: 8, y: 9), toSegment: CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)) == 5)
    }

    /// Effects render beneath every drawing, so a drawing wins even over a later effect.
    @Test func topmostPrefersDrawingOverEffectBeneath() throws {
        let shape = rectangle(box)
        let effect = blur(CGRect(x: 0, y: 0, width: 400, height: 300))
        let document = AnnotationDocument(annotations: [shape, effect])
        let onStroke = try #require(HitTester.topmost(in: document, at: CGPoint(x: 150, y: 51), tolerance: 8))
        #expect(onStroke.id == shape.id)
        #expect(onStroke.hit == .body)
        // Of two drawings, the later one is in front.
        let first = arrow(CGPoint(x: 0, y: 100), CGPoint(x: 300, y: 100))
        let second = arrow(CGPoint(x: 150, y: 0), CGPoint(x: 150, y: 300))
        let crossed = try #require(HitTester.topmost(in: AnnotationDocument(annotations: [first, second]),
                                                     at: CGPoint(x: 150, y: 100), tolerance: 8))
        #expect(crossed.id == second.id)
    }

    @Test func effectSelectableOutsideDrawing() throws {
        let shape = rectangle(box)
        let effect = blur(CGRect(x: 0, y: 0, width: 400, height: 300))
        let document = AnnotationDocument(annotations: [shape, effect])
        let tolerance = HitTester.tolerance(zoom: 1)
        // Inside the hollow rectangle, the blur beneath is what is hit.
        let inside = try #require(HitTester.topmost(in: document, at: CGPoint(x: 200, y: 100), tolerance: tolerance))
        #expect(inside.id == effect.id)
        #expect(inside.hit == .body)
        #expect(HitTester.topmost(in: document, at: CGPoint(x: 350, y: 250), tolerance: tolerance)?.id == effect.id)
        #expect(HitTester.topmost(in: document, at: CGPoint(x: 500, y: 500), tolerance: tolerance) == nil)
        // Of two effects, the later one is in front.
        let later: Annotation = .pixelate(Region(id: UUID(), rect: CGRect(x: 50, y: 50, width: 100, height: 100)), block: 10)
        let stacked = AnnotationDocument(annotations: [effect, later])
        #expect(HitTester.topmost(in: stacked, at: CGPoint(x: 100, y: 100), tolerance: tolerance)?.id == later.id)
    }

    @Test func resizedByEachOfEightHandles() {
        let cases: [(handle: Int, point: CGPoint, expected: CGRect)] = [
            (0, CGPoint(x: 80, y: 40), CGRect(x: 80, y: 40, width: 220, height: 110)),
            (1, CGPoint(x: 999, y: 30), CGRect(x: 100, y: 30, width: 200, height: 120)),
            (2, CGPoint(x: 320, y: 40), CGRect(x: 100, y: 40, width: 220, height: 110)),
            (3, CGPoint(x: 350, y: 999), CGRect(x: 100, y: 50, width: 250, height: 100)),
            (4, CGPoint(x: 320, y: 170), CGRect(x: 100, y: 50, width: 220, height: 120)),
            (5, CGPoint(x: 0, y: 180), CGRect(x: 100, y: 50, width: 200, height: 130)),
            (6, CGPoint(x: 90, y: 160), CGRect(x: 90, y: 50, width: 210, height: 110)),
            (7, CGPoint(x: 60, y: 0), CGRect(x: 60, y: 50, width: 240, height: 100)),
        ]
        for item in cases {
            #expect(HitTester.resized(rectangle(box, id: id), handle: item.handle, to: item.point, square: false)
                    == rectangle(item.expected, id: id))
        }
        // Dragging past the opposite corner flips the rect.
        #expect(HitTester.resizedRect(box, handle: 4, to: CGPoint(x: 40, y: 20), square: false)
                == CGRect(x: 40, y: 20, width: 60, height: 30))
        // Shift squares a corner drag and leaves an edge drag alone.
        #expect(HitTester.resizedRect(box, handle: 4, to: CGPoint(x: 400, y: 100), square: true)
                == CGRect(x: 100, y: 50, width: 300, height: 300))
        #expect(HitTester.resizedRect(box, handle: 3, to: CGPoint(x: 350, y: 0), square: true)
                == CGRect(x: 100, y: 50, width: 250, height: 100))
        #expect(HitTester.resizedRect(box, handle: 8, to: .zero, square: false) == box)
        // Effects keep their id and parameter.
        #expect(HitTester.resized(blur(box, id: id), handle: 4, to: CGPoint(x: 320, y: 170), square: false)
                == blur(CGRect(x: 100, y: 50, width: 220, height: 120), id: id))
        let fill = EditorPalette.defaultRedact
        #expect(HitTester.resized(.redact(Region(id: id, rect: box), fill: fill), handle: 0, to: CGPoint(x: 80, y: 40), square: false)
                == .redact(Region(id: id, rect: CGRect(x: 80, y: 40, width: 220, height: 110)), fill: fill))
    }

    @Test func arrowEndpointHandlesMoveEnds() {
        let original = arrow(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), lineWidth: 6, id: id)
        #expect(HitTester.handles(for: original) == [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10)])
        #expect(HitTester.hit(original, at: CGPoint(x: 99, y: 12), tolerance: 8) == .handle(1))
        #expect(HitTester.hit(original, at: CGPoint(x: 12, y: 9), tolerance: 8) == .handle(0))
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 120, y: 40), square: false)
                == arrow(CGPoint(x: 10, y: 10), CGPoint(x: 120, y: 40), lineWidth: 6, id: id))
        #expect(HitTester.resized(original, handle: 0, to: CGPoint(x: 0, y: 0), square: false)
                == arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 10), lineWidth: 6, id: id))
        // Shift snaps the moved end to 45 degrees around the other end.
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 200, y: 15), square: true)
                == arrow(CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10), lineWidth: 6, id: id))
        #expect(HitTester.resized(original, handle: 0, to: CGPoint(x: 40, y: -45), square: true)
                == arrow(CGPoint(x: 42.5, y: -47.5), CGPoint(x: 100, y: 10), lineWidth: 6, id: id))
    }
}
