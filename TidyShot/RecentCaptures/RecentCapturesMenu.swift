import AppKit

/// The Recent Captures submenu: the newest captures, up to 15, as custom rows. A row's buttons
/// close the whole menu and act once menu tracking has ended, so the delete alert never runs
/// inside the menu's tracking loop.
final class RecentCapturesMenu: NSObject {
    static let limit = 15

    /// The status menu's "Recent Captures" item; its submenu is `menu`. Created once and added
    /// again on every rebuild, because a menu can be the submenu of only one item.
    let item = NSMenuItem(title: "Recent Captures", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Recent Captures")
    private let coordinator: AppCoordinator
    /// Cancels tracking of the status menu, which closes this submenu too.
    private let closeMenus: () -> Void

    init(coordinator: AppCoordinator, closeMenus: @escaping () -> Void) {
        self.coordinator = coordinator
        self.closeMenus = closeMenus
        super.init()
        menu.autoenablesItems = false
        item.submenu = menu
    }

    /// Fills the submenu from the history; called by `StatusMenuController` each time the status
    /// menu opens. Rows show their records as they were at that moment.
    func rebuild() {
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
        for record in records {
            let row = NSMenuItem()
            row.view = RecentCaptureMenuItemView(record: record, now: now, provider: coordinator.thumbnailProvider,
                                                 actions: actions)
            menu.addItem(row)
        }
    }

    private func makeActions() -> RecentCaptureActions {
        RecentCaptureActions(
            copyLinkOrFile: { [weak self] id in self?.afterMenusClose { $0.copyLinkOrFile(recordID: id) } },
            copyLink: { [weak self] id in self?.afterMenusClose { $0.copyLink(recordID: id) } },
            copyImage: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.copyImage(recordID: id) } } },
            delete: { [weak self] id in self?.afterMenusClose { coordinator in Task { await coordinator.deleteCapture(recordID: id) } } })
    }

    /// Closes the menus, then runs `work` when the run loop is back in its default mode, that is,
    /// after menu tracking has ended (`perform(inModes:)` does not run in the menu's
    /// event-tracking mode).
    private func afterMenusClose(_ work: @escaping @MainActor (AppCoordinator) -> Void) {
        closeMenus()
        let coordinator = coordinator
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { work(coordinator) }
        }
    }
}
