import CoreGraphics
import Testing
@testable import TidyShot

/// Where the bubble starts, how a drag and a size step move it, and what is remembered (design,
/// Webcam bubble, Where it starts, and memory; plan Gap 14).
struct BubblePlacementTests {
    let recorded = CGRect(x: 0, y: 0, width: 1000, height: 800)

    /// Every edge of `frame` inside `rect`.
    func isInside(_ frame: CGRect, _ rect: CGRect) -> Bool {
        frame.minX >= rect.minX && frame.maxX <= rect.maxX
            && frame.minY >= rect.minY && frame.maxY <= rect.maxY
    }

    // MARK: Sizes

    @Test func theDiameters() {
        #expect(BubbleSize.small.diameter == 120)
        #expect(BubbleSize.medium.diameter == 180)
        #expect(BubbleSize.large.diameter == 260)
    }

    @Test func theTitles() {
        #expect(BubbleSize.allCases.map(\.title) == ["Small", "Medium", "Large"])
    }

    @Test func theStepOrder() {
        #expect(BubbleSize.small.next == .medium)
        #expect(BubbleSize.medium.next == .large)
        #expect(BubbleSize.large.next == .small)
    }

    @Test(arguments: [
        ("small", BubbleSize.small), ("medium", .medium), ("large", .large),
        ("huge", .medium), ("", .medium),
    ])
    func storedSizes(stored: String, size: BubbleSize) {
        #expect(BubbleSize(stored: stored) == size)
    }

    // MARK: Insets

    @Test func theStandardInsets() {
        #expect(BubbleInsets.standard == BubbleInsets(right: 16, bottom: 16))
    }

    @Test(arguments: [(-4.0, 16.0), (.nan, 16), (.infinity, 16), (-.infinity, 16), (24, 24), (0, 0)])
    func readingAStoredInset(value: Double, reads: Double) {
        #expect(BubbleInsets.reading(value) == CGFloat(reads))
    }

    // MARK: The start

    @Test(arguments: [
        (BubbleSize.small, CGRect(x: 864, y: 16, width: 120, height: 120)),
        (.medium, CGRect(x: 804, y: 16, width: 180, height: 180)),
        (.large, CGRect(x: 724, y: 16, width: 260, height: 260)),
    ])
    func theDefaultFrameSits16PointsFromTheRightAndBottom(size: BubbleSize, frame: CGRect) {
        let placed = BubblePlacement.frame(recorded: recorded, size: size, insets: .standard)
        #expect(placed == frame)
        #expect(recorded.maxX - placed.maxX == 16)
        #expect(placed.minY - recorded.minY == 16)
    }

    @Test func storedInsetsPlaceIt() {
        let insets = BubbleInsets(right: 300, bottom: 200)
        let placed = BubblePlacement.frame(recorded: recorded, size: .medium, insets: insets)
        #expect(placed == CGRect(x: 520, y: 200, width: 180, height: 180))
    }

    /// An area away from the origin: the insets count from its own edges.
    @Test func theInsetsCountFromTheRecordedRect() {
        let area = CGRect(x: 1600, y: 300, width: 640, height: 480)
        let placed = BubblePlacement.frame(recorded: area, size: .small, insets: .standard)
        #expect(placed == CGRect(x: 2104, y: 316, width: 120, height: 120))
    }

    /// Insets the next, smaller area cannot hold are clamped, and the clamp is not stored.
    @Test func storedInsetsAreClampedInASmallRect() {
        let small = CGRect(x: 100, y: 100, width: 400, height: 300)
        let insets = BubbleInsets(right: 700, bottom: 600)
        let placed = BubblePlacement.frame(recorded: small, size: .medium, insets: insets)
        #expect(placed == CGRect(x: 100, y: 220, width: 180, height: 180))
        #expect(isInside(placed, small))
        #expect(BubblePlacement.storedInsets(after: .start, frame: placed, recorded: small) == nil)
    }

