import KeyboardShortcuts
import SwiftUI

struct MenuContent: View {
    private let coordinator = AppCoordinator.shared

    var body: some View {
        if !coordinator.permissionGranted {
            Button("Screen Recording permission needed…") {
                coordinator.showPermissionWindow()
            }
            Divider()
        }
        Button(menuTitle("Capture Area", .captureArea)) {
            Task { await coordinator.captureArea() }
        }
        .disabled(coordinator.isCapturing)
        Button(menuTitle("Capture Window", .captureWindow)) {
            Task { await coordinator.captureWindow() }
        }
        .disabled(coordinator.isCapturing)
        Button(menuTitle("Capture Fullscreen", .captureFullscreen)) {
            Task { await coordinator.captureFullscreen() }
        }
        .disabled(coordinator.isCapturing)
        Divider()
        Button("Recent Captures…") {
            coordinator.showGallery()
        }
        if !coordinator.history.failedRecords.isEmpty {
            Button("Retry Failed Uploads") {
                coordinator.retryFailedUploads()
            }
        }
        Button("Reveal Last Capture") {
            coordinator.revealLastCapture()
        }
        .disabled(coordinator.lastCaptureURL == nil)
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func menuTitle(_ title: String, _ name: KeyboardShortcuts.Name) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return title }
        return "\(title)  \(shortcut)"
    }
}
