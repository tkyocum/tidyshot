import AppKit
import SwiftUI

/// Floating, non-activating panel in a screen corner. Visible on every Space, including over
/// full-screen apps, and never steals focus from the app the user is working in.
final class QuickAccessPanel: NSPanel {
    init(model: QuickAccessModel) {
        super.init(contentRect: CGRect(origin: .zero, size: QuickAccessView.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        contentView = NSHostingView(rootView: QuickAccessView(model: model))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
