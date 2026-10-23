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

    func ellipse(_ rect: CGRect, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .ellipse(ShapeBox(id: id, rect: rect, color: red, lineWidth: lineWidth))
    }

    func line(_ from: CGPoint, _ to: CGPoint, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .line(Segment(id: id, from: from, to: to, color: red, lineWidth: lineWidth))
    }

    func pencil(_ points: [CGPoint], width: CGFloat = 8, id: UUID = UUID()) -> Annotation {
        .pencil(Stroke(id: id, points: points, color: red, lineWidth: width))
    }

    func blur(_ rect: CGRect, id: UUID = UUID()) -> Annotation {
        .blur(Region(id: id, rect: rect), radius: 16)
    }

    func spotlight(_ rect: CGRect, isEllipse: Bool = false, id: UUID = UUID()) -> Annotation {
        .spotlight(SpotlightShape(id: id, rect: rect, isEllipse: isEllipse))
    }

    func counter(at center: CGPoint, diameter: CGFloat = 40, id: UUID = UUID()) -> Annotation {
        .counter(CounterMark(id: id, center: center, number: 1, diameter: diameter, color: red))
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

    /// A stroke is hit within half its width plus the tolerance of its smoothed path, with round
    /// caps, and not in the hollow of a curve. It has no handles, so a drag can only move it.
    @Test func strokeHitWithinWidth() {
        let level = pencil([CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), CGPoint(x: 200, y: 100)])
        #expect(HitTester.handles(for: level).isEmpty)
        // Width 8: 3 px off the path is inside, 5 px is not until the tolerance reaches it.
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 103), tolerance: 0) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 105), tolerance: 0) == nil)
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 105), tolerance: 4) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 109), tolerance: 4) == nil)
        // The round cap reaches 4 px past the last point along the path.
        #expect(HitTester.hit(level, at: CGPoint(x: 203, y: 100), tolerance: 0) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 206, y: 100), tolerance: 0) == nil)

        // The smoothed curve passes through its points; the space under the arch is not the body.
        let arch = pencil([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)])
        #expect(HitTester.hit(arch, at: CGPoint(x: 50, y: 50), tolerance: 0) == .body)
        #expect(HitTester.hit(arch, at: CGPoint(x: 50, y: 10), tolerance: 4) == nil)

        // A highlighter is hit the same way.
        let marker = Annotation.highlighter(Stroke(id: UUID(), points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 80, y: 0)],
                                                   color: EditorPalette.defaultHighlight, lineWidth: 24))
        #expect(HitTester.hit(marker, at: CGPoint(x: 40, y: 11), tolerance: 0) == .body)
        #expect(HitTester.hit(marker, at: CGPoint(x: 40, y: 13), tolerance: 0) == nil)
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

    /// `box` is 200 by 100 with its centre at (200, 100), so the outline's radii are 100 and 50.
    /// With a 4 px stroke and a tolerance of 2, the ring runs from radii (102, 52) down to (94, 44).
    @Test func ellipseHitOnRingNotCentre() {
        let shape = ellipse(box, id: id)
        let tolerance: CGFloat = 2
        // The handles are the bounding box's, as for a rectangle.
        #expect(HitTester.handles(for: shape) == HitTester.handles(for: rectangle(box)))
        #expect(HitTester.hit(shape, at: CGPoint(x: 201, y: 51), tolerance: tolerance) == .handle(1))
        // On the stroke, just outside it (within the tolerance) and just inside it.
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 54), tolerance: tolerance) == .body)
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 51), tolerance: tolerance) == .body)
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 57), tolerance: tolerance) == .body)
        // Beyond the tolerance outside, and inside the hollow: no hit.
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 48), tolerance: tolerance) == nil)
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 62), tolerance: tolerance) == nil)
        #expect(HitTester.hit(shape, at: CGPoint(x: 200, y: 100), tolerance: tolerance) == nil)
        // The bounding box's corner region is outside an ellipse and on a rectangle.
        let corner = CGPoint(x: 296, y: 146)
        #expect(HitTester.hit(shape, at: corner, tolerance: tolerance) == nil)
        #expect(HitTester.hit(rectangle(box), at: corner, tolerance: tolerance) == .body)
        // Too small to have a hollow, it is filled, as it is drawn.
        let dot = ellipse(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(HitTester.hit(dot, at: CGPoint(x: 5, y: 5), tolerance: tolerance) == .body)
        // Handles resize it like a rectangle, keeping id and stroke.
        #expect(HitTester.resized(shape, handle: 4, to: CGPoint(x: 320, y: 170), square: false)
                == ellipse(CGRect(x: 100, y: 50, width: 220, height: 120), id: id))
        #expect(HitTester.resized(shape, handle: 4, to: CGPoint(x: 400, y: 100), square: true)
                == ellipse(CGRect(x: 100, y: 50, width: 300, height: 300), id: id))
        // Moving shifts the rect.
        #expect(shape.moved(by: CGVector(dx: 5, dy: -3)) == ellipse(box.offsetBy(dx: 5, dy: -3), id: id))
    }

    @Test func lineHitWithinWidth() {
        let level = line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), lineWidth: 10, id: id)
        // Within lineWidth / 2 + tolerance = 7 of the segment, which includes a round cap past each end.
        #expect(HitTester.hit(level, at: CGPoint(x: 50, y: 6), tolerance: 2) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 50, y: 8), tolerance: 2) == nil)
        #expect(HitTester.hit(level, at: CGPoint(x: 106, y: 0), tolerance: 2) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: -8, y: 0), tolerance: 2) == nil)
        // A diagonal measures the perpendicular distance: 7 / sqrt(2) = 4.95 in, 10 / sqrt(2) = 7.07 out.
        let diagonal = line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100), lineWidth: 10)
        #expect(HitTester.hit(diagonal, at: CGPoint(x: 50, y: 57), tolerance: 2) == .body)
        #expect(HitTester.hit(diagonal, at: CGPoint(x: 50, y: 60), tolerance: 2) == nil)
        // Two endpoint handles, tail then head, which beat the body.
        #expect(HitTester.handles(for: level) == [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        #expect(HitTester.hit(level, at: CGPoint(x: 99, y: 1), tolerance: 8) == .handle(1))
        #expect(HitTester.hit(level, at: CGPoint(x: 1, y: 1), tolerance: 8) == .handle(0))
        // A moved end keeps id, colour and width; Shift snaps it to 45 degrees around the other end.
        let original = line(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), lineWidth: 6, id: id)
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 120, y: 40), square: false)
                == line(CGPoint(x: 10, y: 10), CGPoint(x: 120, y: 40), lineWidth: 6, id: id))
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 200, y: 15), square: true)
                == line(CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10), lineWidth: 6, id: id))
        // Moving shifts both ends.
        #expect(original.moved(by: CGVector(dx: 5, dy: -3))
                == line(CGPoint(x: 15, y: 7), CGPoint(x: 105, y: 7), lineWidth: 6, id: id))
    }

    /// A spotlight shows nothing inside its hole, so its body is filled, as an effect's is: its
    /// shape grown by the tolerance, with no band. `box` is 200 by 100 about (200, 100).
    @Test func spotlightBodyIsFilled() {
        let tolerance: CGFloat = 2
        let rect = spotlight(box)
        #expect(HitTester.hit(rect, at: CGPoint(x: 200, y: 100), tolerance: tolerance) == .body)
        #expect(HitTester.hit(rect, at: CGPoint(x: 150, y: 48.5), tolerance: tolerance) == .body)
        #expect(HitTester.hit(rect, at: CGPoint(x: 301.5, y: 120), tolerance: tolerance) == .body)
        #expect(HitTester.hit(rect, at: CGPoint(x: 150, y: 47), tolerance: tolerance) == nil)
        #expect(HitTester.hit(rect, at: CGPoint(x: 296, y: 146), tolerance: tolerance) == .body)

        // The ellipse's radii are 100 and 50; at x 230 its edge is at y 52.3.
        let oval = spotlight(box, isEllipse: true)
        #expect(HitTester.hit(oval, at: CGPoint(x: 200, y: 100), tolerance: tolerance) == .body)
        #expect(HitTester.hit(oval, at: CGPoint(x: 230, y: 53), tolerance: tolerance) == .body)
        #expect(HitTester.hit(oval, at: CGPoint(x: 230, y: 51), tolerance: tolerance) == .body)
        #expect(HitTester.hit(oval, at: CGPoint(x: 230, y: 49), tolerance: tolerance) == nil)
        // The bounding box's corner is outside the ellipse, and far enough from its handle.
        #expect(HitTester.hit(oval, at: CGPoint(x: 296, y: 146), tolerance: tolerance) == nil)
    }

    /// A spotlight has the eight box handles of either shape and resizes like a rectangle,
    /// keeping its id and shape.
    @Test func spotlightHandlesResizeItsRect() {
        for isEllipse in [false, true] {
            let shape = spotlight(box, isEllipse: isEllipse, id: id)
            #expect(HitTester.handles(for: shape) == HitTester.boxHandles(box))
            #expect(HitTester.hit(shape, at: CGPoint(x: 101, y: 51), tolerance: 8) == .handle(0))
            #expect(HitTester.hit(shape, at: CGPoint(x: 299, y: 101), tolerance: 8) == .handle(3))
            #expect(HitTester.resized(shape, handle: 4, to: CGPoint(x: 320, y: 170), square: false)
                    == spotlight(CGRect(x: 100, y: 50, width: 220, height: 120), isEllipse: isEllipse, id: id))
            #expect(HitTester.resized(shape, handle: 4, to: CGPoint(x: 400, y: 100), square: true)
                    == spotlight(CGRect(x: 100, y: 50, width: 300, height: 300), isEllipse: isEllipse, id: id))
            #expect(HitTester.resized(shape, handle: 7, to: CGPoint(x: 60, y: 0), square: false)
                    == spotlight(CGRect(x: 60, y: 50, width: 240, height: 100), isEllipse: isEllipse, id: id))
        }
    }

    /// A counter's body is its circle grown by the tolerance. It has no handles: its size comes
    /// from the Size option, so a handle drag changes nothing.
    @Test func counterBodyIsItsCircle() {
        let mark = counter(at: CGPoint(x: 100, y: 100), diameter: 40, id: id)
        let tolerance: CGFloat = 2
        #expect(HitTester.hit(mark, at: CGPoint(x: 100, y: 100), tolerance: tolerance) == .body)
        #expect(HitTester.hit(mark, at: CGPoint(x: 121.5, y: 100), tolerance: tolerance) == .body)
        #expect(HitTester.hit(mark, at: CGPoint(x: 100, y: 78.5), tolerance: tolerance) == .body)
        #expect(HitTester.hit(mark, at: CGPoint(x: 123, y: 100), tolerance: tolerance) == nil)
        // The bounding square's corner is 26.9 px from the centre, outside the circle.
        #expect(HitTester.hit(mark, at: CGPoint(x: 119, y: 119), tolerance: tolerance) == nil)
        #expect(HitTester.handles(for: mark).isEmpty)
        #expect(HitTester.resized(mark, handle: 0, to: CGPoint(x: 0, y: 0), square: false) == mark)
        #expect(HitTester.resized(mark, handle: 4, to: CGPoint(x: 300, y: 300), square: true) == mark)
    }

    // MARK: Spotlights in the hit order (spec 2.12, Editing)

    /// A spotlight ranks last: an arrow inside its hole is picked whichever was made first.
    @Test func anArrowInsideASpotlightIsHitFirst() throws {
        let hole = spotlight(box)
        let shaft = arrow(CGPoint(x: 150, y: 100), CGPoint(x: 250, y: 100))
        for annotations in [[shaft, hole], [hole, shaft]] {
            let found = try #require(HitTester.topmost(in: AnnotationDocument(annotations: annotations),
                                                       at: CGPoint(x: 200, y: 100), tolerance: 8))
            #expect(found.id == shaft.id)
            #expect(found.hit == .body)
        }
    }

    /// Bare image inside a rectangle spotlight, or within the tolerance outside its edge, picks it.
    @Test func bareImageInsideASpotlightHitsItsBody() throws {
        let hole = spotlight(box)
        let elsewhere = arrow(CGPoint(x: 400, y: 400), CGPoint(x: 500, y: 400))
        let document = AnnotationDocument(annotations: [hole, elsewhere])
        for point in [CGPoint(x: 120, y: 70), CGPoint(x: 94, y: 75), CGPoint(x: 250, y: 156)] {
            let found = try #require(HitTester.topmost(in: document, at: point, tolerance: 8), "at \(point)")
            #expect(found.id == hole.id)
            #expect(found.hit == .body)
        }
        #expect(HitTester.topmost(in: document, at: CGPoint(x: 90, y: 75), tolerance: 8) == nil)
    }

    /// Inside an ellipse spotlight a click picks it; in its bounding box's corner, clear of the
    /// corner handle, nothing is hit.
    @Test func anEllipseSpotlightIsHitInsideItsEllipseOnly() throws {
        let oval = spotlight(box, isEllipse: true)
        let document = AnnotationDocument(annotations: [oval])
        let found = try #require(HitTester.topmost(in: document, at: CGPoint(x: 200, y: 100), tolerance: 8))
        #expect(found.id == oval.id)
        #expect(found.hit == .body)
        // 14 px from the handle at (300, 150), and outside the ellipse grown by 8.
        #expect(HitTester.topmost(in: document, at: CGPoint(x: 290, y: 140), tolerance: 8) == nil)
    }

    /// A redaction inside a spotlight is picked by a click on it, whichever was made first.
    @Test func aRedactionInsideASpotlightIsHit() throws {
        let hole = spotlight(box)
        let secret = Annotation.redact(Region(id: UUID(), rect: CGRect(x: 150, y: 75, width: 50, height: 50)), fill: red)
        for annotations in [[secret, hole], [hole, secret]] {
            let found = try #require(HitTester.topmost(in: AnnotationDocument(annotations: annotations),
                                                       at: CGPoint(x: 175, y: 100), tolerance: 8))
            #expect(found.id == secret.id)
            #expect(found.hit == .body)
        }
    }

    /// Every handle is tested before any body, so a spotlight's corner stays grabbable over a blur
    /// made after it.
    @Test func aSpotlightHandleBeatsAnEffectBodyUnderIt() throws {
        let hole = spotlight(box)
        let effect = blur(CGRect(x: 0, y: 0, width: 400, height: 300))
        let found = try #require(HitTester.topmost(in: AnnotationDocument(annotations: [hole, effect]),
                                                   at: CGPoint(x: 103, y: 52), tolerance: 8))
        #expect(found.id == hole.id)
        #expect(found.hit == .handle(0))
        // Away from the handles the blur's body is in front of the spotlight's.
        #expect(HitTester.topmost(in: AnnotationDocument(annotations: [hole, effect]),
                                  at: CGPoint(x: 200, y: 100), tolerance: 8)?.id == effect.id)
    }
}
