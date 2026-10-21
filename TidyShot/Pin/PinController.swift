import AppKit

/// Owns the pinned screenshots (spec 2.9): one `PinPanel` per pin, in memory only. The panels
/// close at quit and are not restored.
final class PinController {
    struct Actions {
        var copyImage: (UUID) -> Void
        var saveAs: (UUID) -> Void
        var annotate: (UUID) -> Void
    }

    private final class Pin {
        let recordID: UUID
        let panel: PinPanel
        let view: PinView
        let imagePoints: CGSize
        var opacity = 1.0
        var isLocked = false

        init(recordID: UUID, panel: PinPanel, view: PinView, imagePoints: CGSize) {
            self.recordID = recordID
            self.panel = panel
            self.view = view
            self.imagePoints = imagePoints
        }
    }

    private var pins: [Pin] = []

    var hasPins: Bool { !pins.isEmpty }
    var hasLockedPins: Bool { pins.contains { $0.isLocked } }

    /// Orders the first pin of the record to the front. False when it has none.
    func bringToFront(recordID: UUID) -> Bool {
        guard let pin = pins.first(where: { $0.recordID == recordID }) else { return false }
        pin.panel.orderFrontRegardless()
        return true
    }

    /// Opens a pin showing `image` at `frame`. It is ordered front without becoming key: the
    /// user's app keeps the keyboard until the pin is clicked.
    func open(recordID: UUID, image: CGImage, imagePoints: CGSize, frame: CGRect, actions: Actions) {
        let panel = PinPanel(contentRect: frame)
        let view = PinView(image: image)
        let pin = Pin(recordID: recordID, panel: panel, view: view, imagePoints: imagePoints)
        panel.contentView = view
        panel.contentAspectRatio = imagePoints
        panel.contentMinSize = PinGeometry.minimumSize(aspect: imagePoints, initial: frame.size)
        panel.makeFirstResponder(view)

        view.onCommand = { [weak self, weak pin] command in
            guard let self, let pin else { return }
            switch command {
            case .nudge(let dx, let dy, let shift):
                pin.panel.setFrame(PinGeometry.nudged(pin.panel.frame, dx: dx, dy: dy, shift: shift), display: true)
            case .zoomIn:
                pin.panel.setFrame(PinGeometry.zoomed(pin.panel.frame, factor: PinGeometry.zoomStep,
                                                      visibleFrame: Self.visibleFrame(of: pin)), display: true)
            case .zoomOut:
                pin.panel.setFrame(PinGeometry.zoomed(pin.panel.frame, factor: 1 / PinGeometry.zoomStep,
                                                      visibleFrame: Self.visibleFrame(of: pin)), display: true)
            case .actualSize:
                pin.panel.setFrame(PinGeometry.actualSize(pin.panel.frame, imagePoints: pin.imagePoints,
                                                          visibleFrame: Self.visibleFrame(of: pin)), display: true)
            case .copyImage:
                actions.copyImage(pin.recordID)
            case .close:
                self.close(pin)
            }
        }
        view.onOpacitySteps = { [weak pin] steps in
            guard let pin else { return }
            Self.setOpacity(PinOpacity.changed(pin.opacity, steps: steps), of: pin)
        }
        view.onOpacity = { [weak pin] opacity in
            guard let pin else { return }
            Self.setOpacity(opacity, of: pin)
        }
        view.menuState = { [weak pin] in pin?.opacity ?? 1.0 }
        view.onSaveAs = { actions.saveAs(recordID) }
        view.onAnnotate = { actions.annotate(recordID) }
        view.onLock = { [weak pin] in
            guard let pin else { return }
            Self.lock(pin)
        }

        pins.append(pin)
        panel.orderFrontRegardless()
        // A window capture's transparent corners cast the right shadow.
        panel.invalidateShadow()
    }

    /// Closes every pin of the record.
    func close(recordID: UUID) {
        for pin in pins.filter({ $0.recordID == recordID }) { close(pin) }
    }

    func closeAll() {
        for pin in pins { close(pin) }
    }

    /// Makes every locked pin take clicks again, with its border.
    func unlockAll() {
        for pin in pins where pin.isLocked {
            pin.isLocked = false
            pin.panel.ignoresMouseEvents = false
            pin.view.showsBorder = true
        }
    }

    private func close(_ pin: Pin) {
        pin.panel.orderOut(nil)
        pins.removeAll { $0 === pin }
    }

    /// The visible frame of the pin's screen, or of the main screen when it is off all of them.
    private static func visibleFrame(of pin: Pin) -> CGRect {
        (pin.panel.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private static func setOpacity(_ opacity: Double, of pin: Pin) {
        pin.opacity = opacity
        pin.panel.alphaValue = opacity
    }

    /// A locked pin is click-through and borderless; the status menu is the way back.
    private static func lock(_ pin: Pin) {
        pin.isLocked = true
        pin.panel.ignoresMouseEvents = true
        pin.view.showsBorder = false
    }
}
