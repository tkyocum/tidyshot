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

    /// The UUID in a `<UUID>.mp4` name, as `Recording.fileURL(for:)` names a recording.
    private static func id(of url: URL) -> UUID? {
        guard url.pathExtension == MediaKind.video.fileExtension else { return nil }
        return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
    }
}
