import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            CaptureSettingsView()
                .tabItem { Label("Capture", systemImage: "camera") }
            UploadSettingsView()
                .tabItem { Label("Upload", systemImage: "icloud.and.arrow.up") }
            OverlaySettingsView()
                .tabItem { Label("Overlay", systemImage: "macwindow.on.rectangle") }
        }
        // Tall enough for the Upload tab's five sections so no tab needs to scroll.
        .frame(width: 600, height: 720)
        .onAppear {
            NSApplication.shared.activate()
        }
    }
}
