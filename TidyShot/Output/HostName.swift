import Darwin
import Foundation

/// The Mac's local host name for the `{hostname}` token: what `gethostname(2)` reports (the
/// Sharing pane's local hostname, for example `Tims-MacBook-Pro.local`), lowercased and without
/// `.local`. A plain syscall, so it never blocks on DNS the way `ProcessInfo.hostName` can, and
/// it works inside the App Sandbox. `Host` (NSHost) is marked for deprecation and is not used.
nonisolated enum HostName {
    static func local() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let status = buffer.withUnsafeMutableBufferPointer { gethostname($0.baseAddress, $0.count - 1) }
        guard status == 0 else { return TemplateExpander.normalizeHostname("") }
        let raw = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return TemplateExpander.normalizeHostname(raw)
    }
}
