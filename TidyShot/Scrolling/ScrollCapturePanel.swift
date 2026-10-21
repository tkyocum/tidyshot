import AppKit
import SwiftUI

/// The scrolling capture's control panel (spec 2.8, The session): the live preview, the size
/// readout, the status line and the buttons. Floating and non-activating, so the user can click
/// their own app to scroll; it can become key while TidyShot is active, so Return and Escape reach
/// its buttons. The controller sizes and places it.
final class ScrollCapturePanel: NSPanel {
    init(session: ScrollCaptureSession) {
        super.init(contentRect: CGRect(x: 0, y: 0, width: ScrollPanelGeometry.panelWidth,
                                       height: ScrollPanelGeometry.minimumHeight),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        let host = NSHostingView(rootView: ScrollCaptureView(session: session))
        // The panel's frame sizes the view, not the reverse.
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
