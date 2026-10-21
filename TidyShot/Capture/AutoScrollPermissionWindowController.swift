import AppKit
import SwiftUI

struct AutoScrollPermissionView: View {
    @State private var isGranted = PostEventPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Accessibility access for auto-scroll", systemImage: "scroll")
                .font(.title2.bold())
            Text("To scroll other apps for you during a scrolling capture, TidyShot posts scroll-wheel events. macOS lists this under Privacy & Security > Accessibility. TidyShot posts them only while a scrolling capture runs. Without it, you scroll and TidyShot captures as you go.")
                .fixedSize(horizontal: false, vertical: true)
            if isGranted {
                Label("Access granted. Auto-scroll is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Button("Request Access") {
                        PostEventPermission.request()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Open System Settings") {
                        PostEventPermission.openSystemSettings()
                    }
                }
            }
            Text("If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
        .task {
            while !Task.isCancelled {
                isGranted = PostEventPermission.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Shows the auto-scroll permission window from the scrolling panel's link. Reuses the window.
final class AutoScrollPermissionWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: AutoScrollPermissionView()))
            newWindow.title = "TidyShot"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
