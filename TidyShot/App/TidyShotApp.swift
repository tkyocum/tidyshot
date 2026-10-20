import SwiftUI

/// The SwiftUI side of the app is the Settings scene only. The menu bar item is AppKit
/// (`StatusMenuController`, created by `AppDelegate`).
@main
struct TidyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
