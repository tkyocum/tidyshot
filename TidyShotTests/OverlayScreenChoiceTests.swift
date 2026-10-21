import CoreGraphics
import Testing
@testable import TidyShot

/// Which screen the stack goes to (spec 2.9, Which display). Indices are into `NSScreen.screens`.
struct OverlayScreenChoiceTests {
    let ids: [CGDirectDisplayID] = [1, 7, 42]

    @Test func captureChoiceUsesTheCaptureDisplay() {
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 42, pointerIndex: 1, screenDisplayIDs: ids) == 2)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 1, pointerIndex: 2, screenDisplayIDs: ids) == 0)
    }

    /// A display unplugged since the capture, or no capture display (a restored card): the
    /// pointer's screen, then screen 0.
    @Test func aMissingCaptureDisplayFallsBackToThePointerThenScreenZero() {
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 99, pointerIndex: 1, screenDisplayIDs: ids) == 1)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: nil, pointerIndex: 2, screenDisplayIDs: ids) == 2)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 99, pointerIndex: nil, screenDisplayIDs: ids) == 0)
    }

    @Test func pointerChoiceIgnoresTheCaptureDisplay() {
        #expect(OverlayScreenChoice.index(choice: .pointer, captureDisplayID: 42, pointerIndex: 1, screenDisplayIDs: ids) == 1)
        #expect(OverlayScreenChoice.index(choice: .pointer, captureDisplayID: 42, pointerIndex: nil, screenDisplayIDs: ids) == 0)
        #expect(OverlayScreenChoice.index(choice: .pointer, captureDisplayID: 42, pointerIndex: 5, screenDisplayIDs: ids) == 0)
    }

    @Test func mainChoiceIsScreenZero() {
        #expect(OverlayScreenChoice.index(choice: .main, captureDisplayID: 42, pointerIndex: 1, screenDisplayIDs: ids) == 0)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 42, pointerIndex: nil, screenDisplayIDs: []) == 0)
    }

    @Test func titlesAndStoredValues() {
        #expect(OverlayDisplayChoice.allCases.map(\.title) == ["Display of the capture", "Display with the pointer", "Main display"])
        #expect(OverlayDisplayChoice.allCases.map(\.rawValue) == ["capture", "pointer", "main"])
    }
}
