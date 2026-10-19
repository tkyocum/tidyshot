import SwiftUI

@main
struct TidyShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra("TidyShot", systemImage: coordinator.isUploading ? "arrow.up.circle" : "camera.viewfinder") {
            MenuContent()
        }
        Settings {
            SettingsView()
        }
    }
}
