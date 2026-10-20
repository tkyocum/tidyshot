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
        // Tall enough for the Upload tab (its sections, the example captions under Endpoint and
        // Public URL, and the key template's field, caption, example, collision warning and
        // button) so no tab needs to scroll.
        .frame(width: 600, height: 840)
        .onAppear {
            NSApplication.shared.activate()
        }
    }
}
