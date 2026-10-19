import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture area:", name: .captureArea)
            KeyboardShortcuts.Recorder("Capture window:", name: .captureWindow)
            KeyboardShortcuts.Recorder("Capture fullscreen:", name: .captureFullscreen)
            Text("macOS reserves ⌘⇧3, ⌘⇧4 and ⌘⇧5. To use them here, disable them in System Settings > Keyboard > Keyboard Shortcuts > Screenshots.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
