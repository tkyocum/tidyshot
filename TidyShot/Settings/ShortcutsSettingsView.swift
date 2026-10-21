import KeyboardShortcuts
import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Capture area:", name: .captureArea)
            KeyboardShortcuts.Recorder("Capture window:", name: .captureWindow)
            KeyboardShortcuts.Recorder("Capture fullscreen:", name: .captureFullscreen)
            KeyboardShortcuts.Recorder("Capture scrolling:", name: .captureScrolling)
            KeyboardShortcuts.Recorder("All-in-One:", name: .allInOne)
            KeyboardShortcuts.Recorder("Capture previous area:", name: .capturePreviousArea)
            KeyboardShortcuts.Recorder("Self-timer:", name: .selfTimer)
            KeyboardShortcuts.Recorder("Capture text:", name: .captureText)
            KeyboardShortcuts.Recorder("Restore closed overlay:", name: .restoreOverlay)
            Text("macOS reserves ⌘⇧3, ⌘⇧4 and ⌘⇧5. To use them here, disable them in System Settings > Keyboard > Keyboard Shortcuts > Screenshots.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
