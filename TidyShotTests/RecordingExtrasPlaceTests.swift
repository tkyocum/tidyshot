import CoreGraphics
import Testing
@testable import TidyShot

/// Where the bubble, the ring overlay and the rings go for a recorded area or display (design,
/// Filming, When they are made; plan Gap 13).
struct RecordingExtrasPlaceTests {
    /// A 2560×1440 pt primary display, and its screen with a menu bar and a Dock.
    let primary = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    let primaryVisible = CGRect(x: 0, y: 80, width: 2560, height: 1335)

    @Test func anAreaOnThePrimaryDisplay() {
        let place = RecordingExtrasPlace.make(cgArea: CGRect(x: 100, y: 200, width: 800, height: 600),
                                              cgDisplayFrame: primary, screenFrame: primary,
                                              visibleFrame: primaryVisible, primaryHeight: 1440)
        #expect(place.bubbleRect == CGRect(x: 100, y: 640, width: 800, height: 600))
        #expect(place.ringArea == CGRect(x: 100, y: 200, width: 800, height: 600))
        #expect(place.screenFrame == primary)
        #expect(place.displayFrame == primary)
    }

    @Test func fullscreenUsesTheVisibleFrameAndHasNoRingArea() {
        let place = RecordingExtrasPlace.make(cgArea: nil, cgDisplayFrame: primary, screenFrame: primary,
                                              visibleFrame: primaryVisible, primaryHeight: 1440)
        #expect(place.bubbleRect == primaryVisible)
        #expect(place.ringArea == nil)
        #expect(place.screenFrame == primary)
        #expect(place.displayFrame == primary)
    }

    @Test func anAreaOnASecondDisplayLeftOfAndBelowThePrimary() {
        // CG y grows down, so below the primary is past its height; in AppKit it is negative.
        let display = CGRect(x: -1920, y: 1440, width: 1920, height: 1080)
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let place = RecordingExtrasPlace.make(cgArea: CGRect(x: -1800, y: 1600, width: 400, height: 300),
                                              cgDisplayFrame: display, screenFrame: screen,
                                              visibleFrame: visible, primaryHeight: 1440)
        #expect(place.bubbleRect == CGRect(x: -1800, y: -460, width: 400, height: 300))
        #expect(place.ringArea == CGRect(x: -1800, y: 1600, width: 400, height: 300))
        #expect(place.screenFrame == screen)
        #expect(place.displayFrame == display)
    }

    @Test func fullscreenOnASecondDisplay() {
        let display = CGRect(x: -1920, y: 1440, width: 1920, height: 1080)
        let screen = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let visible = CGRect(x: -1920, y: -1080, width: 1920, height: 1055)
        let place = RecordingExtrasPlace.make(cgArea: nil, cgDisplayFrame: display, screenFrame: screen,
                                              visibleFrame: visible, primaryHeight: 1440)
        #expect(place.bubbleRect == visible)
        #expect(place.ringArea == nil)
        #expect(place.displayFrame == display)
    }

    @Test func anAreaAcrossTheDisplaysEdgeIsCutToIt() {
        let place = RecordingExtrasPlace.make(cgArea: CGRect(x: 2400, y: 1300, width: 400, height: 300),
                                              cgDisplayFrame: primary, screenFrame: primary,
                                              visibleFrame: primaryVisible, primaryHeight: 1440)
        #expect(place.ringArea == CGRect(x: 2400, y: 1300, width: 160, height: 140))
        #expect(place.bubbleRect == CGRect(x: 2400, y: 0, width: 160, height: 140))
    }

    /// The display's frame changed during the count-in and no longer holds the area: the bubble
    /// goes in the visible frame, so its clamp never sees an infinite rect, and no down draws.
    @Test(arguments: [CGRect(x: 3000, y: 200, width: 400, height: 300),
                      CGRect(x: 2560, y: 200, width: 400, height: 300)])
    func anAreaOffTheDisplayPutsTheBubbleInTheVisibleFrame(_ area: CGRect) {
        let place = RecordingExtrasPlace.make(cgArea: area, cgDisplayFrame: primary, screenFrame: primary,
                                              visibleFrame: primaryVisible, primaryHeight: 1440)
        #expect(place.bubbleRect == primaryVisible)
        let frame = BubblePlacement.frame(recorded: place.bubbleRect, size: .medium,
                                          insets: .standard)
        #expect(frame.minX.isFinite && frame.minY.isFinite)
        #expect(place.ringArea?.isEmpty == true)
    }
}
