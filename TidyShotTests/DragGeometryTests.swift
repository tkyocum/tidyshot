import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct DragGeometryTests {
    let start = CGPoint(x: 100, y: 100)

    /// Shift makes both sides the longer one, and the square grows toward the pointer in each axis.
    @Test func squareKeepsSignPerQuadrant() {
        func square(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            DragGeometry.rect(from: start, to: CGPoint(x: x, y: y), square: true, fromCentre: false)
        }
        #expect(square(130, 110) == CGRect(x: 100, y: 100, width: 30, height: 30))
        #expect(square(70, 110) == CGRect(x: 70, y: 100, width: 30, height: 30))
        #expect(square(90, 60) == CGRect(x: 60, y: 60, width: 40, height: 40))
        #expect(square(140, 80) == CGRect(x: 100, y: 60, width: 40, height: 40))
        // Without Shift the rect follows the pointer, standardized for drags up and to the left.
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 130, y: 110), square: false, fromCentre: false)
                == CGRect(x: 100, y: 100, width: 30, height: 10))
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 70, y: 60), square: false, fromCentre: false)
                == CGRect(x: 70, y: 60, width: 30, height: 40))
    }

    /// Option draws from the centre: the pointer's offset is mirrored on the other side.
    @Test func fromCentreMirrors() {
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 130, y: 110), square: false, fromCentre: true)
                == CGRect(x: 70, y: 90, width: 60, height: 20))
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 70, y: 90), square: false, fromCentre: true)
                == CGRect(x: 70, y: 90, width: 60, height: 20))
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 130, y: 110), square: true, fromCentre: true)
                == CGRect(x: 70, y: 70, width: 60, height: 60))
        #expect(DragGeometry.rect(from: start, to: start, square: false, fromCentre: true)
                == CGRect(x: 100, y: 100, width: 0, height: 0))
    }

    /// The end is projected onto the nearest of the eight 45-degree directions around the start.
    @Test func snap45ToNearestOctant() {
        func snapped(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            DragGeometry.segmentEnd(from: start, to: CGPoint(x: x, y: y), snap45: true)
        }
        #expect(snapped(200, 110) == CGPoint(x: 200, y: 100))   // right
        #expect(snapped(10, 101) == CGPoint(x: 10, y: 100))     // left
        #expect(snapped(110, 30) == CGPoint(x: 100, y: 30))     // up (image y grows downward)
        #expect(snapped(160, 140) == CGPoint(x: 150, y: 150))   // down and right
        #expect(snapped(40, 170) == CGPoint(x: 35, y: 165))     // down and left
        #expect(snapped(30, 40) == CGPoint(x: 35, y: 35))       // up and left
        #expect(snapped(170, 20) == CGPoint(x: 175, y: 25))     // up and right
        #expect(DragGeometry.segmentEnd(from: start, to: CGPoint(x: 160, y: 140), snap45: false) == CGPoint(x: 160, y: 140))
        #expect(DragGeometry.segmentEnd(from: start, to: start, snap45: true) == start)
    }

    /// Shift during a move keeps the larger component of the total delta; a tie keeps horizontal.
    @Test func axisLockKeepsDominant() {
        #expect(DragGeometry.axisLocked(CGVector(dx: 12, dy: -5)) == CGVector(dx: 12, dy: 0))
        #expect(DragGeometry.axisLocked(CGVector(dx: 3, dy: -9)) == CGVector(dx: 0, dy: -9))
        #expect(DragGeometry.axisLocked(CGVector(dx: -4, dy: 4)) == CGVector(dx: -4, dy: 0))
        #expect(DragGeometry.axisLocked(CGVector(dx: 0, dy: 0)) == CGVector(dx: 0, dy: 0))
    }

    /// The minimum is 2 view points: 2 / zoom image pixels in each dimension for a rect, and in
    /// length for a segment.
    @Test func tinyDragRejectedRelativeToZoom() {
        #expect(!DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 1.5, height: 40), zoom: 1))
        #expect(!DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 40, height: 1), zoom: 1))
        #expect(DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 2, height: 2), zoom: 1))
        // A 2x capture at its natural size: 2 points are 4 pixels.
        #expect(!DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 3, height: 40), zoom: 0.5))
        #expect(DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 4, height: 4), zoom: 0.5))
        // Zoomed in to 4, half a pixel is enough.
        #expect(DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), zoom: 4))
        // A negative size counts by its magnitude.
        #expect(DragGeometry.isLargeEnough(CGRect(x: 10, y: 10, width: -5, height: -5), zoom: 1))
        // A segment counts by its length, so a horizontal arrow (zero height) is kept.
        #expect(DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 3, y: 0), zoom: 1))
        #expect(!DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 1, y: 1), zoom: 1))
        #expect(!DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 3, y: 0), zoom: 0.5))
        #expect(DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 0, y: 0.6), zoom: 4))
    }
}
