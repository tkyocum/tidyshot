import AppKit

/// A pinned screenshot's window (spec 2.9): borderless, floating above other windows on every
/// Space, resizable from its edges, and able to become key when clicked without making TidyShot
/// the active app, so the user's own app keeps its menus until then.
final class PinPanel: OverlayPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .resizable], level: .floating,
                   collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary], hasShadow: true)
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool { true }
}
