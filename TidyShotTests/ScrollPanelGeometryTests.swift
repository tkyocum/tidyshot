import CoreGraphics
import Testing
@testable import TidyShot

struct ScrollPanelGeometryTests {
    /// AppKit coordinates: origin bottom left. The visible frame has a 25 pt menu bar gap on top
    /// and a 70 pt Dock at the bottom.
    let screen = CGRect(x: 0, y: 70, width: 1920, height: 985)
    let panel = CGSize(width: 240, height: 400)

    @Test func sitsTwelvePointsRightOfTheAreaTopAligned() {
        let area = CGRect(x: 200, y: 300, width: 800, height: 600)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
                == CGRect(x: 1012, y: 500, width: 240, height: 400))
    }

    @Test func fitsExactlyAgainstTheRightEdge() {
        let area = CGRect(x: 200, y: 300, width: 1468, height: 600)
        // 1668 + 12 + 240 = 1920.
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen).minX == 1680)
    }

    @Test func goesLeftWhenTheRightHasNoRoom() {
        let area = CGRect(x: 900, y: 300, width: 900, height: 600)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
                == CGRect(x: 648, y: 500, width: 240, height: 400))
    }

    @Test func goesInsideTheBottomRightCornerWhenNeitherSideHasRoom() {
        let area = CGRect(x: 100, y: 200, width: 1700, height: 700)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
                == CGRect(x: 1548, y: 212, width: 240, height: 400))
    }

    @Test func isClampedBelowTheMenuBar() {
        // The area reaches the top of the visible frame, and a tall panel top-aligned to it stays inside.
        let area = CGRect(x: 200, y: 700, width: 600, height: 355)
        let frame = ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
        #expect(frame.maxY == screen.maxY)
        #expect(frame.minX == 812)
    }

    @Test func isClampedAboveTheDock() {
        // A short area near the bottom: top alignment would push the panel below the visible frame.
        let area = CGRect(x: 200, y: 80, width: 600, height: 120)
        let frame = ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
        #expect(frame.minY == screen.minY)
        #expect(frame.minX == 812)
    }

    @Test func usesTheVisibleFrameOfAScreenNotAtTheOrigin() {
        let right = CGRect(x: 1920, y: 0, width: 1440, height: 875)
        let area = CGRect(x: 2300, y: 200, width: 1000, height: 500)
        // 3300 + 12 + 240 is past 3360, so left: 2300 - 12 - 240. The top aligns with the area's: 700 - 400.
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: right)
                == CGRect(x: 2048, y: 300, width: 240, height: 400))
        // Neither side has room on this screen: inside the corner, never onto the first screen.
        let wide = CGRect(x: 2000, y: 200, width: 1300, height: 500)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: wide, visibleFrame: right)
                == CGRect(x: 3048, y: 212, width: 240, height: 400))
    }

    @Test func theResultAlwaysStaysInsideTheVisibleFrame() {
        let areas = [CGRect(x: 0, y: 70, width: 1920, height: 985), CGRect(x: 1800, y: 900, width: 120, height: 155),
                     CGRect(x: 0, y: 70, width: 120, height: 100), CGRect(x: 960, y: 500, width: 400, height: 200)]
        for area in areas {
            let frame = ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
            #expect(screen.contains(frame), "area \(area) gave \(frame)")
            #expect(frame.size == panel)
        }
    }

    @Test func heightFollowsThePreviewBetween220AndTheAreaHeight() {
        #expect(ScrollPanelGeometry.height(wanted: 100, areaHeight: 800) == 220)
        #expect(ScrollPanelGeometry.height(wanted: 380, areaHeight: 800) == 380)
        #expect(ScrollPanelGeometry.height(wanted: 700, areaHeight: 800) == 560)
        #expect(ScrollPanelGeometry.height(wanted: 700, areaHeight: 300) == 300)
        // An area shorter than the minimum still gets the minimum.
        #expect(ScrollPanelGeometry.height(wanted: 400, areaHeight: 150) == 220)
    }

    @Test func thePanelIs240PointsWide() {
        #expect(ScrollPanelGeometry.panelWidth == 240)
        #expect(ScrollPanelGeometry.gap == 12)
    }
}
