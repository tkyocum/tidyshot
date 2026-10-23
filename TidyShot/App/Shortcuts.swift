import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// All-in-One (spec 2.9): the first capture item, ⌃⇧1.
    static let allInOne = Self("allInOne", initial: .init(.one, modifiers: [.control, .shift]))
    static let captureArea = Self("captureArea", initial: .init(.four, modifiers: [.control, .shift]))
    static let captureWindow = Self("captureWindow", initial: .init(.two, modifiers: [.control, .shift]))
    static let captureFullscreen = Self("captureFullscreen", initial: .init(.three, modifiers: [.control, .shift]))
    static let captureScrolling = Self("captureScrolling", initial: .init(.five, modifiers: [.control, .shift]))
    static let capturePreviousArea = Self("capturePreviousArea", initial: .init(.six, modifiers: [.control, .shift]))
    /// Capture Text (spec 2.10): ⌃⇧7, after ⌃⇧6.
    static let captureText = Self("captureText", initial: .init(.seven, modifiers: [.control, .shift]))
    /// Self-Timer. No default; the Shortcuts tab records one.
    static let selfTimer = Self("selfTimer")
    /// Restore Closed Overlay. No default; the Shortcuts tab records one.
    static let restoreOverlay = Self("restoreOverlay")
    /// Escape, live only while a scrolling capture or a self-timer countdown runs (disabled at
    /// launch). It has no recorder row: the recorder refuses keys without modifiers, the hotkey
    /// itself does not. The stored name is the one Phase 5 shipped, so nothing migrates.
    static let cancelCapture = Self("cancelScrollingCapture", initial: .init(.escape))
}
