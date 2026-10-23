import Foundation

/// The panel's elapsed time and a video's duration badge: `0:42`, or `1:02:03` past an hour.
nonisolated enum RecordingClock {
    /// From 5:00 the panel's time turns orange. Nothing stops the recording.
    static let softLimit: TimeInterval = 300

    /// Whole seconds, rounded down. Negative and non-finite values read as `0:00`.
    static func format(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite && seconds > 0 ? Int(min(seconds, Double(Int32.max))) : 0
        let hours = total / 3600
        let minutes = total / 60 % 60
        let rest = total % 60
        return hours > 0
            ? "\(hours):\(twoDigits(minutes)):\(twoDigits(rest))"
            : "\(minutes):\(twoDigits(rest))"
    }

    static func isPastSoftLimit(_ seconds: TimeInterval) -> Bool {
        seconds >= softLimit
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
