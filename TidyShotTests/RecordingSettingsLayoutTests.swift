import Foundation
import Testing
@testable import TidyShot

/// Which Recording rows the Capture tab shows and enables for each format (design, GIF, Setting).
struct RecordingSettingsLayoutTests {
    @Test func mp4ShowsFrameRateAndEnablesTheAudioRows() {
        let layout = RecordingSettingsLayout(format: .mp4)
        #expect(layout.showsFrameRate)
        #expect(!layout.showsGIFRows)
        #expect(layout.audioRowsEnabled)
        #expect(!layout.showsGIFCaption)
    }

    @Test func gifShowsItsRowsAndDisablesTheAudioRows() {
        let layout = RecordingSettingsLayout(format: .gif)
        #expect(!layout.showsFrameRate)
        #expect(layout.showsGIFRows)
        #expect(!layout.audioRowsEnabled)
        #expect(layout.showsGIFCaption)
    }

    @Test func eachFormatHasItsOwnLayout() {
        #expect(RecordingSettingsLayout(format: .mp4) == RecordingSettingsLayout(format: .mp4))
        #expect(RecordingSettingsLayout(format: .mp4) != RecordingSettingsLayout(format: .gif))
    }

    @Test func cameraRowsFollowTheBubbleToggleForBothFormats() {
        for format in [RecordingFormat.mp4, .gif] {
            #expect(!RecordingSettingsLayout(format: format).cameraRowsEnabled)
            #expect(!RecordingSettingsLayout(format: format, clickHighlights: true).cameraRowsEnabled)
            #expect(RecordingSettingsLayout(format: format, webcamBubble: true).cameraRowsEnabled)
            #expect(RecordingSettingsLayout(format: format, clickHighlights: true, webcamBubble: true).cameraRowsEnabled)
        }
    }

    @Test func theBubbleGIFCaptionShowsForGIFWithTheBubbleOnOnly() {
        #expect(RecordingSettingsLayout(format: .gif, webcamBubble: true).showsBubbleGIFCaption)
        #expect(!RecordingSettingsLayout(format: .gif).showsBubbleGIFCaption)
        #expect(!RecordingSettingsLayout(format: .gif, clickHighlights: true).showsBubbleGIFCaption)
        #expect(!RecordingSettingsLayout(format: .mp4, webcamBubble: true).showsBubbleGIFCaption)
        #expect(!RecordingSettingsLayout(format: .mp4).showsBubbleGIFCaption)
    }

    @Test func theOverlayCaptionShowsWithEitherToggleOn() {
        for format in [RecordingFormat.mp4, .gif] {
            #expect(!RecordingSettingsLayout(format: format).showsOverlayCaption)
            #expect(RecordingSettingsLayout(format: format, clickHighlights: true).showsOverlayCaption)
            #expect(RecordingSettingsLayout(format: format, webcamBubble: true).showsOverlayCaption)
            #expect(RecordingSettingsLayout(format: format, clickHighlights: true, webcamBubble: true).showsOverlayCaption)
        }
    }

    /// R2's four fields do not change with the R3 arguments.
    @Test func theR2FieldsIgnoreTheR3Toggles() {
        for format in [RecordingFormat.mp4, .gif] {
            let plain = RecordingSettingsLayout(format: format)
            let both = RecordingSettingsLayout(format: format, clickHighlights: true, webcamBubble: true)
            #expect(both.showsFrameRate == plain.showsFrameRate)
            #expect(both.showsGIFRows == plain.showsGIFRows)
            #expect(both.audioRowsEnabled == plain.audioRowsEnabled)
            #expect(both.showsGIFCaption == plain.showsGIFCaption)
        }
    }

    @Test func theR3Captions() {
        #expect(RecordingSettingsLayout.bubbleGIFCaption
                == "A webcam bubble makes GIFs larger, because its picture changes in every frame.")
        #expect(RecordingSettingsLayout.overlayCaption
                == "Click highlights and the webcam bubble apply to area and fullscreen recordings.")
    }

    @Test func captions() {
        #expect(RecordingSettingsLayout.gifCaption == "GIFs have no sound. Sound settings apply to MP4 recordings.")
        #expect(RecordingSettingsLayout.fullSizeCaption == "Full size GIFs can be very large.")
    }

    /// Stored as `recordingFormat`: `mp4` or `gif`.
    @Test func formatRawValues() {
        #expect(RecordingFormat.mp4.rawValue == "mp4")
        #expect(RecordingFormat.gif.rawValue == "gif")
    }
}
