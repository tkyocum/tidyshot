import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is the unit-test host; the coordinator must not start then.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// The menu bar item, kept for the life of the app.
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        AppCoordinator.shared.start()
        statusMenu = StatusMenuController(coordinator: .shared)
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
