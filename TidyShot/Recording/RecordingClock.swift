import Foundation

/// The panel's elapsed time and a video's duration badge: `0:42`, or `1:02:03` past an hour.
nonisolated enum RecordingClock {
    /// From 5:00 the panel's time turns orange for an MP4, and from 0:30 for a GIF. Nothing stops
    /// the recording.
    static let softLimit: TimeInterval = 300
    static let gifSoftLimit: TimeInterval = 30

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

    static func isPastSoftLimit(_ seconds: TimeInterval, format: RecordingFormat) -> Bool {
        seconds >= (format == .gif ? gifSoftLimit : softLimit)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
