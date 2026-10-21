import CoreGraphics
import Testing
@testable import TidyShot

struct SelectionAdjustTests {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    /// minX 100, maxX 500, minY 100, maxY 300, in the view's coordinates (y up). Ratio 2.
    let rect = CGRect(x: 100, y: 100, width: 400, height: 200)
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func resize(_ handle: SelectionHandle, to x: CGFloat, _ y: CGFloat, from start: CGRect? = nil,
                ratio: CGFloat? = nil) -> CGRect {
        SelectionAdjust.resized(start ?? rect, handle: handle, to: CGPoint(x: x, y: y), lockedRatio: ratio,
                                bounds: bounds, minSide: SelectionAdjust.minSide)
    }

    func hit(_ x: CGFloat, _ y: CGFloat, on target: CGRect? = nil) -> SelectionHandle? {
        SelectionAdjust.handle(at: CGPoint(x: x, y: y), rect: target ?? rect, tolerance: SelectionAdjust.handleTolerance)
    }

    @Test func eachHandleIsFoundAtItsCornerOrEdge() {
        #expect(hit(100, 300) == .topLeft)
        #expect(hit(300, 300) == .top)
        #expect(hit(500, 300) == .topRight)
        #expect(hit(500, 200) == .right)
        #expect(hit(500, 100) == .bottomRight)
        #expect(hit(300, 100) == .bottom)
        #expect(hit(100, 100) == .bottomLeft)
        #expect(hit(100, 200) == .left)
        #expect(hit(300, 200) == .inside)
        // Within the tolerance, outside the rect, and anywhere along an edge.
        #expect(hit(95, 305) == .topLeft)
        #expect(hit(200, 304) == .top)
        #expect(hit(504, 150) == .right)
        // Beyond the tolerance: a new rect.
        #expect(hit(300, 307) == nil)
        #expect(hit(50, 200) == nil)
        #expect(hit(600, 600) == nil)
    }

    /// Both sides of an 8 pt wide rect are within 6 pt of the middle; the nearer one wins.
    @Test func aNarrowRectGivesTheNearerSide() {
        let narrow = CGRect(x: 100, y: 100, width: 8, height: 200)
        #expect(hit(101, 200, on: narrow) == .left)
        #expect(hit(107, 200, on: narrow) == .right)
        #expect(hit(107, 299, on: narrow) == .topRight)
    }

    @Test func handlePointsSitOnCornersAndEdgeMidpoints() throws {
        #expect(SelectionHandle.resizeHandles.count == 8)
        #expect(!SelectionHandle.resizeHandles.contains(.inside))
        #expect(SelectionHandle.topLeft.point(on: rect) == CGPoint(x: 100, y: 300))
        #expect(SelectionHandle.top.point(on: rect) == CGPoint(x: 300, y: 300))
        #expect(SelectionHandle.right.point(on: rect) == CGPoint(x: 500, y: 200))
        #expect(SelectionHandle.bottomLeft.point(on: rect) == CGPoint(x: 100, y: 100))
        #expect(SelectionHandle.inside.point(on: rect) == nil)
        for handle in SelectionHandle.resizeHandles {
            let point = try #require(handle.point(on: rect))
            #expect(SelectionAdjust.handle(at: point, rect: rect, tolerance: 6) == handle)
        }
    }

    @Test func eachHandleMovesOnlyItsEdges() {
        #expect(resize(.right, to: 600, 0) == CGRect(x: 100, y: 100, width: 500, height: 200))
        #expect(resize(.left, to: 50, 999) == CGRect(x: 50, y: 100, width: 450, height: 200))
        #expect(resize(.top, to: 999, 350) == CGRect(x: 100, y: 100, width: 400, height: 250))
        #expect(resize(.bottom, to: 0, 40) == CGRect(x: 100, y: 40, width: 400, height: 260))
        #expect(resize(.topRight, to: 600, 350) == CGRect(x: 100, y: 100, width: 500, height: 250))
        #expect(resize(.bottomLeft, to: 50, 40) == CGRect(x: 50, y: 40, width: 450, height: 260))
        #expect(resize(.topLeft, to: 50, 350) == CGRect(x: 50, y: 100, width: 450, height: 250))
        #expect(resize(.bottomRight, to: 600, 40) == CGRect(x: 100, y: 40, width: 500, height: 260))
        #expect(resize(.inside, to: 600, 40) == rect)
    }

    /// Dragging an edge past the opposite one stops 4 pt short of it; the rect never flips.
    @Test func resizingStopsAtTheMinimumSide() {
        #expect(resize(.right, to: 50, 200) == CGRect(x: 100, y: 100, width: 4, height: 200))
        #expect(resize(.top, to: 300, 0) == CGRect(x: 100, y: 100, width: 400, height: 4))
        #expect(resize(.bottomLeft, to: 900, 800) == CGRect(x: 496, y: 296, width: 4, height: 4))
    }

