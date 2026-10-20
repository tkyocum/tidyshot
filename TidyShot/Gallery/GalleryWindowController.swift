import AppKit
import SwiftUI

/// The Recent Captures window. One instance, reused; `show()` brings it to the front.
final class GalleryWindowController {
    private let model: GalleryModel
    private let actions: GalleryActions
    private var window: NSWindow?

    init(model: GalleryModel, actions: GalleryActions) {
        self.model = model
        self.actions = actions
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: GalleryView(model: model, actions: actions))
            let newWindow = GalleryWindow(contentViewController: hosting)
            newWindow.title = "Recent Captures"
            newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 900, height: 600))
            newWindow.center()
            newWindow.setFrameAutosaveName("RecentCaptures")
            window = newWindow
        }
        // A menu bar agent is not the active app when its menu is used; activate so the window
        // comes to the front and takes keyboard focus.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.performClose(nil)
    }
}

/// Closes on Escape and ⌘W. A menu bar agent has no main menu, so the usual Close item that
/// would provide ⌘W does not exist.
final class GalleryWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Caps Lock is ignored: it is in the device-independent flags and makes the character "W".
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
