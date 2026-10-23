import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct RecordingEndTests {
    static func facts(playable: Bool = true, duration: TimeInterval) -> VideoFacts {
        VideoFacts(isPlayable: playable, duration: duration, naturalSize: playable ? CGSize(width: 1600, height: 1000) : nil,
                   videoTracks: playable ? 1 : 0, audioTracks: 0, byteCount: 1_000,
                   meetsMinimum: playable && duration >= RecordingLimits.minimumDuration)
    }

    let tenSeconds = Self.facts(duration: 10)
    let tooShort = Self.facts(duration: 0.3)
    let unplayable = Self.facts(playable: false, duration: 0)

    @Test func playableFileIsSavedAfterAStop() {
        #expect(RecordingEnd.decide(.stop, facts: tenSeconds, waitTimedOut: false) == .keep(notice: nil))
    }

    @Test func shortFileIsDiscardedAsTooShort() {
        #expect(RecordingEnd.decide(.stop, facts: tooShort, waitTimedOut: false)
            == .remove(notice: RecordingNotice(title: "Recording failed", body: "The recording is too short.")))
    }

    @Test func unplayableFileIsDiscarded() {
        #expect(RecordingEnd.decide(.stop, facts: unplayable, waitTimedOut: false)
            == .remove(notice: RecordingNotice(title: "Recording failed", body: "The recording is too short.")))
        #expect(RecordingEnd.decide(.failed("The stream stopped."), facts: unplayable, waitTimedOut: false)
            == .remove(notice: RecordingNotice(title: "Recording failed", body: "The stream stopped.")))
    }

    @Test func playableFileAfterAnErrorIsSavedAsStopped() {
        #expect(RecordingEnd.decide(.failed("The stream stopped."), facts: tenSeconds, waitTimedOut: false)
            == .keep(notice: RecordingNotice(title: "Recording stopped", body: "The stream stopped.")))
    }

    /// The timeout never deletes a playable file.
    @Test func timeoutWithAPlayableFileIsSaved() {
        #expect(RecordingEnd.decide(.stop, facts: tenSeconds, waitTimedOut: true) == .keep(notice: nil))
        #expect(RecordingEnd.decide(.sleep, facts: tenSeconds, waitTimedOut: true)
            == .keep(notice: RecordingNotice(title: "Recording stopped", body: "Your Mac went to sleep.")))
    }

    @Test func discardingCancelRemovesAPlayableFileAndPostsNothing() {
        #expect(RecordingEnd.decide(.discardingCancel, facts: tenSeconds, waitTimedOut: false) == .remove(notice: nil))
        #expect(RecordingEnd.decide(.discardingCancel, facts: unplayable, waitTimedOut: true) == .remove(notice: nil))
    }

    /// `Save` in the discard alert carries on as a Stop: the controller decides it as `.stop`.
    @Test func saveInTheAlertSavesAsAStop() {
        #expect(RecordingEnd.decide(.stop, facts: Self.facts(duration: 6), waitTimedOut: false) == .keep(notice: nil))
    }

    @Test(arguments: [
        (RecordingEndKind.diskFull, "Your disk is almost full."),
        (.sleep, "Your Mac went to sleep."),
        (.userSwitch, "Another user took over the screen."),
        (.windowClosed, "The recorded window closed."),
        (.failed("The stream stopped."), "The stream stopped."),
    ])
    func everyOtherEndKeepsAPlayableFileWithItsReason(kind: RecordingEndKind, reason: String) {
        #expect(kind.reason == reason)
        #expect(RecordingEnd.decide(kind, facts: tenSeconds, waitTimedOut: false)
            == .keep(notice: RecordingNotice(title: "Recording stopped", body: reason)))
    }

    @Test func theUsersOwnStopAndCancelHaveNoReason() {
        #expect(RecordingEndKind.stop.reason == nil)
        #expect(RecordingEndKind.discardingCancel.reason == nil)
    }

    @Test func unplayableFileAfterTheDiskCheckFailsWithTheDiskText() {
        #expect(RecordingEnd.decide(.diskFull, facts: unplayable, waitTimedOut: false)
            == .remove(notice: RecordingNotice(title: "Recording failed", body: "Your disk is almost full.")))
    }

    @Test func startFailureIsRecordingFailedWithTheDescription() {
        #expect(RecordingEnd.startFailure("The display is no longer connected.")
            == RecordingNotice(title: "Recording failed", body: "The display is no longer connected."))
    }

    @Test func titlesAndAlertText() {
        #expect(RecordingEnd.stoppedTitle == "Recording stopped")
        #expect(RecordingEnd.failedTitle == "Recording failed")
        #expect(RecordingEnd.refusalTitle == "Screen recording")
        #expect(RecordingEnd.tooShortText == "The recording is too short.")
        #expect(RecordingEnd.discardQuestion == "Discard this recording?")
        #expect(RecordingEnd.discardDetail(elapsed: 65.4) == "1:05 of recording will be deleted.")
    }
}
