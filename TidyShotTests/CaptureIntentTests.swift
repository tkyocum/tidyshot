import Testing
@testable import TidyShot

/// What each `action` asks for under each after-capture action (spec 2.9, URL scheme, Actions).
struct CaptureIntentTests {
    @Test func noActionIsTheAfterCaptureActionInGeneral() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: nil, setting: setting) == CaptureIntent(action: setting, copyOnly: false, then: .none))
        }
    }

    /// `upload` is Upload only when that is the setting (Tim's case), otherwise Upload and copy URL.
    @Test func uploadUploadsUnderEverySetting() {
        #expect(CaptureIntent(urlAction: .upload, setting: .uploadOnly) == CaptureIntent(action: .uploadOnly))
        #expect(CaptureIntent(urlAction: .upload, setting: .upload) == CaptureIntent(action: .upload))
        #expect(CaptureIntent(urlAction: .upload, setting: .save) == CaptureIntent(action: .upload))
    }

    @Test func saveIsSaveAndCopyImageUnderEverySetting() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: .save, setting: setting) == CaptureIntent(action: .save))
        }
    }

    @Test func copyPutsTheImageOnTheClipboardOnly() {
        for setting in AfterCaptureAction.allCases {
            let intent = CaptureIntent(urlAction: .copy, setting: setting)
            #expect(intent.copyOnly)
            #expect(intent.then == .none)
        }
    }

    @Test func annotateRunsTheAfterCaptureActionThenOpensTheEditor() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: .annotate, setting: setting) == CaptureIntent(action: setting, then: .annotate))
        }
    }

    @Test func pinRunsTheAfterCaptureActionThenPins() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: .pin, setting: setting) == CaptureIntent(action: setting, then: .pin))
        }
    }

    @Test func theSenderTravelsWithTheIntent() {
        #expect(CaptureIntent(urlAction: .copy, setting: .save, sender: "Raycast").sender == "Raycast")
        #expect(CaptureIntent(urlAction: nil, setting: .save).sender == nil)
    }

    /// Hotkeys and the menu: the General action, nothing else.
    @Test func standardIsTheGeneralSettingWithNothingAfter() {
        #expect(CaptureIntent.standard == CaptureIntent(action: AppSettings.shared.afterCaptureAction))
    }
}
