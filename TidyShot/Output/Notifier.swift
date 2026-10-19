import AppKit
import UserNotifications

/// Posts "saved" and "failed" notifications. Clicking a saved notification reveals the file in Finder.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Read from the nonisolated delegate callbacks, so it must not be MainActor-isolated.
    nonisolated private static let pathKey = "path"
    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Notification authorization failed: \(error.localizedDescription)") }
        }
    }

    func notifySaved(fileURL: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Screenshot saved"
        content.body = fileURL.lastPathComponent
        content.userInfo = [Self.pathKey: fileURL.path]
        post(content)
    }

    func notifyError(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Capture failed"
        content.body = message
        post(content)
    }

    private func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { NSLog("Notification failed: \(error.localizedDescription)") }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let path = response.notification.request.content.userInfo[Self.pathKey] as? String else { return }
        let url = URL(fileURLWithPath: path)
        await MainActor.run {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
