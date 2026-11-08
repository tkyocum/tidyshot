import AppKit
import CoreGraphics

/// A privacy permission TidyShot asks macOS for (TCC) through CoreGraphics: Screen Recording,
/// which ScreenCaptureKit needs for every capture not driven by the system picker, and the
/// PostEvent privilege auto-scroll needs (spec 2.8, Auto-scroll permission), which is compatible
/// with the App Sandbox, needs no entitlement, and System Settings lists under Accessibility. The
/// microphone and camera go through `AVCaptureDevice` instead; only their panes are here.
struct TCCPermission {
    /// True when the app has the permission. Does not prompt.
    let isGranted: () -> Bool
    /// Shows the system prompt the first time. Later calls return the current state without
    /// prompting.
    let request: () -> Bool
    /// The System Settings pane that lists it.
    let pane: PrivacyPane

    static let screenRecording = TCCPermission(isGranted: CGPreflightScreenCaptureAccess,
                                               request: CGRequestScreenCaptureAccess, pane: .screenCapture)
    static let postEvent = TCCPermission(isGranted: CGPreflightPostEventAccess,
                                         request: CGRequestPostEventAccess, pane: .accessibility)

    /// Opens System Settings > Privacy & Security at the permission's pane.
    func openSystemSettings() {
        NSWorkspace.shared.open(pane.url)
    }
}

/// A pane of System Settings > Privacy & Security, by the anchor the `x-apple.systempreferences`
/// URL takes.
nonisolated enum PrivacyPane: String, Sendable {
    case screenCapture = "Privacy_ScreenCapture"
    case accessibility = "Privacy_Accessibility"
    case microphone = "Privacy_Microphone"
    case camera = "Privacy_Camera"

    var url: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(rawValue)")!
    }
}
