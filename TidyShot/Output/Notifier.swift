import AppKit
import UserNotifications

/// Posts "saved", "uploaded" and "failed" notifications. Clicking a saved notification reveals
/// the file in Finder; clicking an uploaded notification opens the URL.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Read from the nonisolated delegate callbacks, so they must not be MainActor-isolated.
    nonisolated private static let pathKey = "path"
    nonisolated private static let urlKey = "url"
    private let center = UNUserNotificationCenter.current()

    func setUp() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Notification authorization failed: \(error.localizedDescription)") }
        }
    }

    /// Clicking it reveals the file. The editor's Save As… posts it with the title `Saved`.
    func notifySaved(fileURL: URL, title: String = "Screenshot saved") {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = fileURL.lastPathComponent
        content.userInfo = [Self.pathKey: fileURL.path]
        post(content)
    }

    func notifyUploaded(url: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Uploaded, URL copied"
        content.body = url.absoluteString
        content.userInfo = [Self.urlKey: url.absoluteString]
        post(content)
    }

    func notifyError(_ message: String, title: String = "Capture failed", subtitle: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if let subtitle {
            content.subtitle = subtitle
        }
        post(content)
    }

    /// A plain notification with no click action, such as "Copying image…" and "Image copied".
    func notify(title: String, body: String, subtitle: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle {
            content.subtitle = subtitle
        }
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
        let userInfo = response.notification.request.content.userInfo
        if let path = userInfo[Self.pathKey] as? String {
            let url = URL(fileURLWithPath: path)
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else if let string = userInfo[Self.urlKey] as? String, let url = URL(string: string) {
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }
}
