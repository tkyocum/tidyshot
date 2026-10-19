import AppKit
import CoreGraphics

/// Screen Recording (TCC) permission checks. ScreenCaptureKit requires this permission for every
/// capture that is not driven by the system content picker.
enum ScreenCapturePermission {
    /// True when this app has Screen Recording permission. Does not prompt.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time. Later calls return the current state without prompting.
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings > Privacy & Security > Screen & System Audio Recording.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
