import AppKit
import SwiftUI

/// Floating, non-activating card in the Quick Access stack. Visible on every Space, including
/// over full-screen apps, and never steals focus from the app the user is working in. The stack
/// places its cards, so dragging one does not move it.
final class QuickAccessPanel: NSPanel {
    init(model: QuickAccessModel) {
        super.init(contentRect: CGRect(origin: .zero, size: QuickAccessView.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        contentView = NSHostingView(rootView: QuickAccessView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