    @Test func aRectSmallerThanTheBubbleCentresIt() {
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 100)
        let placed = BubblePlacement.frame(recorded: tiny, size: .medium, insets: .standard)
        #expect(placed == CGRect(x: -40, y: -40, width: 180, height: 180))
    }

    /// Too narrow but tall enough: centred across, clamped up and down.
    @Test func aRectSmallerInOneDimensionCentresOnlyThatOne() {
        let narrow = CGRect(x: 0, y: 0, width: 100, height: 800)
        let placed = BubblePlacement.frame(recorded: narrow, size: .medium, insets: .standard)
        #expect(placed == CGRect(x: -40, y: 16, width: 180, height: 180))
    }

    /// Fullscreen places the bubble in the display's visible frame, above the Dock.
    @Test func fullscreenUsesTheVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 70, width: 1512, height: 874)
        let placed = BubblePlacement.frame(recorded: visibleFrame, size: .large, insets: .standard)
        #expect(placed == CGRect(x: 1236, y: 86, width: 260, height: 260))
        #expect(isInside(placed, visibleFrame))
    }

    // MARK: Clamp

    @Test func aFrameInsideIsUnchanged() {
        let frame = CGRect(x: 400, y: 300, width: 180, height: 180)
        #expect(BubblePlacement.clamp(frame, into: recorded) == frame)
    }

    @Test(arguments: [
        (CGRect(x: -50, y: 300, width: 180, height: 180), CGRect(x: 0, y: 300, width: 180, height: 180)),
        (CGRect(x: 900, y: 300, width: 180, height: 180), CGRect(x: 820, y: 300, width: 180, height: 180)),
        (CGRect(x: 400, y: -30, width: 180, height: 180), CGRect(x: 400, y: 0, width: 180, height: 180)),
        (CGRect(x: 400, y: 700, width: 180, height: 180), CGRect(x: 400, y: 620, width: 180, height: 180)),
    ])
    func aFrameOverAnEdgeIsPulledIn(frame: CGRect, clamped: CGRect) {
        #expect(BubblePlacement.clamp(frame, into: recorded) == clamped)
    }

    // MARK: Drag

    @Test func aDragMovesByThePointersTravel() {
        let start = CGRect(x: 804, y: 16, width: 180, height: 180)
        let moved = BubblePlacement.drag(startFrame: start, from: CGPoint(x: 900, y: 100),
                                         to: CGPoint(x: 600, y: 400), in: recorded)
        #expect(moved == CGRect(x: 504, y: 316, width: 180, height: 180))
    }

    @Test func aDragStopsAtTheEdge() {
        let start = CGRect(x: 804, y: 16, width: 180, height: 180)
        let moved = BubblePlacement.drag(startFrame: start, from: CGPoint(x: 900, y: 100),
                                         to: CGPoint(x: 1400, y: 100), in: recorded)
        #expect(moved == CGRect(x: 820, y: 16, width: 180, height: 180))
    }

    /// Far past every corner, the whole bubble stays inside.
    @Test(arguments: [
        CGPoint(x: -5000, y: -5000), CGPoint(x: 5000, y: -5000),
        CGPoint(x: -5000, y: 5000), CGPoint(x: 5000, y: 5000),
    ])
    func aDragsClampKeepsEveryEdgeInside(to point: CGPoint) {
        let start = CGRect(x: 400, y: 300, width: 260, height: 260)
        let moved = BubblePlacement.drag(startFrame: start, from: CGPoint(x: 500, y: 400),
                                         to: point, in: recorded)
        #expect(isInside(moved, recorded))
        #expect(moved.size == start.size)
    }

    // MARK: Size step

    @Test func aStepKeepsTheCentre() {
        let frame = CGRect(x: 400, y: 300, width: 120, height: 120)
        let stepped = BubblePlacement.step(frame, to: .medium, in: recorded)
        #expect(stepped == CGRect(x: 370, y: 270, width: 180, height: 180))
        #expect(stepped.midX == frame.midX && stepped.midY == frame.midY)
    }

    /// The default Small bubble's centre (924, 76) as Medium crosses the right and bottom edges.
    @Test func aStepAgainstTheEdgeIsClamped() {
        let small = BubblePlacement.frame(recorded: recorded, size: .small, insets: .standard)
        #expect(small.midX == 924 && small.midY == 76)
        let stepped = BubblePlacement.step(small, to: .medium, in: recorded)
        #expect(stepped == CGRect(x: 820, y: 0, width: 180, height: 180))
    }

    @Test func aStepDownToSmallKeepsTheCentre() {
        let large = CGRect(x: 400, y: 300, width: 260, height: 260)
        let stepped = BubblePlacement.step(large, to: .small, in: recorded)
        #expect(stepped == CGRect(x: 470, y: 370, width: 120, height: 120))
    }

    // MARK: Memory

    @Test func theInsetsOfAFrame() {
        let frame = CGRect(x: 504, y: 316, width: 180, height: 180)
        #expect(BubblePlacement.insets(of: frame, in: recorded) == BubbleInsets(right: 316, bottom: 316))
    }

    @Test func theInsetsWrittenBackAfterADrag() {
        let frame = CGRect(x: 504, y: 316, width: 180, height: 180)
        #expect(BubblePlacement.storedInsets(after: .dragEnded, frame: frame, recorded: recorded)
            == BubbleInsets(right: 316, bottom: 316))
    }

    /// A Small, Medium, Large, Small walk of size steps from the default place, clamped against
    /// the right and bottom edges on the way: the stored insets stay 16, 16 throughout, so the
    /// next start puts Small back where it began.
    @Test func aWalkOfStepsAgainstAnEdgeLeavesTheStoredInsets() {
        var stored = BubbleInsets.standard
        var frame = BubblePlacement.frame(recorded: recorded, size: .small, insets: stored)
        for size in [BubbleSize.medium, .large, .small] {
            frame = BubblePlacement.step(frame, to: size, in: recorded)
            if let insets = BubblePlacement.storedInsets(after: .sizeStepped, frame: frame,
                                                         recorded: recorded) {
                stored = insets
            }
            #expect(stored == .standard)
        }
        #expect(frame != CGRect(x: 864, y: 16, width: 120, height: 120))
        #expect(BubblePlacement.frame(recorded: recorded, size: .small, insets: stored)
            == CGRect(x: 864, y: 16, width: 120, height: 120))
    }

    /// A drag that ends against an edge is where the user left it, so it is written back.
    @Test func aDragAgainstTheEdgeIsWrittenBack() {
        let start = CGRect(x: 804, y: 16, width: 180, height: 180)
        let moved = BubblePlacement.drag(startFrame: start, from: CGPoint(x: 900, y: 100),
                                         to: CGPoint(x: 1400, y: 100), in: recorded)
        #expect(BubblePlacement.storedInsets(after: .dragEnded, frame: moved, recorded: recorded)
            == BubbleInsets(right: 0, bottom: 16))
    }

    /// A size step writes the size only, even one clear of every edge.
    @Test(arguments: [BubblePlacement.Move.start, .reclamp, .sizeStepped])
    func noInsetsAreWrittenAfterAStartAReclampOrAStep(move: BubblePlacement.Move) {
        let frame = CGRect(x: 504, y: 316, width: 180, height: 180)
        #expect(BubblePlacement.storedInsets(after: move, frame: frame, recorded: recorded) == nil)
    }

    /// Insets stored after a drag place the bubble in the same spot at the next start.
    @Test func theStoredPlaceComesBack() throws {
        let dragged = CGRect(x: 504, y: 316, width: 180, height: 180)
        let stored = BubblePlacement.storedInsets(after: .dragEnded, frame: dragged, recorded: recorded)
        let insets = try #require(stored)
        #expect(BubblePlacement.frame(recorded: recorded, size: .medium, insets: insets) == dragged)
    }
}
