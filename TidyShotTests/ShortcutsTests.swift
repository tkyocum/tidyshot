import KeyboardShortcuts
import Testing
@testable import TidyShot

struct ShortcutsTests {
    /// ⌃⇧5 sits next to the other three; Escape cancels a scrolling capture. No two names share a
    /// key or a default shortcut.
    @Test func scrollingShortcutsHaveTheirInitialKeys() {
        #expect(KeyboardShortcuts.Name.captureScrolling.initialShortcut == .init(.five, modifiers: [.control, .shift]))
        #expect(KeyboardShortcuts.Name.cancelCapture.initialShortcut == .init(.escape))
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureWindow, .captureFullscreen,
                                               .captureScrolling, .cancelCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count)
    }

    /// Restore Closed Overlay has a recorder in the Shortcuts tab but no default (spec 2.9).
    @Test func restoreOverlayHasNoInitialShortcut() {
        #expect(KeyboardShortcuts.Name.restoreOverlay.rawValue == "restoreOverlay")
        #expect(KeyboardShortcuts.Name.restoreOverlay.initialShortcut == nil)
    }

    /// ⌃⇧6 sits after ⌃⇧5. No two names share a key or a default shortcut (Restore Closed
    /// Overlay has none; `restoreOverlayHasNoInitialShortcut` checks that).
    @Test func capturePreviousAreaIsControlShiftSix() {
        #expect(KeyboardShortcuts.Name.capturePreviousArea.initialShortcut == .init(.six, modifiers: [.control, .shift]))
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureWindow, .captureFullscreen, .captureScrolling,
                                               .capturePreviousArea, .restoreOverlay, .cancelCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count - 1)
    }

    /// ⌃⇧1 sits before ⌃⇧2 to ⌃⇧6 (spec 2.9). No two names share a key or a default shortcut
    /// (Restore Closed Overlay has none).
    @Test func allInOneIsControlShiftOne() {
        #expect(KeyboardShortcuts.Name.allInOne.rawValue == "allInOne")
        #expect(KeyboardShortcuts.Name.allInOne.initialShortcut == .init(.one, modifiers: [.control, .shift]))
        let names: [KeyboardShortcuts.Name] = [.allInOne, .captureArea, .captureWindow, .captureFullscreen,
                                               .captureScrolling, .capturePreviousArea, .restoreOverlay,
                                               .cancelCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count - 1)
    }

    /// ⌃⇧7 sits after ⌃⇧6 (spec 2.10). No two names share a key or a default shortcut (Self-Timer
    /// and Restore Closed Overlay have none).
    @Test func captureTextIsControlShiftSeven() {
        #expect(KeyboardShortcuts.Name.captureText.rawValue == "captureText")
        #expect(KeyboardShortcuts.Name.captureText.initialShortcut == .init(.seven, modifiers: [.control, .shift]))
        let names: [KeyboardShortcuts.Name] = [.allInOne, .captureArea, .captureWindow, .captureFullscreen,
                                               .captureScrolling, .capturePreviousArea, .selfTimer, .captureText,
                                               .restoreOverlay, .cancelCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count - 2)
    }

    /// Self-Timer has a recorder in the Shortcuts tab but no default (spec 2.9), like Restore Closed Overlay.
    @Test func selfTimerHasNoInitialShortcut() {
        #expect(KeyboardShortcuts.Name.selfTimer.rawValue == "selfTimer")
        #expect(KeyboardShortcuts.Name.selfTimer.initialShortcut == nil)
    }

    /// ⌃⇧8 sits after ⌃⇧7 (recording design, Starting); Record Fullscreen has no default. No two
    /// names share a key or a default shortcut (Self-Timer, Restore Closed Overlay and Record
    /// Fullscreen have none).
    @Test func recordScreenIsControlShiftEight() {
        #expect(KeyboardShortcuts.Name.recordScreen.rawValue == "recordScreen")
        #expect(KeyboardShortcuts.Name.recordScreen.initialShortcut == .init(.eight, modifiers: [.control, .shift]))
        #expect(KeyboardShortcuts.Name.recordFullscreen.rawValue == "recordFullscreen")
        #expect(KeyboardShortcuts.Name.recordFullscreen.initialShortcut == nil)
        let names: [KeyboardShortcuts.Name] = [.allInOne, .captureArea, .captureWindow, .captureFullscreen,
                                               .captureScrolling, .capturePreviousArea, .selfTimer, .captureText,
                                               .recordScreen, .recordFullscreen, .restoreOverlay, .cancelCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count - 3)
    }

    /// Either record shortcut cancels a count-in and stops a recording, whichever started it. Idle,
    /// or while a recording is saved, it starts a new one.
    @Test func recordShortcutsStartCancelOrStopByPhase() {
        #expect(AppCoordinator.recordingShortcutAction(for: .idle, askingPermission: nil) == .start)
        #expect(AppCoordinator.recordingShortcutAction(for: .countIn, askingPermission: nil) == .cancelCountIn)
        #expect(AppCoordinator.recordingShortcutAction(for: .recording, askingPermission: nil) == .stop)
        #expect(AppCoordinator.recordingShortcutAction(for: .saving, askingPermission: nil) == .start)
    }

    /// While a start waits on the microphone or the camera prompt, another start is ignored (R3
    /// design, Permission). Nothing counts in or records then; were it so, the shortcut would still
    /// cancel or stop.
    @Test(arguments: [PermissionPrompt.microphone, .camera])
    func aStartWhileAPromptIsOpenIsIgnored(prompt: PermissionPrompt) {
        #expect(AppCoordinator.recordingShortcutAction(for: .idle, askingPermission: prompt) == .ignore)
        #expect(AppCoordinator.recordingShortcutAction(for: .saving, askingPermission: prompt) == .ignore)
        #expect(AppCoordinator.recordingShortcutAction(for: .countIn, askingPermission: prompt) == .cancelCountIn)
        #expect(AppCoordinator.recordingShortcutAction(for: .recording, askingPermission: prompt) == .stop)
    }

    /// Before the capture lock (R2 design, At the start), for either prompt: a start with no access
    /// to ask for goes on, also while another capture runs, whose lock then refuses it; one that would
    /// prompt while another capture runs ends there, with no prompt; otherwise the prompt shows.
    @Test func aPromptShowsOnlyWithNoCaptureRunning() {
        #expect(AppCoordinator.permissionPromptStep(asksForAccess: true, isCapturing: false) == .prompt)
        #expect(AppCoordinator.permissionPromptStep(asksForAccess: true, isCapturing: true) == .end)
        #expect(AppCoordinator.permissionPromptStep(asksForAccess: false, isCapturing: false) == .goOn)
        #expect(AppCoordinator.permissionPromptStep(asksForAccess: false, isCapturing: true) == .goOn)
    }

    /// The prompts a start shows (plan Gap 9): the microphone first, then the camera, then on to
    /// the lock.
    @Test func aStartAsksForTheMicrophoneThenTheCamera() {
        #expect(AppCoordinator.startPrompts(microphone: true, camera: true) == [.microphone, .camera])
        #expect(AppCoordinator.startPrompts(microphone: false, camera: true) == [.camera])
        #expect(AppCoordinator.startPrompts(microphone: true, camera: false) == [.microphone])
        #expect(AppCoordinator.startPrompts(microphone: false, camera: false) == [])
    }

    /// Settings asks only with nothing recording, no capture holding the lock and no prompt open;
    /// otherwise it defers to the next start (R3 design, Asking from Settings; plan Gap 8).
    @Test func aSettingsPromptWaitsWhileACaptureRecordingOrPromptRuns() {
        #expect(AppCoordinator.settingsPromptStep(phase: .idle, isCapturing: false, askingPermission: nil) == .ask)
        for phase in [RecordingPhase.countIn, .recording, .saving] {
            #expect(AppCoordinator.settingsPromptStep(phase: phase, isCapturing: false, askingPermission: nil) == .wait)
        }
        #expect(AppCoordinator.settingsPromptStep(phase: .idle, isCapturing: true, askingPermission: nil) == .wait)
        #expect(AppCoordinator.settingsPromptStep(phase: .idle, isCapturing: false, askingPermission: .microphone) == .wait)
        #expect(AppCoordinator.settingsPromptStep(phase: .idle, isCapturing: false, askingPermission: .camera) == .wait)
    }

    /// The names the log lines give each prompt.
    @Test func eachPromptHasItsName() {
        #expect(PermissionPrompt.microphone.name == "microphone")
        #expect(PermissionPrompt.camera.name == "camera")
    }

    /// One rule for the capture lock, the status menu's capture items and the URL commands (R2
    /// design, Decided 2026-10-24, 9; R3 design, Permission): a capture is refused while another
    /// runs and while a start or Settings waits on the microphone or the camera prompt.
    @Test func aCaptureIsRefusedWhileAnotherRunsOrAPromptIsOpen() {
        #expect(!AppCoordinator.refusesCapture(isCapturing: false, askingPermission: nil))
        #expect(AppCoordinator.refusesCapture(isCapturing: true, askingPermission: nil))
        #expect(AppCoordinator.refusesCapture(isCapturing: false, askingPermission: .microphone))
        #expect(AppCoordinator.refusesCapture(isCapturing: false, askingPermission: .camera))
        #expect(AppCoordinator.refusesCapture(isCapturing: true, askingPermission: .microphone))
        #expect(AppCoordinator.refusesCapture(isCapturing: true, askingPermission: .camera))
    }

    /// The URL handler's log gives the reason (R4 design, What `record-screen` does in each phase):
    /// a count-in or a recording first, each named, then a capture holding the lock, also while idle
    /// or saving, then the open prompt, named.
    @Test func aRefusedCaptureNamesTheRecordingThenTheLockThenThePrompt() {
        for prompt in [nil, PermissionPrompt.microphone, .camera] {
            #expect(AppCoordinator.captureRefusal(isCapturing: true, askingPermission: prompt, recordingPhase: .countIn)
                    == .recordingStarting)
            #expect(AppCoordinator.captureRefusal(isCapturing: true, askingPermission: prompt, recordingPhase: .recording)
                    == .recordingRunning)
            for phase in [RecordingPhase.idle, .saving] {
                #expect(AppCoordinator.captureRefusal(isCapturing: true, askingPermission: prompt, recordingPhase: phase)
                        == .captureRunning)
            }
        }
        for phase in [RecordingPhase.idle, .saving] {
            #expect(AppCoordinator.captureRefusal(isCapturing: false, askingPermission: nil, recordingPhase: phase) == nil)
            #expect(AppCoordinator.captureRefusal(isCapturing: false, askingPermission: .microphone, recordingPhase: phase)
                    == .permissionPrompt(.microphone))
            #expect(AppCoordinator.captureRefusal(isCapturing: false, askingPermission: .camera, recordingPhase: phase)
                    == .permissionPrompt(.camera))
        }
    }

    /// `record-screen` only starts (R4 design, What `record-screen` does in each phase): idle or
    /// while an earlier recording is saved, never with a prompt open nor while quitting.
    @Test func aURLStartRunsOnlyIdleOrSavingWithNoPromptAndNoQuit() {
        for phase in [RecordingPhase.idle, .saving, .countIn, .recording] {
            let starts = phase == .idle || phase == .saving
            #expect(AppCoordinator.recordingStartsFromURL(phase: phase, askingPermission: nil, isQuitting: false) == starts)
            #expect(!AppCoordinator.recordingStartsFromURL(phase: phase, askingPermission: nil, isQuitting: true))
            for prompt in [PermissionPrompt.microphone, .camera] {
                #expect(!AppCoordinator.recordingStartsFromURL(phase: phase, askingPermission: prompt, isQuitting: false))
                #expect(!AppCoordinator.recordingStartsFromURL(phase: phase, askingPermission: prompt, isQuitting: true))
            }
        }
    }

    /// `stop-recording` stops a recording and cancels a count-in, and otherwise does nothing; it
    /// never starts one (R4 design, What `stop-recording` does in each phase).
    @Test func stopRecordingStopsOrCancelsByPhase() {
        #expect(AppCoordinator.recordingStopCommandAction(for: .recording) == .stop)
        #expect(AppCoordinator.recordingStopCommandAction(for: .countIn) == .cancelCountIn)
        #expect(AppCoordinator.recordingStopCommandAction(for: .idle) == .nothing)
        #expect(AppCoordinator.recordingStopCommandAction(for: .saving) == .nothing)
    }

    /// The reason a deferred Settings prompt logs (R4 design, The Settings prompt's deferral
    /// reason): an open prompt first, then a capture holding the lock (a count-in and a recording
    /// always hold it), then a save in flight; nil when nothing defers.
    @Test func aDeferredSettingsPromptGivesItsTrueReason() {
        for phase in [RecordingPhase.idle, .countIn, .recording, .saving] {
            for isCapturing in [false, true] {
                #expect(AppCoordinator.settingsPromptDeferralReason(phase: phase, isCapturing: isCapturing,
                                                                    askingPermission: .microphone)
                        == "the microphone prompt is open")
                #expect(AppCoordinator.settingsPromptDeferralReason(phase: phase, isCapturing: isCapturing,
                                                                    askingPermission: .camera)
                        == "the camera prompt is open")
            }
        }
        for phase in [RecordingPhase.idle, .countIn, .recording, .saving] {
            #expect(AppCoordinator.settingsPromptDeferralReason(phase: phase, isCapturing: true, askingPermission: nil)
                    == "a capture is running")
        }
        #expect(AppCoordinator.settingsPromptDeferralReason(phase: .saving, isCapturing: false, askingPermission: nil)
                == "a recording is being saved")
        #expect(AppCoordinator.settingsPromptDeferralReason(phase: .idle, isCapturing: false, askingPermission: nil) == nil)
    }

    /// A record start the capture lock refuses posts only when it showed the microphone or the
    /// camera prompt, which the user answered; one that showed none ends silently, as any capture the
    /// lock refuses.
    @Test func aRefusedStartPostsOnlyAfterAPrompt() {
        #expect(AppCoordinator.lockRefusalNotice(afterPrompt: true)
                == RecordingNotice(title: "Screen recording",
                                   body: "The recording did not start because another capture was running."))
        #expect(AppCoordinator.lockRefusalNotice(afterPrompt: true)?.title == RecordingEnd.refusalTitle)
        #expect(AppCoordinator.lockRefusalNotice(afterPrompt: false) == nil)
    }

    /// The Escape name serves scrolling and the self-timer now; the stored name is the old one,
    /// so nothing in UserDefaults moves.
    @Test func cancelCaptureKeepsTheStoredNameOfTheScrollingEscape() {
        #expect(KeyboardShortcuts.Name.cancelCapture.rawValue == "cancelScrollingCapture")
        #expect(KeyboardShortcuts.Name.cancelCapture.initialShortcut == .init(.escape))
    }
}
