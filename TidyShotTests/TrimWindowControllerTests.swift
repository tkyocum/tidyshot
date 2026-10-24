import AppKit
import CoreGraphics
import Testing
@testable import TidyShot

/// The Trim window's first size (design, Trim, Window): the recording at its point size, scaled down to
/// fit the screen with its aspect kept, never under the minimum; its first frame, centred on that
/// screen; and the save sheet's answer.
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

    /// The first frame is centred in the visible frame of the screen the size was fitted to, also a
    /// second display left of and below the primary, on whole points.
    @Test func theWindowIsCentredOnTheScreenItWasSizedFor() {
        let size = CGSize(width: 800, height: 528)
        #expect(TrimWindowController.frame(size: size, centredIn: CGRect(x: 0, y: 25, width: 1512, height: 919))
                == CGRect(x: 356, y: 221, width: 800, height: 528))
        let second = CGRect(x: -2560, y: -400, width: 2560, height: 1415)
        let frame = TrimWindowController.frame(size: size, centredIn: second)
        #expect(frame == CGRect(x: -1680, y: 44, width: 800, height: 528))
        #expect(second.contains(frame))
    }

    /// The save sheet's response picks its button: `alertFirstButtonReturn` the first, each later
    /// return the next; the window closed under the sheet (`.cancel`), or any other response, is
    /// `Cancel`.
    @Test func theSheetsResponsePicksItsButton() {
        let buttons: [RecordingTrim.SheetButton] = [.saveAndUpload, .save, .cancel]
        let first = NSApplication.ModalResponse.alertFirstButtonReturn
        #expect(TrimWindowController.sheetButton(response: first, of: buttons) == .saveAndUpload)
        #expect(TrimWindowController.sheetButton(response: .alertSecondButtonReturn, of: buttons) == .save)
        #expect(TrimWindowController.sheetButton(response: NSApplication.ModalResponse(first.rawValue + 1), of: buttons)
                == .save)
        #expect(TrimWindowController.sheetButton(response: NSApplication.ModalResponse(first.rawValue + 2), of: buttons)
                == .cancel)
        #expect(TrimWindowController.sheetButton(response: .alertThirdButtonReturn, of: [.save, .saveAndUpload, .cancel])
                == .cancel)
        #expect(TrimWindowController.sheetButton(response: .cancel, of: buttons) == .cancel)
        #expect(TrimWindowController.sheetButton(response: .abort, of: buttons) == .cancel)
        #expect(TrimWindowController.sheetButton(response: .alertSecondButtonReturn, of: [.save, .cancel]) == .cancel)
    }
}
