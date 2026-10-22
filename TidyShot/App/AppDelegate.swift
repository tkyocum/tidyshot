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
        #if DEBUG
        // The R1 sandbox spike: `open TidyShot.app --args -RecordingSpike YES`.
        if UserDefaults.standard.bool(forKey: "RecordingSpike") {
            Task { await RecordingSpike.run() }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting does not call `windowShouldClose`, so an editor with unsaved changes is reviewed
    /// here: the quit waits (`.terminateLater`) while `reviewEditorsBeforeQuit()` shows the close
    /// sheet in each one, and goes ahead only when none was cancelled.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isRunningTests, AppCoordinator.shared.hasUnsavedEditors else { return .terminateNow }
        Task {
            let proceed = await AppCoordinator.shared.reviewEditorsBeforeQuit()
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }
}
