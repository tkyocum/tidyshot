import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// The seconds the badge shows.
@Observable
final class SelfTimerModel {
    var seconds = 0
}

/// The countdown badge (spec 2.9, Self-Timer): the seconds left and how to cancel.
struct SelfTimerBadge: View {
    let model: SelfTimerModel

    var body: some View {
        VStack(spacing: 2) {
            Text("\(model.seconds)")
                .font(.system(size: 48, weight: .semibold).monospacedDigit())
            Text("Esc to cancel")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: SelfTimerGeometry.badgeSide, height: SelfTimerGeometry.badgeSide)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.seconds) seconds left")
    }
}

/// Borderless, non-activating and click-through, so the app the user is working in keeps the
/// focus, its menus and its keys during the countdown. Nothing excludes it from the capture: the
/// stage orders it and the dashed frame out, and waits for the screen to settle, before capturing.
final class SelfTimerPanel: NSPanel {
    init(model: SelfTimerModel, frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // isFloatingPanel resets the level to .floating, so it must come first.
        isFloatingPanel = true
        level = .screenSaver
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SelfTimerBadge(model: model))
        // The panel's frame sizes the view, not the reverse.
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The real stage: the badge and the dashed frame the scrolling capture uses, and the shared
/// Escape hotkey. `subject` and `screenFrame` are in AppKit global points. Without `showsFrame`
/// (a fullscreen recording's count-in) only the badge shows.
final class SelfTimerScreenStage: SelfTimerStage {
    private let model: SelfTimerModel
    private let panel: SelfTimerPanel
    private let frameWindow: ScrollAreaFrameWindow?

    init(subject: CGRect, screenFrame: CGRect, showsFrame: Bool = true) {
        // A local first: a class cannot read `self.model` before every stored property is set.
        let model = SelfTimerModel()
        self.model = model
        panel = SelfTimerPanel(model: model, frame: SelfTimerGeometry.badgeFrame(around: subject, in: screenFrame))
        frameWindow = showsFrame ? ScrollAreaFrameWindow(area: subject) : nil
    }

    func armEscape() {
        KeyboardShortcuts.enable(.cancelCapture)
    }

    func disarmEscape() {
        KeyboardShortcuts.disable(.cancelCapture)
    }

    func show(seconds: Int) {
        model.seconds = seconds
        frameWindow?.orderFrontRegardless()
        panel.orderFrontRegardless()
    }

    func tick(seconds: Int) {
        model.seconds = seconds
    }

    func dismiss() {
        panel.orderOut(nil)
        frameWindow?.orderOut(nil)
    }
}
