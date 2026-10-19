import AppKit

/// Shows one Quick Access panel for the latest capture, updates it as the upload progresses,
/// and closes it a few seconds after the upload settles (unless the mouse is over it).
final class QuickAccessController {
    struct Actions {
        var copy: (UUID) -> Void
        var retry: (UUID) -> Void
        var reveal: (UUID) -> Void
    }

    private var panel: QuickAccessPanel?
    private var model: QuickAccessModel?
    private var closeTask: Task<Void, Never>?
    private var autoCloseSeconds: Double = 5

    func show(record: CaptureRecord, thumbnail: NSImage?, corner: OverlayCorner, autoCloseSeconds: Double, actions: Actions) {
        close()
        let model = QuickAccessModel(record: record, thumbnail: thumbnail)
        model.onCopy = { actions.copy(record.id) }
        model.onRetry = { actions.retry(record.id) }
        model.onReveal = { actions.reveal(record.id) }
        model.onClose = { [weak self] in self?.close() }
        self.model = model
        self.autoCloseSeconds = autoCloseSeconds

        let panel = QuickAccessPanel(model: model)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(OverlayGeometry.frame(size: QuickAccessView.size, corner: corner, in: screen.visibleFrame), display: false)
        panel.orderFrontRegardless()
        self.panel = panel

        if model.isSettled {
            scheduleClose()
        }
    }

    /// Pushes a new record state into the visible panel, if it shows that record.
    func update(record: CaptureRecord) {
        guard let model, model.record.id == record.id else { return }
        model.record = record
        if model.isSettled {
            scheduleClose()
        }
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    /// Waits `autoCloseSeconds`, then keeps waiting while the mouse is over the panel.
    private func scheduleClose() {
        closeTask?.cancel()
        let seconds = autoCloseSeconds
        guard seconds > 0 else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            while !Task.isCancelled, self?.model?.isHovered == true {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}
