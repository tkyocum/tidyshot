import AppKit
import SwiftUI

struct PermissionView: View {
    @State private var isGranted = ScreenCapturePermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Screen Recording access needed", systemImage: "camera.viewfinder")
                .font(.title2.bold())
            Text("TidyShot captures your screen with Apple's ScreenCaptureKit, which requires Screen Recording permission. Nothing is captured until you press a capture shortcut.")
                .fixedSize(horizontal: false, vertical: true)
            if isGranted {
                Label("Access granted. Quit and reopen TidyShot to finish.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Quit TidyShot") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            } else {
                HStack {
                    Button("Request Access") {
                        ScreenCapturePermission.request()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Open System Settings") {
                        ScreenCapturePermission.openSystemSettings()
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 440)
        .task {
            while !Task.isCancelled {
                isGranted = ScreenCapturePermission.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Shows the first-run permission window. Safe to call repeatedly; reuses the window.
final class PermissionWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView())
            let newWindow = NSWindow(contentViewController: hosting)
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