    @Test func resizingIsClampedToTheBounds() {
        #expect(resize(.right, to: 2000, 200) == CGRect(x: 100, y: 100, width: 1340, height: 200))
        #expect(resize(.topLeft, to: -50, 1000) == CGRect(x: 0, y: 100, width: 500, height: 800))
        #expect(resize(.bottom, to: 300, -300) == CGRect(x: 100, y: 0, width: 400, height: 300))
    }

    /// A corner takes the larger of the two directions, so the rect reaches the pointer.
    @Test func aLockedCornerKeepsTheRatio() {
        #expect(resize(.bottomRight, to: 600, 40, ratio: 2) == CGRect(x: 100, y: 40, width: 520, height: 260))
        #expect(resize(.topLeft, to: 300, 250, ratio: 2) == CGRect(x: 200, y: 100, width: 300, height: 150))
    }

    @Test func aLockedEdgeGrowsTheOtherSideAboutTheCentre() {
        #expect(resize(.right, to: 700, 123, ratio: 2) == CGRect(x: 100, y: 50, width: 600, height: 300))
        #expect(resize(.top, to: 77, 400, ratio: 2) == CGRect(x: 0, y: 100, width: 600, height: 300))
    }

    @Test func aLockedResizeStopsAtTheBounds() {
        // The corner runs out of room to the right first; the ratio holds.
        let nearRight = CGRect(x: 1000, y: 100, width: 400, height: 200)
        #expect(resize(.bottomRight, to: 1500, -100, from: nearRight, ratio: 2)
                == CGRect(x: 1000, y: 80, width: 440, height: 220))
        // An edge near the top: the centred side would leave the screen and moves inside it.
        let nearTop = CGRect(x: 100, y: 600, width: 400, height: 200)
        #expect(resize(.right, to: 1100, 700, from: nearTop, ratio: 2)
                == CGRect(x: 100, y: 400, width: 1000, height: 500))
    }

    @Test func aLockedResizeKeepsTheMinimumSide() {
        #expect(resize(.bottomRight, to: 101, 299, ratio: 2) == CGRect(x: 100, y: 296, width: 8, height: 4))
    }

    @Test func insideMovesTheRectAndClampsAtEachEdge() {
        func move(_ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            SelectionAdjust.moved(rect, by: CGVector(dx: dx, dy: dy), bounds: bounds)
        }
        #expect(move(50, -30) == CGRect(x: 150, y: 70, width: 400, height: 200))
        #expect(move(-500, 0) == CGRect(x: 0, y: 100, width: 400, height: 200))
        #expect(move(5000, 0) == CGRect(x: 1040, y: 100, width: 400, height: 200))
        #expect(move(0, -500) == CGRect(x: 100, y: 0, width: 400, height: 200))
        #expect(move(0, 5000) == CGRect(x: 100, y: 700, width: 400, height: 200))
        // Fractions round to whole points.
        #expect(move(0.4, 0.6) == CGRect(x: 100, y: 101, width: 400, height: 200))
    }

    @Test func arrowsNudgeByOneOrTenAndStopAtTheEdge() {
        func nudge(_ key: SelectionAdjust.Arrow, shift: Bool = false, _ start: CGRect? = nil) -> CGRect {
            SelectionAdjust.nudged(start ?? rect, key: key, shift: shift, bounds: bounds)
        }
        #expect(nudge(.left) == CGRect(x: 99, y: 100, width: 400, height: 200))
        #expect(nudge(.right, shift: true) == CGRect(x: 110, y: 100, width: 400, height: 200))
        // Up is +y in the view's coordinates.
        #expect(nudge(.up) == CGRect(x: 100, y: 101, width: 400, height: 200))
        #expect(nudge(.down, shift: true) == CGRect(x: 100, y: 90, width: 400, height: 200))
        let corner = CGRect(x: 0, y: 0, width: 400, height: 200)
        #expect(nudge(.left, corner) == corner)
        #expect(nudge(.down, shift: true, corner) == corner)
    }

    @Test func keysMapToCommands() {
        #expect(SelectionAdjust.keyCommand(keyCode: 53, hasRect: false) == .cancel)
        #expect(SelectionAdjust.keyCommand(keyCode: 53, hasRect: true) == .cancel)
        #expect(SelectionAdjust.keyCommand(keyCode: 36, hasRect: true) == .capture)
        #expect(SelectionAdjust.keyCommand(keyCode: 76, hasRect: true) == .capture)
        #expect(SelectionAdjust.keyCommand(keyCode: 36, hasRect: false) == nil)
        #expect(SelectionAdjust.keyCommand(keyCode: 123, hasRect: true) == .nudge(.left))
        #expect(SelectionAdjust.keyCommand(keyCode: 124, hasRect: true) == .nudge(.right))
        #expect(SelectionAdjust.keyCommand(keyCode: 125, hasRect: true) == .nudge(.down))
        #expect(SelectionAdjust.keyCommand(keyCode: 126, hasRect: true) == .nudge(.up))
        #expect(SelectionAdjust.keyCommand(keyCode: 126, hasRect: false) == nil)
        // A, and Tab: not the overlay's.
        #expect(SelectionAdjust.keyCommand(keyCode: 0, hasRect: true) == nil)
        #expect(SelectionAdjust.keyCommand(keyCode: 48, hasRect: true) == nil)
    }

    @Test func typedSizeGrowsFromTheTopLeft() {
        #expect(SelectionAdjust.sized(rect, width: 600, height: nil, lockedRatio: nil, bounds: bounds)
                == CGRect(x: 100, y: 100, width: 600, height: 200))
        // The top edge (maxY 300) stays; the bottom moves.
        #expect(SelectionAdjust.sized(rect, width: nil, height: 250, lockedRatio: nil, bounds: bounds)
                == CGRect(x: 100, y: 50, width: 400, height: 250))
        #expect(SelectionAdjust.sized(rect, width: 300, height: 100, lockedRatio: nil, bounds: bounds)
                == CGRect(x: 100, y: 200, width: 300, height: 100))
    }

    @Test func typedSizeIsClampedAndMovedInside() {
        let nearRight = CGRect(x: 1000, y: 100, width: 400, height: 200)
        func size(_ width: CGFloat?, _ height: CGFloat?) -> CGRect {
            SelectionAdjust.sized(nearRight, width: width, height: height, lockedRatio: nil, bounds: bounds)
        }
        #expect(size(600, nil) == CGRect(x: 840, y: 100, width: 600, height: 200))
        #expect(size(2000, nil) == CGRect(x: 0, y: 100, width: 1440, height: 200))
        #expect(size(nil, 1000) == CGRect(x: 1000, y: 0, width: 400, height: 900))
        #expect(size(0, nil) == CGRect(x: 1000, y: 100, width: 4, height: 200))
    }

    @Test func typedSizeWithTheLockChangesTheOtherSide() {
        func size(_ width: CGFloat?, _ height: CGFloat?) -> CGRect {
            SelectionAdjust.sized(rect, width: width, height: height, lockedRatio: 2, bounds: bounds)
        }
        #expect(size(600, nil) == CGRect(x: 100, y: 0, width: 600, height: 300))
        #expect(size(nil, 100) == CGRect(x: 100, y: 200, width: 200, height: 100))
        // Both given: the width wins.
        #expect(size(600, 50) == CGRect(x: 100, y: 0, width: 600, height: 300))
        // Too large for the screen: both sides shrink together, then the rect moves inside.
        #expect(size(2000, nil) == CGRect(x: 0, y: 0, width: 1440, height: 720))
        // Below the minimum: the short side is 4 pt.
        #expect(size(0, nil) == CGRect(x: 100, y: 296, width: 8, height: 4))
    }

    @Test func restoreKeepsARectOnItsDisplay() {
        #expect(SelectionAdjust.restored(rect, displayFrames: [main, right]) == rect)
        let second = CGRect(x: 2000, y: 500, width: 300, height: 300)
        #expect(SelectionAdjust.restored(second, displayFrames: [main, right]) == second)
        // Across two displays: the display holding the centre keeps its part.
        #expect(SelectionAdjust.restored(CGRect(x: 1300, y: 100, width: 400, height: 200), displayFrames: [main, right])
                == CGRect(x: 1440, y: 100, width: 260, height: 200))
        // A display above the main one (AppKit y up); fractions round.
        let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
        #expect(SelectionAdjust.restored(CGRect(x: 10.4, y: 1000.6, width: 99.8, height: 50), displayFrames: [main, above])
                == CGRect(x: 10, y: 1001, width: 100, height: 50))
    }

    @Test func restoreRefusesARectOffEveryDisplay() {
        // The display it was on is gone.
        #expect(SelectionAdjust.restored(CGRect(x: 2000, y: 100, width: 400, height: 200), displayFrames: [main]) == nil)
        // The centre is on the second display, with 3 pt of the rect on it.
        #expect(SelectionAdjust.restored(CGRect(x: 1437, y: 100, width: 6, height: 200), displayFrames: [main, right]) == nil)
        #expect(SelectionAdjust.restored(CGRect(x: 100, y: 100, width: 3, height: 200), displayFrames: [main]) == nil)
        #expect(SelectionAdjust.restored(.null, displayFrames: [main]) == nil)
        #expect(SelectionAdjust.restored(rect, displayFrames: []) == nil)
    }
}
