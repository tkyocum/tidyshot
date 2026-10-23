import AppKit
import UserNotifications

/// Posts "saved", "uploaded" and "failed" notifications. Clicking a saved notification, or an
/// error given a file, reveals the file in Finder; clicking an uploaded notification, or a plain
/// one given a URL, opens the URL; clicking the `Uploaded` of a link that was not copied copies it.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Read from the nonisolated delegate callbacks, so they must not be MainActor-isolated.
    nonisolated private static let pathKey = "path"
    nonisolated private static let urlKey = "url"
    nonisolated private static let copyURLKey = "copyURL"
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

    /// `Uploaded, URL copied`, whose click opens the URL. With `copied` false (a recording whose
    /// URL did not replace the clipboard) it is `Uploaded` with `Click to copy the link.`, and a
    /// click copies the URL without opening it.
    func notifyUploaded(url: URL, copied: Bool = true) {
        let content = UNMutableNotificationContent()
        content.body = url.absoluteString
        if copied {
            content.title = "Uploaded, URL copied"
            content.userInfo = [Self.urlKey: url.absoluteString]
        } else {
            content.title = "Uploaded"
            content.subtitle = "Click to copy the link."
            content.userInfo = [Self.copyURLKey: url.absoluteString]
        }
        post(content)
    }

    /// With `revealing`, a click reveals that file, as `Recording stopped` does.
    func notifyError(_ message: String, title: String = "Capture failed", subtitle: String? = nil,
                     revealing fileURL: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if let subtitle {
            content.subtitle = subtitle
        }
        if let fileURL {
            content.userInfo = [Self.pathKey: fileURL.path]
        }
        post(content)
    }

    /// A plain notification, such as "Copying image…" and "Image copied". Clicking it opens
    /// `openURL` when one is given, as an uploaded notification does, and otherwise does nothing.
    func notify(title: String, body: String, subtitle: String? = nil, openURL: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let subtitle {
            content.subtitle = subtitle
        }
        if let openURL {
            content.userInfo = [Self.urlKey: openURL.absoluteString]
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
        } else if let string = userInfo[Self.copyURLKey] as? String, let url = URL(string: string) {
            await MainActor.run {
                _ = Pasteboard.copy(url: url)
            }
        }
    }
}
