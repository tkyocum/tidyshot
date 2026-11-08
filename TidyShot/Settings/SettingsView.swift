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
        // The Phase 3 height. The Upload tab's grouped Form is taller than this (about 970 points
        // with the key template's collision warning, about 1010 with a status line under the Save
        // buttons) and scrolls; a window tall enough to show all of it would not fit a laptop
        // screen.
        .frame(width: 600, height: 800)
        .onAppear {
            NSApplication.shared.activate()
        }
    }
}

/// A note under a control, as every tab shows its examples, token lists and warnings: the caption
/// font in the secondary colour.
struct Caption: View {
    private let text: Text

    init(_ text: String) {
        self.text = Text(text)
    }

    init(verbatim: String) {
        self.text = Text(verbatim: verbatim)
    }

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
