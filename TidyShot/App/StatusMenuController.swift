import AppKit
import KeyboardShortcuts
import Observation

/// The menu bar item: an AppKit `NSStatusItem` with an `NSMenu`, because Recent Captures must be
/// a submenu that opens on hover and holds rows with custom views, which the SwiftUI menu bar scene
/// cannot do.
/// The menu is rebuilt each time it opens, so the shortcut titles, the permission item and Retry
/// Failed Uploads are current. Using the menu never activates the app; only the alerts and
/// windows it leads to do (Settings, the permission window, the delete confirmation).
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let coordinator: AppCoordinator
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let settingsOpener = SettingsOpener()
    private let recentCaptures: RecentCapturesMenu

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu(title: "TidyShot")
        self.menu = menu
        // Row buttons close the status menu, which closes the submenu with it.
        recentCaptures = RecentCapturesMenu(coordinator: coordinator, closeMenus: { [weak menu] in menu?.cancelTracking() })
        super.init()
        // Keeps the item where the user Command-drags it in the menu bar, across launches.
        statusItem.autosaveName = "TidyShot"
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        settingsOpener.install(in: statusItem.button)
        updateIcon()
    }

    /// `camera.viewfinder`, or `arrow.up.circle` while an upload runs. Observation calls `onChange`
    /// once per registration (before the value changes), so the update is scheduled and registers
    /// again; the main queue also runs while a menu is tracking, so the icon changes with the menu open.
    private func updateIcon() {
        let uploading = withObservationTracking {
            coordinator.isUploading
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
        let image = NSImage(systemSymbolName: uploading ? "arrow.up.circle" : "camera.viewfinder",
                            accessibilityDescription: uploading ? "TidyShot, uploading" : "TidyShot")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        if !coordinator.permissionGranted {
            menu.addItem(item("Screen Recording permission needed…", #selector(showPermission)))
            menu.addItem(.separator())
        }
        menu.addItem(captureItem("Capture Area", .captureArea, #selector(captureArea)))
        menu.addItem(captureItem("Capture Window", .captureWindow, #selector(captureWindow)))
        menu.addItem(captureItem("Capture Fullscreen", .captureFullscreen, #selector(captureFullscreen)))
        menu.addItem(.separator())
        recentCaptures.rebuild()
        menu.addItem(recentCaptures.item)
        if !coordinator.history.failedRecords.isEmpty {
            menu.addItem(item("Retry Failed Uploads", #selector(retryFailedUploads)))
        }
        let reveal = item("Reveal Last Capture", #selector(revealLastCapture))
        reveal.isEnabled = coordinator.lastCaptureURL != nil
        menu.addItem(reveal)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit TidyShot", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        return menuItem
    }

    /// "Capture Area  ⌃⇧4": the shortcut is part of the title, as the SwiftUI menu showed it, and
    /// is not a key equivalent, which would fire the capture a second time through the global
    /// hotkey that the menu buffers while it is open.
    private func captureItem(_ title: String, _ name: KeyboardShortcuts.Name, _ action: Selector) -> NSMenuItem {
        let shortcut = KeyboardShortcuts.getShortcut(for: name)
        let menuItem = item(shortcut.map { "\(title)  \($0)" } ?? title, action)
        menuItem.isEnabled = !coordinator.isCapturing
        return menuItem
    }

    // MARK: Actions (AppKit calls these after the menu has closed)

    @objc private func showPermission() { coordinator.showPermissionWindow() }
    @objc private func captureArea() { Task { await coordinator.captureArea() } }
    @objc private func captureWindow() { Task { await coordinator.captureWindow() } }
    @objc private func captureFullscreen() { Task { await coordinator.captureFullscreen() } }
    @objc private func retryFailedUploads() { coordinator.retryFailedUploads() }
    @objc private func revealLastCapture() { coordinator.revealLastCapture() }
    @objc private func openSettings() { settingsOpener.open() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
