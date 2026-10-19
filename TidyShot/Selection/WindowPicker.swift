import Foundation
import ScreenCaptureKit

/// Finds the window under a point. Windows come from ScreenCaptureKit ordered front to back.
struct WindowPicker {
    let windows: [SCWindow]

    init(content: SCShareableContent, selfPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        windows = content.windows.filter { window in
            Self.isPickable(isOnScreen: window.isOnScreen,
                            layer: window.windowLayer,
                            frame: window.frame,
                            ownerPID: window.owningApplication?.processID,
                            selfPID: selfPID)
        }
    }

    /// Normal-level (layer 0), on-screen, at least 20 × 20 points, and not owned by this process.
    static func isPickable(isOnScreen: Bool, layer: Int, frame: CGRect, ownerPID: pid_t?, selfPID: pid_t) -> Bool {
        guard isOnScreen, layer == 0 else { return false }
        guard frame.width >= 20, frame.height >= 20 else { return false }
        if let ownerPID, ownerPID == selfPID { return false }
        return true
    }

    /// `cgPoint` is in CoreGraphics global coordinates.
    func window(at cgPoint: CGPoint) -> SCWindow? {
        windows.first { $0.frame.contains(cgPoint) }
    }
}
