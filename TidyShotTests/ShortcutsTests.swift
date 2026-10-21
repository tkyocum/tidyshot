import KeyboardShortcuts
import Testing
@testable import TidyShot

struct ShortcutsTests {
    /// ⌃⇧5 sits next to the other three; Escape cancels a scrolling capture. No two names share a
    /// key or a default shortcut.
    @Test func scrollingShortcutsHaveTheirInitialKeys() {
        #expect(KeyboardShortcuts.Name.captureScrolling.initialShortcut == .init(.five, modifiers: [.control, .shift]))
        #expect(KeyboardShortcuts.Name.cancelScrollingCapture.initialShortcut == .init(.escape))
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureWindow, .captureFullscreen,
                                               .captureScrolling, .cancelScrollingCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count)
    }

    /// Restore Closed Overlay has a recorder in the Shortcuts tab but no default (spec 2.9).
    @Test func restoreOverlayHasNoInitialShortcut() {
        #expect(KeyboardShortcuts.Name.restoreOverlay.rawValue == "restoreOverlay")
        #expect(KeyboardShortcuts.Name.restoreOverlay.initialShortcut == nil)
    }
}
