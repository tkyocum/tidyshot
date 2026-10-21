import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", initial: .init(.four, modifiers: [.control, .shift]))
    static let captureWindow = Self("captureWindow", initial: .init(.two, modifiers: [.control, .shift]))
    static let captureFullscreen = Self("captureFullscreen", initial: .init(.three, modifiers: [.control, .shift]))
    static let captureScrolling = Self("captureScrolling", initial: .init(.five, modifiers: [.control, .shift]))
    static let capturePreviousArea = Self("capturePreviousArea", initial: .init(.six, modifiers: [.control, .shift]))
    /// Restore Closed Overlay. No default; the Shortcuts tab records one.
    static let restoreOverlay = Self("restoreOverlay")
    /// Escape, live only while a scrolling capture runs (disabled at launch). It has no recorder
    /// row: the recorder refuses keys without modifiers, the hotkey itself does not.
    static let cancelScrollingCapture = Self("cancelScrollingCapture", initial: .init(.escape))
}
