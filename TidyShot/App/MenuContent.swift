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
        historyMenu
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

    /// The ten newest captures. Uploaded: copies the URL. Failed: retries. Otherwise: reveals the file.
    /// Always enabled; when empty it shows a disabled "No captures yet" row.
    @ViewBuilder
    private var historyMenu: some View {
        let recent = Array(coordinator.history.records.prefix(10))
        Menu("Recent Captures") {
            if recent.isEmpty {
                Button("No captures yet") {}
                    .disabled(true)
            }
            ForEach(recent) { record in
                Button(Self.title(for: record)) {
                    coordinator.historyItemSelected(record.id)
                }
            }
            if !coordinator.history.failedRecords.isEmpty {
                Divider()
                Button("Retry Failed Uploads") {
                    coordinator.retryFailedUploads()
                }
            }
        }
    }

    /// For example `Uploaded  14:03:22  aSIS7x.png`. Plain words, no emoji, so VoiceOver reads
    /// the status and the menu looks the same in every font.
    static func title(for record: CaptureRecord) -> String {
        let time = record.timestamp.formatted(date: .omitted, time: .standard)
        let status: String
        switch record.uploadState {
        case .none: status = "Saved"
        case .uploading: status = "Uploading"
        case .uploaded: status = "Uploaded"
        case .failed: status = "Failed"
        }
        let name = record.uploadedURL?.lastPathComponent ?? record.fileURL?.lastPathComponent ?? "Upload only"
        return "\(status)  \(time)  \(name)"
    }

    private func menuTitle(_ title: String, _ name: KeyboardShortcuts.Name) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return title }
        return "\(title)  \(shortcut)"
    }
}
