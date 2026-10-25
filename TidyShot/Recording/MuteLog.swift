import Foundation

/// A recording's mute presses so far, written to `tmp/Mute/<id>.json` at every toggle (design, Mute
/// log), so a crash or a kill cannot recover the sound the user muted. `<id>` is the stem of
/// `tmp/Recording/<id>.mp4`. An open interval is stored as its start only.
nonisolated struct MuteLog: Codable, Equatable, Sendable {
    var intervals: [MuteInterval]
    /// The recording's lag (design, Lag), so recovery widens the intervals as the end would.
    var lag: TimeInterval
    /// Raised at every toggle: a write never replaces a later one.
    var sequence: Int

    /// What `read` found.
    enum Read: Equatable, Sendable {
        /// No log: the recording was never muted, or its log was removed.
        case none
        /// A log that cannot be read or decoded: the whole file counts as muted.
        case unreadable
        case log(MuteLog)
    }

    /// The container's `tmp/Mute`, beside `tmp/Recording` and never in it, as the launch check
    /// removes every file there that does not play. Reading it creates nothing; the first write does.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "Mute", directoryHint: .isDirectory)
    }

    /// `tmp/Mute/<id>.json`.
    static func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)
    }

    /// Writes `log` to `url` atomically, making its folder when it is missing.
    static func write(_ log: MuteLog, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(log).write(to: url, options: .atomic)
    }

    static func read(_ url: URL) -> Read {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile, CocoaError.fileNoSuchFile {
            return .none
        } catch {
            return .unreadable
        }
        guard let log = try? JSONDecoder().decode(MuteLog.self, from: data) else { return .unreadable }
        return .log(log)
    }
}
