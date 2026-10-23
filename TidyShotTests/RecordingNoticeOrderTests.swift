import Testing
@testable import TidyShot

/// The notices after Stop (design, The note posts after Stop; plan Gap 2).
struct RecordingNoticeOrderTests {
    let save = RecordingNotice(title: "GIF not made", body: "Stopped. The recording was saved as an MP4.")
    let stop = RecordingNotice(title: "Recording stopped", body: "Your Mac went to sleep.")
    let microphone = RecordingNotice(title: "Recorded without the microphone", body: "Microphone access is off for TidyShot.")

    @Test func theSavesNoticeThenRecordingStoppedThenTheMicrophoneNote() {
        #expect(RecordingNoticeOrder.afterStop(save: save, stop: stop, microphone: microphone, quitMode: false)
                == [save, stop, microphone])
    }

    @Test func missingNoticesAreSkipped() {
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: stop, microphone: microphone, quitMode: false) == [stop, microphone])
        #expect(RecordingNoticeOrder.afterStop(save: save, stop: nil, microphone: nil, quitMode: false) == [save])
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: nil, microphone: nil, quitMode: false).isEmpty)
    }

    /// `.nothing` has no save: its own notice, then the note.
    @Test func theNoteComesAfterANothingNotice() {
        let failed = RecordingNotice(title: "Recording failed", body: "The recording is too short.")
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: failed, microphone: microphone, quitMode: false)
                == [failed, microphone])
    }

    @Test func quitModeGivesNothing() {
        #expect(RecordingNoticeOrder.afterStop(save: save, stop: stop, microphone: microphone, quitMode: true).isEmpty)
    }
}
