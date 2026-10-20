import AppKit
import SwiftUI

/// Opens the SwiftUI `Settings` scene from AppKit code.
///
/// The `showSettingsWindow:` action that used to do this no longer opens the window (macOS 27:
/// `NSApp.sendAction` returns true and nothing appears). SwiftUI's `openSettings` environment
/// action does, but only a SwiftUI view can read it, so `install(in:)` adds a zero-size
/// `NSHostingView` to a view that is always on screen (the status item's button); its view reads
/// the action when it appears and hands it over.
final class SettingsOpener {
    private var action: OpenSettingsAction?

    func install(in view: NSView?) {
        let reader = NSHostingView(rootView: SettingsActionReader { [weak self] action in
            self?.action = action
        })
        reader.frame = .zero
        view?.addSubview(reader)
    }

    /// Activates the app first: a menu bar agent is not active when its menu is used, and the
    /// window would open behind the frontmost app. If the action has not been read (the reader
    /// never appeared), falls back to `showSettingsWindow:` and logs it, so Settings… is never
    /// silently dead: a macOS where that action works again opens the window, and one where it
    /// does not leaves a line in the log.
    func open() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let action {
            action()
            return
        }
        let sent = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSLog("Settings: the openSettings action has not been read; sent showSettingsWindow: instead (handled: \(sent))")
    }
}

/// Reads `openSettings` from the environment once it is on screen. No work in `body`.
private struct SettingsActionReader: View {
    @Environment(\.openSettings) private var openSettings
    let receive: (OpenSettingsAction) -> Void

    var body: some View {
        Color.clear
            .onAppear { receive(openSettings) }
    }
}
