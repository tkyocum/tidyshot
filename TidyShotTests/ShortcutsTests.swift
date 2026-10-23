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
        #expect(AppCoordinator.recordingShortcutAction(for: .idle) == .start)
        #expect(AppCoordinator.recordingShortcutAction(for: .countIn) == .cancelCountIn)
        #expect(AppCoordinator.recordingShortcutAction(for: .recording) == .stop)
        #expect(AppCoordinator.recordingShortcutAction(for: .saving) == .start)
    }

    /// The Escape name serves scrolling and the self-timer now; the stored name is the old one,
    /// so nothing in UserDefaults moves.
    @Test func cancelCaptureKeepsTheStoredNameOfTheScrollingEscape() {
        #expect(KeyboardShortcuts.Name.cancelCapture.rawValue == "cancelScrollingCapture")
        #expect(KeyboardShortcuts.Name.cancelCapture.initialShortcut == .init(.escape))
    }
}
