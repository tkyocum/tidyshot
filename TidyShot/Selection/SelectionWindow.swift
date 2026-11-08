import AppKit

/// Transparent, borderless window covering one screen, above everything else.
final class SelectionWindow: NSWindow {
    /// CoreGraphics display id of the screen this window covers.
    let displayID: CGDirectDisplayID
    /// The window's one view, covering it.
    let view: SelectionView

    init(screen: NSScreen) {
        displayID = screen.displayID ?? CGMainDisplayID()
        view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
