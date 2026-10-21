import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct ArrowGeometryTests {
    let halfAngle = 28 * CGFloat.pi / 180

    func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 1e-6
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    @Test func headSymmetricAboutShaft() {
        // Length 125 along (0.8, 0.6); the head is max(12 * 2, 4 * 4) = 24 long.
        let from = CGPoint(x: 10, y: 20)
        let to = CGPoint(x: 110, y: 95)
        let head = ArrowGeometry.head(from: from, to: to, lineWidth: 4, scale: 2)
        #expect(head.tip == to)
        #expect(abs(distance(head.tip, head.left) - distance(head.tip, head.right)) < 1e-9)
        // The base's midpoint is on the shaft, 24 px back from the tip, and the base is square to it.
        let middle = CGPoint(x: (head.left.x + head.right.x) / 2, y: (head.left.y + head.right.y) / 2)
        #expect(near(middle, CGPoint(x: 110 - 0.8 * 24, y: 95 - 0.6 * 24)))
        #expect(abs((head.right.x - head.left.x) * 0.8 + (head.right.y - head.left.y) * 0.6) < 1e-9)
        // Pointing right, left is up, because image y grows downward.
        let flat = ArrowGeometry.head(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), lineWidth: 8, scale: 2)
        #expect(flat.left.y < 100 && flat.right.y > 100)
        #expect(abs(flat.left.x - 168) < 1e-9 && abs(flat.right.x - 168) < 1e-9)
    }

    /// Length max(12 * scale, 4 * lineWidth), half-angle 28 degrees.
    @Test func headScalesWithLineWidthAndScale() {
        let cases: [(lineWidth: CGFloat, scale: CGFloat, expected: CGFloat)] = [
            (2, 1, 12), (4, 1, 16), (2, 2, 24), (8, 2, 32), (24, 2, 96),
        ]
        for item in cases {
            let to = CGPoint(x: 400, y: 0)
            let head = ArrowGeometry.head(from: .zero, to: to, lineWidth: item.lineWidth, scale: item.scale)
            #expect(abs((400 - head.left.x) - item.expected) < 1e-9)
            #expect(abs(ArrowGeometry.headLength(from: .zero, to: to, lineWidth: item.lineWidth, scale: item.scale) - item.expected) < 1e-9)
            #expect(abs(atan2(abs(head.left.y), 400 - head.left.x) - halfAngle) < 1e-9)
        }
    }

    @Test func shaftStopsBeforeTip() {
        let from = CGPoint(x: 0, y: 100)
        let to = CGPoint(x: 200, y: 100)
        let head = ArrowGeometry.head(from: from, to: to, lineWidth: 8, scale: 2)
        let end = ArrowGeometry.shaftEnd(from: from, to: to, lineWidth: 8, scale: 2)
        // Half of the 32 px head back from the tip: past the head's base, short of the tip.
        #expect(near(end, CGPoint(x: 184, y: 100)))
        #expect(end.x > head.left.x && end.x < head.tip.x)
        // The 4 px round cap stays inside the triangle.
        #expect(HitTester.distance(from: end, toSegment: head.tip, head.left) >= 4)
        #expect(HitTester.distance(from: end, toSegment: head.tip, head.right) >= 4)
        // An arrow shorter than its head: the head shrinks to the arrow and the shaft stops halfway.
        let short = ArrowGeometry.head(from: .zero, to: CGPoint(x: 10, y: 0), lineWidth: 8, scale: 2)
        #expect(abs(short.left.x) < 1e-9 && abs(short.right.x) < 1e-9)
        #expect(near(ArrowGeometry.shaftEnd(from: .zero, to: CGPoint(x: 10, y: 0), lineWidth: 8, scale: 2), CGPoint(x: 5, y: 0)))
        // A zero-length arrow collapses to its tip.
        let point = CGPoint(x: 7, y: 7)
        let collapsed = ArrowGeometry.head(from: point, to: point, lineWidth: 8, scale: 2)
        #expect(collapsed.tip == point && collapsed.left == point && collapsed.right == point)
        #expect(ArrowGeometry.shaftEnd(from: point, to: point, lineWidth: 8, scale: 2) == point)
    }

    @Test func boundsContainHead() {
        let red = EditorPalette.defaultStroke
        let flat = Segment(id: UUID(), from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), color: red, lineWidth: 8)
        let diagonal = Segment(id: UUID(), from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20), color: red, lineWidth: 6)
        for segment in [flat, diagonal] {
            let bounds = AnnotationGeometry.bounds(of: .arrow(segment), scale: 2)
            let head = ArrowGeometry.head(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: 2)
            for point in [head.tip, head.left, head.right] {
                #expect(bounds.contains(point))
            }
            // The tail's round cap.
            let cap = segment.lineWidth / 2
            #expect(bounds.contains(CGRect(x: segment.from.x - cap, y: segment.from.y - cap, width: 2 * cap, height: 2 * cap)))
        }
        // The head is wider than the shaft: about 17 px each side of a flat 8 px arrow.
        #expect(AnnotationGeometry.bounds(of: .arrow(flat), scale: 2).minY < 100 - 17)
        // A rectangle's stroke sits inside its rect, and an effect paints its rect.
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let margin = AnnotationGeometry.antialiasMargin
        #expect(AnnotationGeometry.bounds(of: .rectangle(ShapeBox(id: UUID(), rect: rect, color: red, lineWidth: 4)), scale: 2)
                == rect.insetBy(dx: -margin, dy: -margin))
        #expect(AnnotationGeometry.bounds(of: .blur(Region(id: UUID(), rect: rect), radius: 16), scale: 2)
                == rect.insetBy(dx: -margin, dy: -margin))
    }
}
