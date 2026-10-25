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
