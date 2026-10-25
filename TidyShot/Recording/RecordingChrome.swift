import AppKit

/// What a recording puts on screen: the control panel, the dashed frame of an area recording, and
/// the Cancel question. `RecordingScreenChrome` is the real one; tests use a fake.
protocol RecordingChrome: AnyObject {
    /// The panel and the frame, for the filter's fallback exclusion. Valid once shown.
    var windowNumbers: Set<CGWindowID> { get }
    /// Orders the frame and the panel front, laid out as `bar`, with Stop enabled, the time at
    /// `0:00` and the sound not muted. `onMute` is the mute button's, which only the mute bar has.
    func show(onStop: @escaping () -> Void, onCancel: @escaping () -> Void, onMute: @escaping () -> Void,
              bar: RecordingPanelLayout.Bar)
    func update(elapsed: TimeInterval)
    /// Stop, Cancel and the mute button together.
    func setStopEnabled(_ enabled: Bool)
    /// The mute button's state.
    func setMuted(_ muted: Bool)
    /// `Discard this recording?` with `<m:ss> of recording will be deleted.`. True for Discard,
    /// false for Save.
    func askToDiscard(elapsed: TimeInterval) async -> Bool
    /// Answers a waiting `askToDiscard` with Save, for a quit. An alert not yet on screen never
    /// shows; one already on screen stays until answered, and that answer is ignored.
    func answerDiscardWithSave()
    func close()
}

/// Where the chrome goes, in AppKit global points: beside the area, beside the window's starting
/// frame (the panel does not follow the window), or at the bottom centre of the display.
enum RecordingChromePlacement {
    case area(CGRect, visibleFrame: CGRect)
    case window(CGRect, visibleFrame: CGRect)
    case fullscreen(visibleFrame: CGRect)
}

/// The real chrome (design, Frame and Control panel). Only an area recording is outlined: a
/// window can move or resize, and the frame is fixed.
final class RecordingScreenChrome: RecordingChrome {
    private let model = RecordingPanelModel()
    private let panel: RecordingPanel
    private let frameWindow: ScrollAreaFrameWindow?
    /// Kept until `show`, which knows the bar and so the panel's size.
    private let placement: RecordingChromePlacement
    /// `askToDiscard`'s answer, from its call until the alert or a quit gives it.
    private var discardAnswer: CheckedContinuation<Bool, Never>?

    init(placement: RecordingChromePlacement) {
        self.placement = placement
        if case .area(let area, _) = placement {
            frameWindow = ScrollAreaFrameWindow(area: area)
        } else {
            frameWindow = nil
        }
        panel = RecordingPanel(model: model)
    }

    /// The panel's frame for a bar of `size` at `placement`.
    private static func panelFrame(size: CGSize, placement: RecordingChromePlacement) -> CGRect {
        switch placement {
        case .area(let area, let visibleFrame):
            ScrollPanelGeometry.frame(panelSize: size, area: area, visibleFrame: visibleFrame)
        case .window(let frame, let visibleFrame):
            ScrollPanelGeometry.frame(panelSize: size, area: frame, visibleFrame: visibleFrame)
        case .fullscreen(let visibleFrame):
            ScrollPanelGeometry.bottomCentre(panelSize: size, visibleFrame: visibleFrame)
        }
    }

    var windowNumbers: Set<CGWindowID> {
        let windows: [NSWindow] = [panel] + (frameWindow.map { [$0] } ?? [])
        return Set(windows.compactMap { $0.isVisible && $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
    }

    func show(onStop: @escaping () -> Void, onCancel: @escaping () -> Void, onMute: @escaping () -> Void,
              bar: RecordingPanelLayout.Bar) {
        model.onStop = onStop
        model.onCancel = onCancel
        model.onMute = onMute
        model.elapsed = 0
        model.stopEnabled = true
        model.isMuted = false
        model.bar = bar
        panel.setFrame(Self.panelFrame(size: RecordingPanelLayout.size(of: bar), placement: placement), display: false)
        frameWindow?.orderFrontRegardless()
        panel.orderFrontRegardless()
    }

    func update(elapsed: TimeInterval) {
        model.elapsed = elapsed
    }

    func setStopEnabled(_ enabled: Bool) {
        model.stopEnabled = enabled
    }

    func setMuted(_ muted: Bool) {
        model.isMuted = muted
    }

    /// Runs as `confirmRemoveFromHistory` does: in a block the run loop performs only in its
    /// default mode, so `runModal()` never starts inside a menu's tracking loop, with TidyShot
    /// activated so the alert takes Return. Save is the default; Discard has no key. While AppKit
    /// holds a quit the run loop stays out of that mode, so the quit answers with
    /// `answerDiscardWithSave()` and the block, when it runs, shows nothing.
    func askToDiscard(elapsed: TimeInterval) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            discardAnswer = done
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    guard self.discardAnswer != nil else { return }
                    let alert = NSAlert()
                    alert.messageText = RecordingEnd.discardQuestion
                    alert.informativeText = RecordingEnd.discardDetail(elapsed: elapsed)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Save")
                    let discard = alert.addButton(withTitle: "Discard")
                    discard.hasDestructiveAction = true
                    discard.keyEquivalent = ""
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    self.answerDiscard(alert.runModal() == .alertSecondButtonReturn)
                }
            }
        }
    }

    func answerDiscardWithSave() {
        answerDiscard(false)
    }

    /// Gives `askToDiscard` its answer, once.
    private func answerDiscard(_ discards: Bool) {
        discardAnswer?.resume(returning: discards)
        discardAnswer = nil
    }

    func close() {
        model.onStop = {}
        model.onCancel = {}
        model.onMute = {}
        panel.orderOut(nil)
        frameWindow?.orderOut(nil)
    }
}
