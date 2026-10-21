import AppKit

/// Shows one Quick Access panel for the latest capture, updates it as the upload progresses,
/// and closes it a few seconds after the upload settles (unless the mouse is over it).
final class QuickAccessController {
    struct Actions {
        var copy: (UUID) -> Void
        var retry: (UUID) -> Void
        var reveal: (UUID) -> Void
        /// Deletes the capture everywhere after one confirmation; see `AppCoordinator.deleteCapture`.
        var delete: (UUID) -> Void
        /// Opens the annotation editor; see `AppCoordinator.openEditor(recordID:)`. Stays enabled
        /// while the upload runs.
        var annotate: (UUID) -> Void
    }

    /// Called with the record's id each time a panel closes, whatever closed it: the Close button,
    /// the auto-close timer, a delete, the editor opening, or the next capture's panel replacing it.
    var onDidClose: ((UUID) -> Void)?

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
        model.onDelete = { actions.delete(record.id) }
        model.onAnnotate = { actions.annotate(record.id) }
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
        } else {
            closeTask?.cancel()
            closeTask = nil
        }
    }

    /// Closes the panel if it shows `recordID` (the capture was deleted).
    func close(recordID: UUID) {
        guard model?.record.id == recordID else { return }
        close()
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        let closedID = model?.record.id
        panel?.orderOut(nil)
        panel = nil
        model = nil
        if let closedID {
            onDidClose?(closedID)
        }
    }

    /// Waits `autoCloseSeconds`; while the mouse is over the panel the countdown restarts.
    private func scheduleClose() {
        closeTask?.cancel()
        let seconds = autoCloseSeconds
        guard seconds > 0 else { return }
        closeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                if self?.model?.isHovered == true { continue }
                break
            }
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}
