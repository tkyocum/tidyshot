import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Finds the window under a point. `SCShareableContent.windows` has no documented order, so the
/// candidates are sorted by the window server's front-to-back order from `CGWindowListCopyWindowInfo`.
struct WindowPicker {
    /// Pickable windows, frontmost first.
    let windows: [SCWindow]

    init(content: SCShareableContent,
         selfPID: pid_t = ProcessInfo.processInfo.processIdentifier,
         frontToBack: [CGWindowID] = WindowPicker.frontToBackWindowIDs()) {
        let pickable = content.windows.filter { window in
            Self.isPickable(isOnScreen: window.isOnScreen,
                            layer: window.windowLayer,
                            frame: window.frame,
                            ownerPID: window.owningApplication?.processID,
                            selfPID: selfPID)
        }
        windows = Self.ordered(pickable, frontToBack: frontToBack) { $0.windowID }
    }

    /// Normal-level (layer 0), on-screen, at least 20 × 20 points, and not owned by this process.
    static func isPickable(isOnScreen: Bool, layer: Int, frame: CGRect, ownerPID: pid_t?, selfPID: pid_t) -> Bool {
        guard isOnScreen, layer == 0 else { return false }
        guard frame.width >= 20, frame.height >= 20 else { return false }
        if let ownerPID, ownerPID == selfPID { return false }
        return true
    }

    /// Sorts `items` by the position of their window id in `frontToBack`. Items whose id is not
    /// listed keep their relative order and go last.
    static func ordered<T>(_ items: [T], frontToBack: [CGWindowID], id: (T) -> CGWindowID) -> [T] {
        var rank: [CGWindowID: Int] = [:]
        for (index, windowID) in frontToBack.enumerated() where rank[windowID] == nil {
            rank[windowID] = index
        }
        let unknown = frontToBack.count
        return items.enumerated()
            .sorted { lhs, rhs in
                let l = rank[id(lhs.element)] ?? unknown
                let r = rank[id(rhs.element)] ?? unknown
                return l != r ? l < r : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// On-screen window ids from the window server, frontmost first.
    static func frontToBackWindowIDs() -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        return info.compactMap { ($0[kCGWindowNumber] as? NSNumber)?.uint32Value }
    }

    /// `cgPoint` is in CoreGraphics global coordinates. Returns the frontmost pickable window under it.
    func window(at cgPoint: CGPoint) -> SCWindow? {
        windows.first { $0.frame.contains(cgPoint) }
    }
}
