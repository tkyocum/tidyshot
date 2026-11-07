import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is the unit-test host; the coordinator must not start then.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The menu bar item, kept for the life of the app.
    private var statusMenu: StatusMenuController?

    /// Installed before launch finishes, so a URL that launched the app reaches it (spec 2.9). It
    /// replaces AppKit's default handler, so SwiftUI's scene machinery never sees the URL.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    /// A `tidyshot://` URL from LaunchServices: `open`, Raycast, Keyboard Maestro, Shortcuts, a browser.
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else {
            NSLog("%@", "A URL event without a readable URL was ignored")
            return
        }
        AppCoordinator.shared.handleURL(url, sender: Self.senderName(of: event))
    }

    /// The sending app's name: the event's `keySenderPIDAttr`, then the running application with
    /// that pid. Nil when the event carries no pid, or the process has gone or has no name.
    private static func senderName(of event: NSAppleEventDescriptor) -> String? {
        guard let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0 else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppCoordinator.shared.start()
        statusMenu = StatusMenuController(coordinator: .shared)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// True from a held quit's `.terminateLater` until its reply.
    private var isHoldingQuit = false

    /// A quit, a log out and a restart all come here. Quitting does not call `windowShouldClose`,
    /// and a recording must not be cut off, so while `quitNeedsHold` the quit waits
    /// (`.terminateLater`). First `reviewEditorsBeforeQuit()` shows the close sheet in each editor
    /// with unsaved changes; a cancel stops the quit, and a recording runs on. Then
    /// `finishRecordingForQuit()` cancels a count-in, stops a recording and waits for its save.
    /// The reply is sent once; a second quit while one is held is cancelled, and the held one answers.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isRunningTests else { return .terminateNow }
        guard !isHoldingQuit else { return .terminateCancel }
        let coordinator = AppCoordinator.shared
        guard coordinator.quitNeedsHold else { return .terminateNow }
        isHoldingQuit = true
        Task {
            let proceed = await coordinator.reviewEditorsBeforeQuit()
            if proceed {
                await coordinator.finishRecordingForQuit()
            }
            isHoldingQuit = false
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }
}
