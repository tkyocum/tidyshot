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
}
