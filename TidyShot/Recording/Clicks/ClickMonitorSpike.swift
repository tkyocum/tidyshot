#if DEBUG
import AppKit
import os

/// R3's P4: the click monitors in the sandboxed app. For 60 s it runs a global and a local monitor
/// on the mouse buttons and logs each event with its delay, whether it had a window and the
/// frontmost app, never a position. It shows a titled panel to click on, because a global monitor
/// does not see clicks on the app's own windows and the local one does. It also logs, without
/// asking, whether Accessibility and Input Monitoring are granted. Launch the Debug build with
/// `-ClickMonitorSpike YES`. Debug builds only.
///
/// Read the lines with
/// `/usr/bin/log show --last 2m --style compact --predicate 'process == "TidyShot"' | grep "Click spike"`.
enum ClickMonitorSpike {
    static let mask: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
    ]

    private static let log = Logger(subsystem: "io.tky.tidyshot", category: "ClickSpike")
    private static let duration: Duration = .seconds(60)

    static func run() async {
        let trusted = AXIsProcessTrusted()
        let listening = CGPreflightListenEventAccess()
        note("Click spike: AXIsProcessTrusted \(trusted), CGPreflightListenEventAccess \(listening)")

        let panel = makePanel()
        panel.orderFrontRegardless()
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            note(line(for: event, source: "global"))
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            note(line(for: event, source: "local"))
            return event
        }

        try? await Task.sleep(for: duration)

        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        panel.close()
        note("Click spike: done")
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Click spike"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        if let screen = NSScreen.main {
            let frame = screen.frame
            panel.setFrameOrigin(NSPoint(x: (frame.midX - panel.frame.width / 2).rounded(),
                                         y: (frame.midY - panel.frame.height / 2).rounded()))
        }
        return panel
    }

    private static func line(for event: NSEvent, source: String) -> String {
        let delay = Int(((ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000).rounded())
        let hasWindow = event.window != nil ? "yes" : "no"
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        return "Click spike: \(source) \(name(of: event.type)), delay \(delay) ms, window \(hasWindow), frontmost \(frontmost)"
    }

    private static func name(of type: NSEvent.EventType) -> String {
        switch type {
        case .leftMouseDown: "leftMouseDown"
        case .leftMouseUp: "leftMouseUp"
        case .leftMouseDragged: "leftMouseDragged"
        case .rightMouseDown: "rightMouseDown"
        case .rightMouseUp: "rightMouseUp"
        case .rightMouseDragged: "rightMouseDragged"
        default: "other(\(type.rawValue))"
        }
    }

    private static func note(_ message: String) {
        log.notice("\(message, privacy: .public)")
    }
}
#endif
