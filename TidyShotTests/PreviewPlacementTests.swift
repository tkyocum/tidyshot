import CoreGraphics
import Testing
@testable import TidyShot

struct PreviewPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1050)
    /// Fits 560 by 373 exactly at half size.
    let image = CGSize(width: 1120, height: 746)

    @Test func fittedShrinksButNeverEnlarges() {
        #expect(PreviewPlacement.fitted(CGSize(width: 1200, height: 800), in: PreviewPlacement.maxSize) == CGSize(width: 560, height: 373))
        #expect(PreviewPlacement.fitted(CGSize(width: 200, height: 100), in: PreviewPlacement.maxSize) == CGSize(width: 200, height: 100))
        #expect(PreviewPlacement.fitted(.zero, in: PreviewPlacement.maxSize) == .zero)
    }

    /// The status item's button window, in the menu bar above `screen`.
    func statusItem(x: CGFloat) -> CGRect {
        CGRect(x: x, y: 1050, width: 32, height: 30)
    }

    /// The usual case: the submenu opened to the right of the status menu, which hangs from the
    /// status item on the submenu's left, so the preview goes on the submenu's right.
    @Test func sitsRightOfASubmenuThatOpenedRightward() {
        let menu = CGRect(x: 560, y: 300, width: 360, height: 600)
        let row = CGRect(x: 560, y: 700, width: 360, height: 52)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: menu, rowFrame: row, statusItemFrame: statusItem(x: 300),
                                       visibleFrame: screen)
                == CGRect(x: 928, y: 539.5, width: 560, height: 373))
    }

    /// Status item near the right end of the menu bar: the submenu opened leftward, so the preview
    /// goes on its left. Without a status item frame the left is the default.
    @Test func sitsLeftOfASubmenuThatOpenedLeftward() {
        let menu = CGRect(x: 1100, y: 300, width: 360, height: 600)
        let row = CGRect(x: 1100, y: 700, width: 360, height: 52)
        let expected = CGRect(x: 532, y: 539.5, width: 560, height: 373)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: menu, rowFrame: row, statusItemFrame: statusItem(x: 1700),
                                       visibleFrame: screen) == expected)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: menu, rowFrame: row, statusItemFrame: nil,
                                       visibleFrame: screen) == expected)
    }

    /// No room on the preferred side: the other side, in both directions; with little room on
    /// both sides, the larger one, and the preview shrinks to fit it.
    @Test func fallsBackToTheOtherSideWithoutRoom() {
        // Prefers right, but the submenu touches the right edge of the screen.
        let rightEdge = CGRect(x: 1540, y: 300, width: 360, height: 600)
        let rightEdgeRow = CGRect(x: 1540, y: 500, width: 360, height: 52)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: rightEdge, rowFrame: rightEdgeRow,
                                       statusItemFrame: statusItem(x: 1500), visibleFrame: screen)
                == CGRect(x: 972, y: 339.5, width: 560, height: 373))

        // Prefers left, but the submenu touches the left edge of the screen.
        let leftEdge = CGRect(x: 40, y: 300, width: 360, height: 600)
        let leftEdgeRow = CGRect(x: 40, y: 500, width: 360, height: 52)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: leftEdge, rowFrame: leftEdgeRow,
                                       statusItemFrame: statusItem(x: 400), visibleFrame: screen)
                == CGRect(x: 408, y: 339.5, width: 560, height: 373))

        // Prefers left (284 points), the right is larger (324 points): right, shrunk.
        let narrow = CGRect(x: 0, y: 0, width: 1000, height: 1050)
        let middle = CGRect(x: 300, y: 0, width: 360, height: 600)
        let middleRow = CGRect(x: 300, y: 300, width: 360, height: 52)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: middle, rowFrame: middleRow,
                                       statusItemFrame: statusItem(x: 800), visibleFrame: narrow)
                == CGRect(x: 668, y: 218, width: 324, height: 216))
    }

    @Test func staysInsideTheScreen() {
        let menu = CGRect(x: 1400, y: 400, width: 360, height: 640)
        let topRow = CGRect(x: 1400, y: 1000, width: 360, height: 40)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: menu, rowFrame: topRow, statusItemFrame: statusItem(x: 1760),
                                       visibleFrame: screen)
                == CGRect(x: 832, y: 669, width: 560, height: 373))
        let low = CGRect(x: 1400, y: 0, width: 360, height: 640)
        let bottomRow = CGRect(x: 1400, y: 0, width: 360, height: 40)
        #expect(PreviewPlacement.frame(imageSize: image, menuFrame: low, rowFrame: bottomRow, statusItemFrame: statusItem(x: 1760),
                                       visibleFrame: screen)
                == CGRect(x: 832, y: 8, width: 560, height: 373))
    }
}
