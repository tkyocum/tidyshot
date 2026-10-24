import CoreGraphics
import Testing
@testable import TidyShot

/// The Trim window's first size (design, Trim, Window): the recording at its point size, scaled down to
/// fit the screen with its aspect kept, never under the minimum.
struct TrimWindowControllerTests {
    let laptop = CGSize(width: 1512, height: 944)

    @Test func aRecordingThatFitsOpensAtItsPointSize() {
        #expect(TrimWindowController.contentSize(pixelSize: CGSize(width: 1600, height: 1000), scale: 2,
                                                 visibleSize: laptop) == CGSize(width: 800, height: 500))
    }

    @Test func aLargeRecordingIsScaledDownWithItsAspectKept() {
        // 2560×1664 at 1× is 2560×1664 points; 80 % of 944 is 755.2, the tighter limit.
        let size = TrimWindowController.contentSize(pixelSize: CGSize(width: 2560, height: 1664), scale: 1,
                                                    visibleSize: laptop)
        #expect(size == CGSize(width: 1162, height: 755))
        #expect(size.width <= laptop.width * TrimWindowController.maximumScreenShare)
        #expect(size.height <= laptop.height * TrimWindowController.maximumScreenShare)
    }

    @Test func aSmallOrUnknownRecordingOpensAtTheMinimum() {
        let minimum = TrimWindowController.minimumContentSize
        #expect(TrimWindowController.contentSize(pixelSize: CGSize(width: 320, height: 200), scale: 2,
                                                 visibleSize: laptop) == minimum)
        #expect(TrimWindowController.contentSize(pixelSize: .zero, scale: 2, visibleSize: laptop) == minimum)
        #expect(TrimWindowController.contentSize(pixelSize: CGSize(width: 1600, height: 1000), scale: 0,
                                                 visibleSize: laptop) == minimum)
    }
}
