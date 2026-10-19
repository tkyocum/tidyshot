import SwiftUI

struct MenuContent: View {
    var body: some View {
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
