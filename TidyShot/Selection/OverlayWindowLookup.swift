import AppKit
import ScreenCaptureKit

/// TidyShot's own windows as ScreenCaptureKit sees them, matched by window number, for a
/// filter's `excludingWindows`. Used for the selection overlay and as the scrolling stream's
/// fallback when TidyShot is missing from the shareable applications.
enum OverlayWindowLookup {
    /// Retries briefly because ScreenCaptureKit can lag the window server, and returns whatever
    /// was found after the last attempt.
    static func windows(numbers wanted: Set<CGWindowID>, engine: CaptureEngine) async -> [SCWindow] {
        var found: [SCWindow] = []
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let fresh = try? await engine.shareableContent() else { continue }
            found = fresh.windows.filter { wanted.contains($0.windowID) }
            if found.count >= wanted.count { break }
        }
        if found.count < wanted.count {
            NSLog("Overlay exclusion incomplete: found \(found.count) of \(wanted.count) overlay windows")
        }
        return found
    }
}
