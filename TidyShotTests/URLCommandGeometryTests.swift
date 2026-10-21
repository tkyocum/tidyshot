import CoreGraphics
import Testing
@testable import TidyShot

/// CleanShot's rect convention (spec 2.9, decision 13): points from the bottom-left corner of the
/// display, display 1 the main one. The result is CoreGraphics global points, clipped.
struct URLCommandGeometryTests {
    /// CoreGraphics global points in `NSScreen.screens` order. Display 1 is the main display;
    /// display 2 sits above it and to the left (negative x and y); display 3 to its right, lower.
    let displays = [
        URLCommandGeometry.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        URLCommandGeometry.Display(id: 2, frame: CGRect(x: -1440, y: -900, width: 1440, height: 900)),
        URLCommandGeometry.Display(id: 3, frame: CGRect(x: 1920, y: 300, width: 2560, height: 1440)),
    ]

    func area(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> URLCommand.Area {
        URLCommand.Area(x: x, y: y, width: width, height: height)
    }

    func on(_ rect: CGRect, _ id: CGDirectDisplayID) -> URLCommandGeometry.Resolution {
        .area(ScreenRect(rect: rect, displayID: id))
    }

    @Test func theOriginIsTheBottomLeftOfTheMainDisplay() {
        #expect(URLCommandGeometry.resolve(area(0, 0, 200, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 0, y: 980, width: 200, height: 100), 1))
        #expect(URLCommandGeometry.resolve(area(100, 100, 200, 50), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 100, y: 930, width: 200, height: 50), 1))
        // The top-right corner of the display.
        #expect(URLCommandGeometry.resolve(area(1720, 980, 200, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 1720, y: 0, width: 200, height: 100), 1))
    }

    @Test func aDisplayAboveAndToTheLeftUsesItsOwnBottomLeft() {
        #expect(URLCommandGeometry.resolve(area(0, 0, 100, 100), display: 2, displays: displays, pointerIndex: 0)
                == on(CGRect(x: -1440, y: -100, width: 100, height: 100), 2))
        #expect(URLCommandGeometry.resolve(area(20, 800, 300, 50), display: 2, displays: displays, pointerIndex: 0)
                == on(CGRect(x: -1420, y: -850, width: 300, height: 50), 2))
    }

    @Test func withoutADisplayThePointersIsUsedThenTheMainOne() {
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: nil, displays: displays, pointerIndex: 2)
                == on(CGRect(x: 1930, y: 1630, width: 100, height: 100), 3))
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: nil, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 10, y: 970, width: 100, height: 100), 1))
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: nil, displays: displays, pointerIndex: 7)
                == on(CGRect(x: 10, y: 970, width: 100, height: 100), 1))
        // A given display wins over the pointer.
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: 1, displays: displays, pointerIndex: 2)
                == on(CGRect(x: 10, y: 970, width: 100, height: 100), 1))
    }

    @Test func aRectPartlyOffItsDisplayIsClipped() {
        #expect(URLCommandGeometry.resolve(area(1800, -20, 200, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 1800, y: 1000, width: 120, height: 80), 1))
        #expect(URLCommandGeometry.resolve(area(-50, 10, 100, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 0, y: 970, width: 50, height: 100), 1))
        // Larger than the display: the whole display.
        #expect(URLCommandGeometry.resolve(area(-10, -10, 5000, 5000), display: 3, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 1920, y: 300, width: 2560, height: 1440), 3))
    }

    @Test func aRectThatLeavesLessThanAPointIsOutside() {
        #expect(URLCommandGeometry.resolve(area(2000, 0, 100, 100), display: 1, displays: displays, pointerIndex: nil)
                == .outside(display: 1))
        #expect(URLCommandGeometry.resolve(area(10, 10, 0.5, 100), display: 1, displays: displays, pointerIndex: nil)
                == .outside(display: 1))
        #expect(URLCommandGeometry.resolve(area(1919.5, 10, 100, 100), display: 1, displays: displays, pointerIndex: nil)
                == .outside(display: 1))
        #expect(URLCommandGeometry.resolve(area(5000, 0, 10, 10), display: nil, displays: displays, pointerIndex: 2)
                == .outside(display: 3))
        #expect(URLCommandGeometry.outsideMessage(display: 2) == "The area leaves less than a point on display 2.")
    }

    @Test func aMissingDisplayIsReported() {
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: 4, displays: displays, pointerIndex: 0) == .noDisplay(4))
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: 0, displays: displays, pointerIndex: 0) == .noDisplay(0))
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: 2, displays: [], pointerIndex: nil) == .noDisplay(2))
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: nil, displays: [], pointerIndex: nil) == .noDisplay(1))
    }

    @Test func fractionalPointsAreKept() {
        #expect(URLCommandGeometry.resolve(area(10.5, 20.25, 100.5, 50.75), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 10.5, y: 1009, width: 100.5, height: 50.75), 1))
    }
}
