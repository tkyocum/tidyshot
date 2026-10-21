import AppKit
import CoreGraphics

/// The PostEvent privilege auto-scroll needs (spec 2.8, Auto-scroll permission). It is
/// compatible with the App Sandbox and needs no entitlement; System Settings lists it under
/// Privacy & Security > Accessibility. Mirrors `ScreenCapturePermission`.
enum PostEventPermission {
    /// True when this app may post events. Does not prompt.
    static var isGranted: Bool {
        CGPreflightPostEventAccess()
    }

    /// Shows the system prompt the first time. Later calls return the current state.
    @discardableResult
    static func request() -> Bool {
        CGRequestPostEventAccess()
    }

    /// Opens System Settings > Privacy & Security > Accessibility.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
