import AppKit
import SwiftUI

/// What a permission window says. `quitsWhenGranted` adds a Quit button to the granted state, for
/// Screen Recording, which takes effect at the next launch.
struct PermissionCopy {
    var title: String
    var symbol: String
    var body: String
    var granted: String
    var footer: String?
    var quitsWhenGranted = false

    static let screenRecording = PermissionCopy(
        title: "Screen Recording access needed", symbol: "camera.viewfinder",
        body: "TidyShot captures your screen with Apple's ScreenCaptureKit, which requires Screen Recording permission. Nothing is captured until you press a capture shortcut.",
        granted: "Access granted. Quit and reopen TidyShot to finish.", quitsWhenGranted: true)

    static let autoScroll = PermissionCopy(
        title: "Accessibility access for auto-scroll", symbol: "scroll",
        body: "To scroll other apps for you during a scrolling capture, TidyShot posts scroll-wheel events. macOS lists this under Privacy & Security > Accessibility. TidyShot posts them only while a scrolling capture runs. Without it, you scroll and TidyShot captures as you go.",
        granted: "Access granted. Auto-scroll is ready.",
        footer: "If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.")
}

/// The window that asks for a permission: the explanation, Request Access and Open System
/// Settings until it is granted, then the granted line. TCC posts no notification, so it polls
/// while open.
struct PermissionView: View {
    let permission: TCCPermission
    let copy: PermissionCopy
    @State private var isGranted: Bool

    init(permission: TCCPermission, copy: PermissionCopy) {
        self.permission = permission
        self.copy = copy
        _isGranted = State(initialValue: permission.isGranted())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(copy.title, systemImage: copy.symbol)
                .font(.title2.bold())
            Text(copy.body)
                .fixedSize(horizontal: false, vertical: true)
            if isGranted {
                Label(copy.granted, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if copy.quitsWhenGranted {
                    Button("Quit TidyShot") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                HStack {
                    Button("Request Access") {
                        _ = permission.request()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Open System Settings") {
                        permission.openSystemSettings()
                    }
                }
            }
            if let footer = copy.footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 440)
        .task {
            while !Task.isCancelled {
                isGranted = permission.isGranted()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Shows a permission window: Screen Recording on first run, the auto-scroll privilege from the
/// scrolling panel's link. Safe to call repeatedly; reuses the window.
final class PermissionWindowController {
    private let permission: TCCPermission
    private let copy: PermissionCopy
    private var window: NSWindow?

    init(_ permission: TCCPermission, copy: PermissionCopy) {
        self.permission = permission
        self.copy = copy
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionView(permission: permission, copy: copy))
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
