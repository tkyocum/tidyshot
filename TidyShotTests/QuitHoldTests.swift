import Testing
@testable import TidyShot

/// The quit hold (design, Quit, log out and restart): an unsaved editor, a count-in, a recording
/// or a recording's save keeps the app from quitting at once.
struct QuitHoldTests {
    @Test func idleWithNoUnsavedEditorDoesNotHold() {
        #expect(!AppCoordinator.holdsQuit(hasUnsavedEditors: false, recording: .idle))
    }

    @Test func unsavedEditorsHold() {
        #expect(AppCoordinator.holdsQuit(hasUnsavedEditors: true, recording: .idle))
    }

    @Test(arguments: [RecordingPhase.countIn, .recording, .saving])
    func everyRecordingPhaseButIdleHolds(_ phase: RecordingPhase) {
        #expect(AppCoordinator.holdsQuit(hasUnsavedEditors: false, recording: phase))
        #expect(AppCoordinator.holdsQuit(hasUnsavedEditors: true, recording: phase))
    }
}
