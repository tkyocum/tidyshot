import AppKit
import SwiftUI

/// The scrolling capture's control panel (spec 2.8, The session): the live preview, the size
/// readout, the status line and the buttons. Floating and non-activating, so the user can click
/// their own app to scroll; it can become key while TidyShot is active, so Return and Escape reach
/// its buttons. The controller sizes and places it.
final class ScrollCapturePanel: OverlayPanel {
    init(session: ScrollCaptureSession, onAllowAutoScroll: @escaping () -> Void) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: ScrollPanelGeometry.panelWidth, height: ScrollPanelGeometry.minimumHeight),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], level: .floating,
                   collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary], hasShadow: true, animationBehavior: .utilityWindow)
        let host = NSHostingView(rootView: ScrollCaptureView(session: session, onAllowAutoScroll: onAllowAutoScroll))
        // The panel's frame sizes the view, not the reverse.
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { true }
}
