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
}
