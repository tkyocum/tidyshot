import AppKit
import SwiftUI

/// Floating, non-activating card in the Quick Access stack. Visible on every Space, including
/// over full-screen apps, and never steals focus from the app the user is working in. The stack
/// places its cards, so dragging one does not move it.
final class QuickAccessPanel: OverlayPanel {
    init(model: QuickAccessModel) {
        super.init(contentRect: CGRect(origin: .zero, size: QuickAccessView.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], level: .floating,
                   collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .transient], hasShadow: true,
                   animationBehavior: .utilityWindow)
        contentView = NSHostingView(rootView: QuickAccessView(model: model))
    }
}
