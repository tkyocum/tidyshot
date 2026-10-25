import Foundation

/// The launch check of `tmp/Recording` (design, Relaunch after a crash). A file left there by a
/// crash, a kill, or a rename that failed is checked, not swept: a killed recording plays, and a
/// crash between the finish and the record would otherwise lose a good recording.
nonisolated enum RecordingRecovery {
    /// A playable file left in `tmp/Recording`.
    struct Found: Equatable, Sendable {
        let url: URL
        /// The UUID its name carries (`<UUID>.mp4`); nil for any other name.
        let id: UUID?
        let facts: VideoFacts
        /// The file's creation date, which becomes the record's timestamp.
        let created: Date
    }

    /// Checks every file in `directory` with `VideoValidation`. Playable files with a video track
    /// are returned, oldest first, and left where they are. Every other file is removed. A missing
    /// or empty folder finds nothing. A crash gives no Stop, so a playable file under the end
    /// rule's 0.5 s is kept too.
    @concurrent
    static func scan(_ directory: URL) async -> [Found] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
        else { return [] }
        var found: [Found] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { continue }
            let facts = await VideoValidation.inspect(url)
            guard facts.isPlayable, facts.videoTracks > 0 else {
                do {
                    try FileManager.default.removeItem(at: url)
                    RecordingLog.note("Recording: \(url.lastPathComponent) could not be played, removed")
                } catch {
                    RecordingLog.note("Recording: \(url.lastPathComponent) could not be played or removed: \(error.localizedDescription)")
                }
                continue
            }
            found.append(Found(url: url, id: id(of: url), facts: facts, created: values?.creationDate ?? .now))
        }
        return found.sorted { $0.created < $1.created }
    }

    /// True when a `.gif` record has the found file's id: a kill after the GIF's save and before
    /// its MP4's removal left the MP4, which is removed rather than recovered. The record is the
    /// whole test; its file is not checked (design, After a crash).
    static func isSavedAsGIF(_ found: Found, records: [CaptureRecord]) -> Bool {
        guard let id = found.id else { return false }
        return records.contains { $0.id == id && $0.mediaKind == .gif }
    }

    /// What the launch check does with a found file before its move (design, Relaunch).
    enum Prepared: Equatable {
        /// Its GIF was saved already (`isSavedAsGIF`): the file is removed, not recovered.
        case savedAsGIF
        /// Recovered, marked with `unmutedIntervals` when its muting failed, with `bodySuffix` added
        /// to `Recovered a recording`'s body, and its mute log removed once the record exists.
        case recover(unmutedIntervals: [MuteInterval], bodySuffix: String?, removesLogAfterRecord: Bool)
    }

    static let mutedSuffix = "The muted parts were silenced."
    static let soundRemovedSuffix = "It was saved without sound."
    static let notMutedSuffix = "Its sound is not muted, so it was not uploaded."

    /// Decides a found file before its move. A file whose GIF was saved is `.savedAsGIF`. A file with
    /// a mute log in `muteDirectory`, found by the UUID in its name (`found.id`, not the record's
    /// id), goes through the ladder: `resolve(file, duration, intervals, lag)`, with the log's
    /// intervals and lag, or the whole file, `[0, duration]`, when the log cannot be read. An open
    /// interval closes at the file's duration in the ladder's segments. A file with no log is
    /// recovered as it is.
    static func prepare(_ found: Found, records: [CaptureRecord], muteDirectory: URL,
                        resolve: (URL, TimeInterval, [MuteInterval], TimeInterval) async -> RecordingMute.Resolution)
        async -> Prepared {
        if isSavedAsGIF(found, records: records) { return .savedAsGIF }
        let unchanged = Prepared.recover(unmutedIntervals: [], bodySuffix: nil, removesLogAfterRecord: false)
        guard let id = found.id else { return unchanged }
        let duration = found.facts.duration
        let intervals: [MuteInterval]
        let lag: TimeInterval
        switch MuteLog.read(muteDirectory.appending(path: "\(id.uuidString).json", directoryHint: .notDirectory)) {
        case .none:
            return unchanged
        case .unreadable:
            (intervals, lag) = ([MuteInterval(start: 0, end: duration)], RecordingMute.defaultLag)
        case .log(let log):
            guard !log.intervals.isEmpty else {
                return .recover(unmutedIntervals: [], bodySuffix: nil, removesLogAfterRecord: true)
            }
            (intervals, lag) = (log.intervals, log.lag)
        }
        let resolution = await resolve(found.url, duration, intervals, lag)
        switch resolution.outcome {
        case .muted:
            return .recover(unmutedIntervals: [], bodySuffix: mutedSuffix, removesLogAfterRecord: true)
        case .soundRemoved:
            return .recover(unmutedIntervals: [], bodySuffix: soundRemovedSuffix, removesLogAfterRecord: true)
        case .notMuted:
            return .recover(unmutedIntervals: resolution.segments, bodySuffix: notMutedSuffix, removesLogAfterRecord: true)
        }
    }

    /// The launch check's start: `muteDirectory` listed (`listMuteFolder`), then `recordingDirectory`
    /// scanned, in that order, so a log written since launch, while the scan or the loop after it runs,
    /// is never in the list `sweepMuteFolder` goes through (Decided 2026-10-24, 6). `scanning` is
    /// `scan`, injected by tests.
    static func begin(recordingDirectory: URL, muteDirectory: URL,
                      scanning: (URL) async -> [Found] = { await RecordingRecovery.scan($0) })
        async -> (muteFiles: [URL], found: [Found]) {
        let muteFiles = listMuteFolder(muteDirectory)
        return (muteFiles, await scanning(recordingDirectory))
    }

    /// The files in `muteDirectory` as the launch check begins, before its loop: the only ones
    /// `sweepMuteFolder` may remove (Decided 2026-10-24, 6). A missing folder lists nothing.
    static func listMuteFolder(_ muteDirectory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: muteDirectory, includingPropertiesForKeys: nil)) ?? []
    }

    /// After the launch check's loop: each of the files `listMuteFolder` listed before it whose
    /// name's stem has no `<stem>.mp4` in `recordingDirectory` goes, the logs of recovered files and
    /// partial rewrites a crash left. A file whose move failed keeps its log for the next launch. A
    /// file written after the list is never touched, so a recording made since launch keeps its
    /// log, also before its `<stem>.mp4` exists (a Mute press before the first frame).
    static func sweepMuteFolder(_ listed: [URL], recordingDirectory: URL) {
        let manager = FileManager.default
        for url in listed {
            let stem = url.deletingPathExtension().lastPathComponent
            let recording = recordingDirectory.appending(path: "\(stem).\(MediaKind.video.fileExtension)",
                                                         directoryHint: .notDirectory)
            guard !manager.fileExists(atPath: recording.path(percentEncoded: false)) else { continue }
            do {
                try manager.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                // A recovered file's log, removed meanwhile.
            } catch {
                RecordingLog.note("Recording: \(url.lastPathComponent) could not be removed from tmp/Mute: \(error.localizedDescription)")
            }
        }
    }

    /// The UUID in a `<UUID>.mp4` name, as `Recording.fileURL(for:)` names a recording.
    private static func id(of url: URL) -> UUID? {
        guard url.pathExtension == MediaKind.video.fileExtension else { return nil }
        return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
    }
}
