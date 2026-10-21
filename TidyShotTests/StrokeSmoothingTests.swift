import CoreGraphics
import Testing
@testable import TidyShot

struct StrokeSmoothingTests {
    /// Distance is measured from the last point kept, so a slow drift still adds points; the last
    /// sample always stays, so the stroke ends where the pointer did.
    @Test func decimationDropsClosePoints() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 3, y: 0),
                    CGPoint(x: 3.4, y: 0), CGPoint(x: 10, y: 0)]
        #expect(StrokeSmoothing.decimated(line, minDistance: 2)
                == [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0), CGPoint(x: 10, y: 0)])

        // 1 and 2 are under 2.5 from the point kept (0) even though each is 1 from its neighbour; 3 is not.
        let drift = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 0)]
        #expect(StrokeSmoothing.decimated(drift, minDistance: 2.5) == [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0)])

        // A last sample closer than the minimum is kept anyway.
        let tail = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 5.5, y: 0)]
        #expect(StrokeSmoothing.decimated(tail, minDistance: 2) == tail)

        #expect(StrokeSmoothing.decimated([], minDistance: 2) == [])
        #expect(StrokeSmoothing.decimated([CGPoint(x: 4, y: 4)], minDistance: 2) == [CGPoint(x: 4, y: 4)])
    }

    /// The curve starts and ends on the first and last point, passes through every other point, and
    /// has `segmentsPerSpan` samples per span. Fewer than three points are returned as they are.
    @Test func smoothingKeepsEndpoints() {
        let corner = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 10), CGPoint(x: 40, y: 40)]
        let curve = StrokeSmoothing.catmullRom(corner)
        #expect(curve.first == corner.first)
        #expect(curve.last == corner.last)
        #expect(curve.count == 1 + (corner.count - 1) * StrokeSmoothing.segmentsPerSpan)
        #expect(curve.contains(corner[1]))
        #expect(curve.contains(corner[2]))

        #expect(StrokeSmoothing.catmullRom([]) == [])
        #expect(StrokeSmoothing.catmullRom([corner[0]]) == [corner[0]])
        #expect(StrokeSmoothing.catmullRom([corner[0], corner[3]]) == [corner[0], corner[3]])

        // Equally spaced points on a level line stay on it.
        let level = [CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), CGPoint(x: 30, y: 5)]
        #expect(StrokeSmoothing.catmullRom(level).allSatisfy { $0.y == 5 })
    }
}
