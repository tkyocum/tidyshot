import Testing
@testable import TidyShot

/// The notices after Stop (design, The note posts after Stop; plan Gap 2; R3 design, Notices).
struct RecordingNoticeOrderTests {
    let save = RecordingNotice(title: "GIF not made", body: "Stopped. The recording was saved as an MP4.")
    let stop = RecordingNotice(title: "Recording stopped", body: "Your Mac went to sleep.")
    let microphone = RecordingNotice(title: "Recorded without the microphone", body: "Microphone access is off for TidyShot.")
    let camera = RecordingNotice(title: "Recorded without the webcam bubble", body: "Camera access is off for TidyShot.")
    let highlights = ClickHighlightRule.notFilmedNotice

    @Test func theSavesNoticeThenRecordingStoppedThenTheMicrophoneNote() {
        #expect(RecordingNoticeOrder.afterStop(save: save, stop: stop, microphone: microphone, camera: nil,
                                               highlights: nil, quitMode: false)
                == [save, stop, microphone])
    }

    @Test func missingNoticesAreSkipped() {
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: stop, microphone: microphone, camera: nil,
                                               highlights: nil, quitMode: false) == [stop, microphone])
        #expect(RecordingNoticeOrder.afterStop(save: save, stop: nil, microphone: nil, camera: nil,
                                               highlights: nil, quitMode: false) == [save])
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: nil, microphone: nil, camera: nil,
                                               highlights: nil, quitMode: false).isEmpty)
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: nil, microphone: nil, camera: nil,
                                               highlights: highlights, quitMode: false) == [highlights])
    }

    /// `.nothing` has no save: its own notice, then the note.
    @Test func theNoteComesAfterANothingNotice() {
        let failed = RecordingNotice(title: "Recording failed", body: "The recording is too short.")
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: failed, microphone: microphone, camera: nil,
                                               highlights: nil, quitMode: false)
                == [failed, microphone])
    }

    @Test func quitModeGivesNothing() {
        #expect(RecordingNoticeOrder.afterStop(save: save, stop: stop, microphone: microphone, camera: camera,
                                               highlights: highlights, quitMode: true).isEmpty)
    }

    /// R3: the camera note after the microphone note, the highlights note after it.
    @Test func theCameraNoteThenTheHighlightsNoteComeLast() {
        #expect(RecordingNoticeOrder.afterStop(save: save, stop: stop, microphone: microphone, camera: camera,
                                               highlights: highlights, quitMode: false)
                == [save, stop, microphone, camera, highlights])
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: nil, microphone: nil, camera: camera,
                                               highlights: highlights, quitMode: false) == [camera, highlights])
    }

    /// `.nothing`'s notice and no save notice: the R3 notes still follow it.
    @Test func theR3NotesComeAfterANothingNotice() {
        let failed = RecordingNotice(title: "Recording failed", body: "The recording is too short.")
        #expect(RecordingNoticeOrder.afterStop(save: nil, stop: failed, microphone: nil, camera: camera,
                                               highlights: highlights, quitMode: false)
                == [failed, camera, highlights])
    }

    /// One camera note at most (Decided 2026-10-24, 8): the start's note and a later loss give the
    /// start's alone.
    @Test func oneCameraNoteAtMost() {
        let start = RecordingNotice(title: "Recorded with FaceTime HD Camera", body: "The chosen camera was not connected.")
        let note = CameraNote.afterStop(start: start, wanted: true, missed: true,
                                        loss: .stopped(at: 12, backAt: nil))
        let notices = RecordingNoticeOrder.afterStop(save: nil, stop: nil, microphone: nil, camera: note,
                                                     highlights: nil, quitMode: false)
        #expect(notices == [start])
    }
}
