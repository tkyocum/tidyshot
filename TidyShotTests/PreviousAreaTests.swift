import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct PreviousAreaTests {
    /// CoreGraphics global points, origin top left of the primary display. `main` is the primary
    /// display, `right` sits beside it, `left` is above-left of the origin with a negative x.
    let main = PreviousArea.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    let right = PreviousArea.Display(id: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
    let left = PreviousArea.Display(id: 3, frame: CGRect(x: -1440, y: 180, width: 1440, height: 900))

    @Test func noRectResolvesToNone() {
        #expect(PreviousArea.resolve(rect: nil, displays: [main]) == .none)
    }

    @Test func aRectUnderOnePointResolvesToNone() {
        #expect(PreviousArea.resolve(rect: CGRect(x: 10, y: 10, width: 0, height: 300), displays: [main]) == .none)
        #expect(PreviousArea.resolve(rect: CGRect(x: 10, y: 10, width: 300, height: 0.5), displays: [main]) == .none)
    }

    @Test func aRectOnTheMainDisplayComesBackUnchanged() {
        let rect = CGRect(x: 100, y: 200, width: 640, height: 480)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, right, left]) == .area(rect, 1))
    }

    @Test func aRectOnADisplayWithANegativeOriginPicksThatDisplay() {
        let rect = CGRect(x: -1000, y: 300, width: 400, height: 300)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, right, left]) == .area(rect, 3))
    }

    @Test func aRectPartlyOffItsDisplayIsClippedToIt() {
        let rect = CGRect(x: 1800, y: 900, width: 200, height: 200)
        #expect(PreviousArea.resolve(rect: rect, displays: [main])
                == .area(CGRect(x: 1800, y: 900, width: 120, height: 180), 1))
    }

    @Test func aRectBetweenTwoDisplaysGoesToTheOneHoldingItsCentre() {
        let displays = [main, right]
        // Centre x 1950: on the right display, clipped to its left edge.
        #expect(PreviousArea.resolve(rect: CGRect(x: 1800, y: 800, width: 300, height: 200), displays: displays)
                == .area(CGRect(x: 1920, y: 800, width: 180, height: 200), 2))
        // Centre x 1850: on the main display, clipped to its right edge.
        #expect(PreviousArea.resolve(rect: CGRect(x: 1700, y: 800, width: 300, height: 200), displays: displays)
                == .area(CGRect(x: 1700, y: 800, width: 220, height: 200), 1))
    }

    @Test func aRectOnARemovedDisplayIsOffScreen() {
        let rect = CGRect(x: 2000, y: 100, width: 500, height: 400)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, right]) == .area(rect, 2))
        #expect(PreviousArea.resolve(rect: rect, displays: [main]) == .offScreen)
    }

    /// A 1 pt wide rect whose centre is 0.1 pt inside the main display's right edge keeps 0.6 pt
    /// on it: too thin to capture, so it counts as off screen. The same at the bottom edge.
    @Test func aRectLeavingUnderOnePointOnItsDisplayIsOffScreen() {
        #expect(PreviousArea.resolve(rect: CGRect(x: 1919.4, y: 100, width: 1, height: 300), displays: [main]) == .offScreen)
        #expect(PreviousArea.resolve(rect: CGRect(x: 100, y: 1079.4, width: 300, height: 1), displays: [main]) == .offScreen)
        // Exactly one point left on the display is enough.
        #expect(PreviousArea.resolve(rect: CGRect(x: 1919, y: 100, width: 1.5, height: 300), displays: [main])
                == .area(CGRect(x: 1919, y: 100, width: 1, height: 300), 1))
    }

    @Test func noDisplaysIsOffScreen() {
        #expect(PreviousArea.resolve(rect: CGRect(x: 0, y: 0, width: 100, height: 100), displays: []) == .offScreen)
    }

    @Test func aCentreInTheGapBetweenDisplaysIsOffScreen() {
        // `lower` starts at y 1200, so a centre at (1950, 1100) is on neither display.
        let lower = PreviousArea.Display(id: 4, frame: CGRect(x: 1920, y: 1200, width: 1280, height: 720))
        let rect = CGRect(x: 1900, y: 1000, width: 100, height: 200)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, lower]) == .offScreen)
    }

    @Test func mirroredDisplaysResolveToTheFirstOne() {
        let mirror = PreviousArea.Display(id: 5, frame: main.frame)
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, mirror]) == .area(rect, 1))
    }

    @Test func aStoredRectRoundTripsThroughJSON() throws {
        let rect = CGRect(x: -1000.5, y: 300.25, width: 400, height: 300.75)
        let data = try JSONEncoder().encode(StoredRect(rect))
        let decoded = try JSONDecoder().decode(StoredRect.self, from: data)
        #expect(decoded == StoredRect(rect))
        #expect(decoded.cgRect == rect)
    }

    /// The stored shape is part of the settings file: Task 10 and Task 13 read the same value.
    @Test func aStoredRectIsFourNamedNumbers() throws {
        let json = Data(#"{"x":1,"y":2,"width":3,"height":4}"#.utf8)
        let decoded = try JSONDecoder().decode(StoredRect.self, from: json)
        #expect(decoded.cgRect == CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}
