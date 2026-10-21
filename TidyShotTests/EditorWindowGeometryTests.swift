import CoreGraphics
import Testing
@testable import TidyShot

struct EditorWindowGeometryTests {
    /// A 1920 by 1080 display below a 25 pt menu bar.
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1055)
    /// The title bar and unified toolbar: frame size minus content size.
    let chrome = CGSize(width: 0, height: 52)

    @Test func naturalSizePlusChromeWhenItFits() {
        // 1600 by 1000 pixels at 2x are 800 by 500 points, plus 24 pt on every side.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 1600, height: 1000), scale: 2,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 848, height: 548))
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 1000, height: 700), scale: 1,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 1048, height: 748))
        // Half points round up, so the canvas still fits the image at 100 %.
        let odd = CGSize(width: 1601, height: 1001)
        let content = EditorWindowGeometry.initialContentSize(imagePixels: odd, scale: 2, chrome: chrome, visibleFrame: screen)
        #expect(content == CGSize(width: 849, height: 549))
        #expect(CanvasTransform.fitting(imagePixelSize: odd, in: content, inset: EditorWindowGeometry.inset, captureScale: 2).zoom == 0.5)
    }

    @Test func clampedToNinetyPercent() {
        // A 5K capture is 2560 by 1440 points: the frame is 90 % of the screen, 1728 by 949.5,
        // and the content is that less the chrome, rounded down.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 5120, height: 2880), scale: 2,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 1728, height: 897))
        // Only the side that does not fit is clamped, on a screen whose origin is elsewhere.
        let laptop = CGRect(x: 1920, y: 300, width: 1440, height: 875)
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 3000, height: 800), scale: 2,
                                                        chrome: chrome, visibleFrame: laptop) == CGSize(width: 1296, height: 448))
    }

    @Test func minimumSize() {
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 200, height: 100), scale: 2,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 640, height: 420))
        // A long thin capture: the long side at its natural size, the short side at the minimum.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 1200, height: 80), scale: 1,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 1248, height: 420))
        // On a screen too small for the minimum, the 90 % cap wins.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 200, height: 100), scale: 2, chrome: chrome,
                                                        visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 400))
                == CGSize(width: 540, height: 308))
    }

    @Test func cascadeOffsetsAndStaysOnScreen() {
        let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let size = CGSize(width: 800, height: 575)
        // The first editor is centred.
        let first = EditorWindowGeometry.cascaded(from: nil, size: size, visibleFrame: laptop)
        #expect(first == CGRect(x: 320, y: 175, width: 800, height: 575))
        // The next is 22 pt right and 22 pt down.
        #expect(EditorWindowGeometry.cascaded(from: first, size: size, visibleFrame: laptop)
                == CGRect(x: 342, y: 153, width: 800, height: 575))
        // After a window of another size, the top edge steps down, not the origin.
        #expect(EditorWindowGeometry.cascaded(from: CGRect(x: 100, y: 300, width: 900, height: 500), size: size, visibleFrame: laptop)
                == CGRect(x: 122, y: 203, width: 800, height: 575))
        // Past the right and bottom edges: clamped inside the visible frame.
        #expect(EditorWindowGeometry.cascaded(from: CGRect(x: 630, y: 30, width: 800, height: 575), size: size, visibleFrame: laptop)
                == CGRect(x: 640, y: 25, width: 800, height: 575))
        // Larger than the screen: the top-left corner stays on it, so the title bar can be reached.
        #expect(EditorWindowGeometry.cascaded(from: nil, size: CGSize(width: 1600, height: 1000), visibleFrame: laptop)
                == CGRect(x: 0, y: -100, width: 1600, height: 1000))
    }

    /// The editor toolbar at its widest point: window buttons ending at 76 pt, a 230 pt title
    /// (counted up to 96 pt, since the title truncates first), six tool segments, four plain
    /// buttons, the prominent Upload, the 84 pt zoom pop-up and one fixed space. Seven items, so
    /// six gaps.
    @Test func toolbarWidthCountsEveryItem() {
        let width = EditorWindowGeometry.toolbarWidth(windowButtonsMaxX: 76, titleWidth: 230, toolSegments: 6,
                                                      buttons: 4, prominentButtons: 1, viewWidths: [84], fixedSpaces: 1)
        // 76 + 12 + 96 + 12 (leading and title), 6 * 36 + 8 (tools), 4 * 36, 44, 84 + 16 (zoom),
        // 6 * 10 (gaps), 16 (space), 16 (trailing).
        #expect(width == 800)
        // A short title counts at its own width.
        #expect(EditorWindowGeometry.toolbarWidth(windowButtonsMaxX: 76, titleWidth: 40, toolSegments: 6, buttons: 4,
                                                  prominentButtons: 1, viewWidths: [84], fixedSpaces: 1) == 744)
    }

    /// The window never gets narrower than its toolbar, nor than the 640 pt floor.
    @Test func minimumContentWidthCoversTheToolbar() {
        #expect(EditorWindowGeometry.minimumContentWidth(toolbarWidth: 800) == 800)
        #expect(EditorWindowGeometry.minimumContentWidth(toolbarWidth: 700.2) == 701)
        #expect(EditorWindowGeometry.minimumContentWidth(toolbarWidth: 500) == 640)
    }

    /// Every tool in `EditorTool.toolbarOrder` is one more segment, so each new tool widens the
    /// toolbar by `ToolbarMetrics.segment`. With the widest title, the toolbar for the tools the
    /// editor has must still fit 90 % of a 1280 pt wide display, or the 90 % cap would win over
    /// the minimum and the toolbar would overflow.
    @Test func toolbarWithEveryToolFitsASmallDisplay() {
        func width(segments: Int) -> CGFloat {
            EditorWindowGeometry.toolbarWidth(windowButtonsMaxX: EditorWindowGeometry.ToolbarMetrics.windowButtons,
                                              titleWidth: 230, toolSegments: segments, buttons: 4,
                                              prominentButtons: 1, viewWidths: [84], fixedSpaces: 1)
        }
        #expect(width(segments: 8) - width(segments: 6) == 2 * EditorWindowGeometry.ToolbarMetrics.segment)
        // The 4a toolbar is 800 pt wide. Each 4b task that adds a tool updates these two lines:
        // 8 tools and 872 pt (Task 1), 10 and 944 (Task 2), 11 and 980 (Task 3), 12 and 1016 (Task 4).
        #expect(EditorTool.toolbarOrder.count == 8)
        #expect(width(segments: EditorTool.toolbarOrder.count) == 872)
        let widest = EditorWindowGeometry.minimumContentWidth(toolbarWidth: width(segments: EditorTool.toolbarOrder.count))
        let ninetyPercent = (1280 * EditorWindowGeometry.screenFraction).rounded(.down)
        #expect(widest <= ninetyPercent)
    }

    /// A small capture opens at the toolbar's width, not at 640 pt.
    @Test func initialSizeUsesTheToolbarMinimum() {
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 200, height: 100), scale: 2,
                                                        chrome: chrome, visibleFrame: screen, minimumWidth: 800)
                == CGSize(width: 800, height: 420))
        // A wide capture is wider than the minimum anyway.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 1000, height: 700), scale: 1,
                                                        chrome: chrome, visibleFrame: screen, minimumWidth: 800)
                == CGSize(width: 1048, height: 748))
    }
}
