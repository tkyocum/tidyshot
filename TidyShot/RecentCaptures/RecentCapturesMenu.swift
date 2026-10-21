import AppKit

/// The Recent Captures submenu: the newest captures, up to 15, as custom rows, and the full-size
/// preview beside the submenu while a thumbnail is hovered. A row's buttons close the whole menu
/// and act once menu tracking has ended, so neither the delete alert nor the editor window opens
/// inside the menu's tracking loop.
final class RecentCapturesMenu: NSObject, NSMenuDelegate {
    static let limit = 15

    /// The status menu's "Recent Captures" item; its submenu is `menu`. Created once and added
    /// again on every rebuild, because a menu can be the submenu of only one item.
    let item = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Recent Captures")
    private let coordinator: AppCoordinator
    /// Cancels tracking of the status menu, which closes this submenu too.
    private let closeMenus: () -> Void
    private let previewPanel = PreviewPanel()
    /// The record whose thumbnail is under the mouse. A preview that finishes loading after the
    /// mouse moved on is dropped.
    private var hoveredID: UUID?
    /// The preview load for `hoveredID`. Cancelled when another thumbnail is hovered and whenever
    /// the preview hides, so moving the mouse down the rows does not leave full-file reads running.
    private var previewTask: Task<Void, Never>?
    /// Where the status item is on screen, read each time a preview is placed, so the preview
    /// goes on the side of the submenu away from the status menu.
    private let statusItemFrame: () -> CGRect?

    init(coordinator: AppCoordinator, closeMenus: @escaping () -> Void, statusItemFrame: @escaping () -> CGRect?) {
        self.coordinator = coordinator
        self.closeMenus = closeMenus
        self.statusItemFrame = statusItemFrame
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.submenu = menu
    }

    /// Fills the submenu from the history; called by `StatusMenuController` each time the status
    /// menu opens. Rows show their records as they were at that moment.
    func rebuild() {
        hidePreview()
        menu.removeAllItems()
        let records = coordinator.history.records.prefix(Self.limit)
        guard !records.isEmpty else {
            let empty = NSMenuItem(title: "No captures yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let now = Date()
        let actions = makeActions()
        let saveFolder = coordinator.saveLocation.currentURL
        let retainedID = coordinator.retainedCaptureID
        for record in records {
            let row = NSMenuItem()
            row.view = RecentCaptureMenuItemView(record: record, now: now, saveFolder: saveFolder, retainedID: retainedID,
                                                 provider: coordinator.thumbnailProvider,
                                                 actions: actions, onThumbnailHover: { [weak self] view, inside in
                                                     self?.thumbnailHover(view, inside: inside)
                                                 })
            menu.addItem(row)
        }
    }

    /// Hides the preview; also called by `StatusMenuController` when the status menu closes.
    func hidePreview() {
        hoveredID = nil
        previewTask?.cancel()
        previewTask = nil
        previewPanel.hide()
    }

    // MARK: NSMenuDelegate

    func menuDidClose(_ menu: NSMenu) {
        hidePreview()
    }

    // MARK: Preview

    /// Loads the preview (up to 1200 px, off the main thread, cached by `ThumbnailProvider`) and
    /// shows it beside the submenu, level with the hovered row, on the side away from the status
    /// menu. The row view's window is the submenu's window, so its frame says where the submenu is
    /// on screen. Hovering another thumbnail cancels the load still running for the last one.
    private func thumbnailHover(_ view: RecentCaptureMenuItemView, inside: Bool) {
        guard inside else {
            if hoveredID == view.recordID { hidePreview() }
            return
        }
        guard let record = coordinator.history.record(id: view.recordID) else { return }
        hoveredID = record.id
        let provider = coordinator.thumbnailProvider
        previewTask?.cancel()
        previewTask = Task { [weak self, weak view] in
            let image = await provider.preview(for: record)
            guard !Task.isCancelled, let self, let view, let image, self.hoveredID == record.id,
                  let menuWindow = view.window, let screen = menuWindow.screen ?? NSScreen.main else { return }
            let rowFrame = menuWindow.convertToScreen(view.convert(view.bounds, to: nil))
            let frame = PreviewPlacement.frame(imageSize: image.size, menuFrame: menuWindow.frame, rowFrame: rowFrame,
                                               statusItemFrame: self.statusItemFrame(), visibleFrame: screen.visibleFrame)
            self.previewPanel.show(image, frame: frame)
        }
    }

    // MARK: Actions

    private func makeActions() -> RecentCaptureActions {
        RecentCaptureActions(
            copyLinkOrFile: { [weak self] id in self?.afterMenusClose { $0.copyLinkOrFile(recordID: id) } },
            annotate: { [weak self] id in self?.afterMenusClose { $0.openEditor(recordID: id) } },
            copyLink: { [weak self] id in self?.afterMenusClose { $0.copyLink(recordID: id) } },
            copyImage: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.copyImage(recordID: id) } } },
            delete: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.deleteCapture(recordID: id) } } })
    }

    /// Closes the menus, then runs `work` when the run loop is back in its default mode, that is,
    /// after menu tracking has ended (`perform(inModes:)` does not run in the menu's
    /// event-tracking mode).
    private func afterMenusClose(_ work: @escaping @MainActor (AppCoordinator) -> Void) {
        hidePreview()
        closeMenus()
        let coordinator = coordinator
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { work(coordinator) }
        }
    }
}
