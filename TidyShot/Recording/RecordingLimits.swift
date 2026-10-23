import Foundation

/// The recording thresholds: free space at the start and during a recording, the Cancel alert,
/// the shortest recording kept, the stop wait and the single-PUT upload limit.
nonisolated enum RecordingLimits {
    /// Under this much free space for `tmp/Recording`, nothing records (decimal GB, as Finder shows).
    static let startFreeBytes: Int64 = 2_000_000_000
    /// Under this much, checked every `diskCheckInterval`, the recording ends.
    static let runningFreeBytes: Int64 = 1_000_000_000
    static let diskCheckInterval: Duration = .seconds(5)
    /// From this much recording, Cancel asks before it discards.
    static let cancelConfirmationSeconds: TimeInterval = 5
    /// A playable file shorter than this is removed as too short.
    static let minimumDuration: TimeInterval = 0.5
    /// How long a stop waits for the output's finish callback, in time awake.
    static let stopTimeout: Duration = .seconds(15)
    /// 5 GiB, the largest single PUT.
    static let singleUploadBytes: Int64 = 5_368_709_120
    static let diskFullText = "Your disk is almost full."

    /// Under 2 GB refuses. An unreadable value (nil) counts as enough.
    static func refusesStart(freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return false }
        return freeBytes < startFreeBytes
    }

    /// Under 1 GB ends the recording. An unreadable value (nil) counts as enough.
    static func stopsRecording(freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return false }
        return freeBytes < runningFreeBytes
    }

    /// Room for a step that writes `byteCount` bytes (a GIF, a muted copy, a trimmed one): at least
    /// that plus 1 GB free. An unreadable value (nil) counts as enough.
    static func hasRoom(for byteCount: Int64, freeBytes: Int64?) -> Bool {
        guard let freeBytes else { return true }
        return freeBytes >= byteCount + runningFreeBytes
    }

    static func asksBeforeDiscarding(elapsed: TimeInterval) -> Bool {
        elapsed >= cancelConfirmationSeconds
    }

    static func fitsSingleUpload(byteCount: Int64) -> Bool {
        byteCount <= singleUploadBytes
    }

    /// `volumeAvailableCapacityForImportantUsageKey` of `url`, or of its nearest existing ancestor
    /// when `url` does not exist yet, so a fresh container is checked too. Nil only when the read
    /// fails.
    static func freeBytes(at url: URL) -> Int64? {
        var folder = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            let parent = folder.deletingLastPathComponent()
            guard parent.path(percentEncoded: false) != folder.path(percentEncoded: false) else { break }
            folder = parent
        }
        return try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }
}
