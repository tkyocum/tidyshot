import Foundation
import Testing
@testable import TidyShot

struct ScrollCaptureStatusTests {
    @Test func everyStatusLineMatchesTheSpec() {
        #expect(ScrollCaptureStatus.readyManual.text == "Click Start, then scroll down slowly.")
        #expect(ScrollCaptureStatus.readyAuto.text == "Click Start, then hold the pointer over the area.")
        #expect(ScrollCaptureStatus.manualCapturing.text == "Scroll down slowly. Click Done at the end.")
        #expect(ScrollCaptureStatus.manualLost.text == "Too fast. Scroll back up a little.")
        #expect(ScrollCaptureStatus.autoScrolling.text == "Scrolling… Move the pointer away to pause.")
        #expect(ScrollCaptureStatus.autoPaused.text == "Paused. Move the pointer over the area to continue.")
        #expect(ScrollCaptureStatus.autoHandedOver.text == "Auto-scroll lost its place. Scroll back up a little, or click Done.")
        #expect(ScrollCaptureStatus.autoReachedEnd.text == "Reached the end.")
        #expect(ScrollCaptureStatus.heightLimit.text == "Reached the 65,536 pixel limit.")
        #expect(ScrollCaptureStatus.finishing.text == "Stitching…")
    }

    @Test func theReadyLineFollowsTheAutoScrollSetting() {
        #expect(ScrollCaptureStatus.ready(autoScroll: false) == .readyManual)
        #expect(ScrollCaptureStatus.ready(autoScroll: true) == .readyAuto)
    }

    @Test func theHeightLimitLineNamesTheLimit() {
        #expect(ScrollCaptureLimits.maxPixelHeight == 65_536)
    }

    @Test func theSizeReadoutGroupsDigitsAndUsesATimesSign() {
        let us = Locale(identifier: "en_US")
        #expect(ScrollCaptureStatus.sizeText(width: 2560, height: 7340, locale: us) == "2,560 × 7,340 px")
        #expect(ScrollCaptureStatus.sizeText(width: 640, height: 900, locale: us) == "640 × 900 px")
        #expect(ScrollCaptureStatus.sizeText(width: 3094, height: 65536, locale: us) == "3,094 × 65,536 px")
        let german = ScrollCaptureStatus.sizeText(width: 2560, height: 7340, locale: Locale(identifier: "de_DE"))
        #expect(german == "2.560 × 7.340 px")
    }
}
