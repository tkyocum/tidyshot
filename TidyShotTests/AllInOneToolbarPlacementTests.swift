import CoreGraphics
import Testing
@testable import TidyShot

struct AllInOneToolbarPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let toolbar = CGSize(width: 440, height: 36)

    func frame(_ selection: CGRect, screen bounds: CGRect? = nil, toolbar size: CGSize? = nil) -> CGRect {
        AllInOneToolbarPlacement.frame(toolbarSize: size ?? toolbar, selection: selection, screenBounds: bounds ?? screen)
    }

    @Test func belowTheSelectionAndCentred() {
        #expect(frame(CGRect(x: 400, y: 300, width: 600, height: 300)) == CGRect(x: 480, y: 256, width: 440, height: 36))
    }

    @Test func aboveWhenThereIsNoRoomBelow() {
        #expect(frame(CGRect(x: 400, y: 30, width: 600, height: 300)) == CGRect(x: 480, y: 338, width: 440, height: 36))
    }

    @Test func insideTheBottomEdgeWhenNeitherFits() {
        #expect(frame(screen) == CGRect(x: 500, y: 8, width: 440, height: 36))
        #expect(frame(CGRect(x: 100, y: 20, width: 600, height: 860)) == CGRect(x: 180, y: 28, width: 440, height: 36))
        // A notched display: the menu bar band is off limits, so the toolbar sits inside the bottom edge.
        #expect(frame(CGRect(x: 100, y: 20, width: 600, height: 820), screen: CGRect(x: 0, y: 0, width: 1440, height: 862))
                == CGRect(x: 180, y: 28, width: 440, height: 36))
    }

    @Test func clampedToTheScreensSides() {
        #expect(frame(CGRect(x: 0, y: 300, width: 100, height: 100)) == CGRect(x: 8, y: 256, width: 440, height: 36))
        #expect(frame(CGRect(x: 1400, y: 300, width: 40, height: 100)) == CGRect(x: 992, y: 256, width: 440, height: 36))
    }

    @Test func aScreenNarrowerThanTheToolbarAlignsItLeft() {
        #expect(frame(CGRect(x: 50, y: 100, width: 100, height: 100), screen: CGRect(x: 0, y: 0, width: 400, height: 300))
                == CGRect(x: 8, y: 56, width: 440, height: 36))
    }

    @Test func screenBoundsWithAnOrigin() {
        #expect(frame(CGRect(x: 150, y: 60, width: 200, height: 100), screen: CGRect(x: 100, y: 50, width: 800, height: 600))
                == CGRect(x: 108, y: 168, width: 440, height: 36))
    }

    @Test func theOriginIsWholePoints() {
        #expect(frame(CGRect(x: 400.5, y: 300, width: 601, height: 300), toolbar: CGSize(width: 441.4, height: 36))
                == CGRect(x: 480, y: 256, width: 441.4, height: 36))
    }
}
