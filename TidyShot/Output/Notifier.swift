import AppKit
import UserNotifications

/// Posts "saved", "uploaded" and "failed" notifications. Clicking a saved notification, or an
/// error given a file, reveals the file in Finder; clicking an uploaded notification, or a plain
/// one given a URL, opens the URL; clicking the `Uploaded` of a link that was not copied copies it.
/// From a recording's count-in until it stops every notification waits, and posts then
/// (`holdNotices()`).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Read from the nonisolated delegate callbacks, so they must not be MainActor-isolated.
    nonisolated private static let pathKey = "path"
    nonisolated private static let urlKey = "url"
    nonisolated private static let copyURLKey = "copyURL"
    private let center = UNUserNotificationCenter.current()
    private var hold = NoticeHold<UNMutableNotificationContent>()
    /// Notices `releaseHeldNotices()` handed to the notification centre that it has not yet taken.
    private var releasedInFlight = 0

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

    /// While a recording counts in or runs (R2 design, Decided 2026-10-24, 8): every notification
    /// asked for from here waits until `releaseHeldNotices()`. The coordinator holds from the
    /// hand-off's start under the capture lock. A hold already on keeps what waits.
    func holdNotices() {
        hold.hold()
    }

    /// Ends the hold: what waited posts now, in the order it was asked for. Returns how many posted.
    /// Nothing waits for them to reach the notification centre, except a quit
    /// (`waitForReleasedNotices(upTo:)`).
    @discardableResult
    func releaseHeldNotices() -> Int {
        let released = hold.release()
        for content in released {
            releasedInFlight += 1
            add(content) {
                Task { @MainActor in self.releasedInFlight -= 1 }
            }
        }
        return released.count
    }

    /// Returns once the notification centre has taken every notice `releaseHeldNotices()` posted, or
    /// once `limit` has passed, so a stuck notification daemon cannot hold a quit; at once when none
    /// is on its way. A quit waits here, so the app does not end before the centre has them.
    func waitForReleasedNotices(upTo limit: Duration) async {
        let deadline = ContinuousClock.now + limit
        while releasedInFlight > 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: Self.releaseCheckInterval)
        }
    }

    /// How often `waitForReleasedNotices(upTo:)` checks.
    private static let releaseCheckInterval = Duration.milliseconds(10)

    /// Every notification comes through here: at once, or held while a recording counts in or runs.
    private func post(_ content: UNMutableNotificationContent) {
        if let content = hold.post(content) {
            add(content)
        }
    }

    /// Hands `content` to the notification centre now, so notices reach it in the order asked for.
    /// `added` runs once the centre has taken it, or failed to.
    private func add(_ content: UNMutableNotificationContent, added: (@Sendable () -> Void)? = nil) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { NSLog("Notification failed: \(error.localizedDescription)") }
            added?()
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
