import AppKit
import SwiftUI

/// The recording's control bar (design, Control panel). Floating, non-activating and on every
/// Space; it never becomes key, so the user's app keeps its keys and menus while it records, and
/// it can be dragged by its background. The recording leaves it out, so moving it changes nothing
/// in the video.
final class RecordingPanel: NSPanel {
    init(model: RecordingPanelModel) {
        // `RecordingScreenChrome.show` sets the frame, at its bar's size.
        super.init(contentRect: .zero,
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        // isFloatingPanel resets the level to .floating, so it comes first.
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: RecordingPanelView(model: model))
        // The panel's frame sizes the view, not the reverse.
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
