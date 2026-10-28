import Foundation
import Testing
@testable import TidyShot

/// The one camera note after Stop (design, Webcam bubble, When the note posts; Notices and R2) and
/// the first-loss bookkeeping behind it.
struct CameraNoteTests {
    let startNote = RecordingNotice(title: "Recorded with TKY Camera", body: "Brio 500 is not connected.")
    let accessNote = RecordingNotice(title: "Recorded without the webcam bubble", body: "Camera access is off for TidyShot.")
    let notFilmed = RecordingNotice(title: "Recorded without the webcam bubble", body: "The bubble could not be filmed.")

    var losses: [CameraLoss?] { [nil, .couldNotStart, .stopped(at: 12, backAt: nil), .stopped(at: 12, backAt: 20)] }

    // MARK: The note

    /// The toggle off and the bar never pressed: nothing, whatever the access, the devices or a miss.
    @Test func noNoteWhenTheBubbleWasNeverWanted() {
        for start in [nil, startNote, accessNote] {
            for missed in [false, true] {
                for loss in losses {
                    #expect(CameraNote.afterStop(start: start, wanted: false, missed: missed, loss: loss) == nil)
                }
            }
        }
    }

    @Test func theStartsNoteWhenWanted() {
        #expect(CameraNote.afterStop(start: accessNote, wanted: true, missed: false, loss: nil) == accessNote)
        #expect(CameraNote.afterStop(start: startNote, wanted: true, missed: false, loss: nil) == startNote)
    }

    /// A recording never ends with two camera banners: the start's note wins over a miss and a loss.
    @Test func aLossAfterAStartNotePostsNothingMore() {
        for loss in losses {
            #expect(CameraNote.afterStop(start: startNote, wanted: true, missed: false, loss: loss) == startNote)
            #expect(CameraNote.afterStop(start: startNote, wanted: true, missed: true, loss: loss) == startNote)
        }
    }

    @Test func theLookupMissNote() {
        for loss in losses {
            #expect(CameraNote.afterStop(start: nil, wanted: true, missed: true, loss: loss) == notFilmed)
        }
    }

    @Test func theLossNoteWithAndWithoutTheCamerasReturn() {
        #expect(CameraNote.afterStop(start: nil, wanted: true, missed: false, loss: .stopped(at: 12, backAt: 20))
                == RecordingNotice(title: "Camera lost", body: "The camera stopped at 0:12. It came back at 0:20."))
        #expect(CameraNote.afterStop(start: nil, wanted: true, missed: false, loss: .stopped(at: 12, backAt: nil))
                == RecordingNotice(title: "Camera lost", body: "The camera stopped at 0:12. The bubble had no picture from there."))
    }

    @Test func aCameraThatCouldNotStart() {
        #expect(CameraNote.afterStop(start: nil, wanted: true, missed: false, loss: .couldNotStart)
                == RecordingNotice(title: "Recorded without the webcam bubble", body: "The camera could not be started."))
    }

    @Test func noNoteWhenWantedAndAllWentWell() {
        #expect(CameraNote.afterStop(start: nil, wanted: true, missed: false, loss: nil) == nil)
    }

    @Test func theLostBody() {
        #expect(CameraNote.lostTitle == "Camera lost")
        #expect(CameraNote.lostBody(at: 12, backAt: 20) == "The camera stopped at 0:12. It came back at 0:20.")
        #expect(CameraNote.lostBody(at: 12, backAt: nil) == "The camera stopped at 0:12. The bubble had no picture from there.")
        #expect(CameraNote.lostBody(at: 3725.4, backAt: nil) == "The camera stopped at 1:02:05. The bubble had no picture from there.")
    }

    // MARK: The tracker

    @Test func aTrackerStartsWithNoLoss() {
        let tracker = CameraLossTracker()
        #expect(tracker.loss == nil)
        #expect(!tracker.isClosed)
    }

    @Test func aLossThenAReturn() {
        var tracker = CameraLossTracker()
        tracker.lost(at: 12)
        #expect(tracker.loss == .stopped(at: 12, backAt: nil))
        tracker.back(at: 20)
        #expect(tracker.loss == .stopped(at: 12, backAt: 20))
    }

    @Test func aSecondLossAndASecondReturnChangeNothing() {
        var tracker = CameraLossTracker()
        tracker.lost(at: 12)
        tracker.lost(at: 15)
        #expect(tracker.loss == .stopped(at: 12, backAt: nil))
        tracker.back(at: 20)
        tracker.lost(at: 30)
        tracker.back(at: 40)
        #expect(tracker.loss == .stopped(at: 12, backAt: 20))
    }

    @Test func aCouldNotStartIsKeptOverALaterLoss() {
        var tracker = CameraLossTracker()
        tracker.couldNotStart()
        tracker.lost(at: 12)
        tracker.back(at: 20)
        tracker.couldNotStart()
        #expect(tracker.loss == .couldNotStart)
    }

    @Test func aLossIsKeptOverALaterCouldNotStart() {
        var tracker = CameraLossTracker()
        tracker.lost(at: 12)
        tracker.couldNotStart()
        #expect(tracker.loss == .stopped(at: 12, backAt: nil))
    }

    @Test func aReturnWithNoLossChangesNothing() {
        var tracker = CameraLossTracker()
        tracker.back(at: 20)
        #expect(tracker == CameraLossTracker())
        tracker.lost(at: 30)
        #expect(tracker.loss == .stopped(at: 30, backAt: nil))
    }

    @Test func afterCloseNothingChanges() {
        var closed = CameraLossTracker()
        closed.close()
        #expect(closed.isClosed)
        var tracker = closed
        tracker.lost(at: 12)
        tracker.back(at: 20)
        tracker.couldNotStart()
        #expect(tracker == closed)
        #expect(tracker.loss == nil)

        var lost = CameraLossTracker()
        lost.lost(at: 12)
        lost.close()
        let atClose = lost
        lost.back(at: 20)
        lost.lost(at: 30)
        lost.couldNotStart()
        lost.close()
        #expect(lost == atClose)
        #expect(lost.loss == .stopped(at: 12, backAt: nil))
    }
}
