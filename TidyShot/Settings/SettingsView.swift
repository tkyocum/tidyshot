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
        .frame(width: 520)
        .onAppear {
            NSApplication.shared.activate()
        }
    }
}
