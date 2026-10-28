import CoreGraphics
import Foundation

/// A finished recording, handed to `saveRecording`. The pixel size, duration and poster are
/// read from the finished file, never from the stream.
nonisolated struct Recording: Sendable {
    /// Minted at the start. It names `tmp/Recording/<id>.mp4` and becomes the record's id.
    let id: UUID
    /// The recorder's MP4, or the GIF made from it.
    let fileURL: URL
    let startedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let poster: CGImage?
    let displayID: CGDirectDisplayID
    /// `.video` for the recorder's MP4, `.gif` for the GIF made from it.
    var mediaKind: MediaKind
    /// The file the launch check recovers when the save leaves `fileURL` in `tmp/Recording`:
    /// `fileURL` itself for an MP4, the MP4 for a GIF (plan Gap 3).
    var recoveryURL: URL
    /// `GIF frame rate` and `GIF size` as they were at the start, for a GIF recording's MP4; nil
    /// for an MP4 recording.
    var gif: GIFSettings?
    /// The muted stretches on the recording's clock, closed at its end; empty when it was never
    /// muted. A non-empty list is applied to the file before `saveRecording` (design, After the end).
    var muteIntervals: [MuteInterval] = []
    /// Click highlights were on at some point after the first frame, so a GIF made from it reserves
    /// the ring colours in its palette (design, Filming).
    var highlightedClicks = false
    /// How far the recording's sound sits behind its clock (design, Lag), added after each interval.
    var lag: TimeInterval = RecordingMute.defaultLag

    init(id: UUID, fileURL: URL, startedAt: Date, pixelWidth: Int, pixelHeight: Int, duration: TimeInterval,
         poster: CGImage?, displayID: CGDirectDisplayID, mediaKind: MediaKind = .video, recoveryURL: URL? = nil,
         gif: GIFSettings? = nil) {
        self.id = id
        self.fileURL = fileURL
        self.startedAt = startedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.poster = poster
        self.displayID = displayID
        self.mediaKind = mediaKind
        self.recoveryURL = recoveryURL ?? fileURL
        self.gif = gif
    }

    /// The container's `tmp/Recording`. Reading it creates nothing.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "Recording", directoryHint: .isDirectory)
    }

    /// Creates `directory` with its parents; an existing folder is fine. Called before anything
    /// writes there or reads its free space.
    static func makeDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// `tmp/Recording/<id>.mp4`.
    static func fileURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).\(MediaKind.video.fileExtension)", directoryHint: .notDirectory)
    }

    /// `tmp/Recording/<id>.gif`, where a GIF is made beside its MP4.
    static func gifURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).\(MediaKind.gif.fileExtension)", directoryHint: .notDirectory)
    }

    /// Removes a recording's file in a detached task. A file already gone is fine; any other
    /// failure is logged.
    static func removeFile(at url: URL) {
        removeFiles(at: [url])
    }

    /// Removes files one after another in one detached task, so they go in order: a discarded
    /// recording's file before its mute log, and a kill between the two never leaves a playable
    /// file without its log (design, Privacy rule). A file already gone is fine. Any other failure
    /// is logged and keeps the files after it, so a file that stays keeps its log for the next
    /// launch.
    @discardableResult
    static func removeFiles(at urls: [URL],
                            remove: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) })
        -> Task<Void, Never> {
        Task.detached {
            for url in urls {
                do {
                    try remove(url)
                } catch CocoaError.fileNoSuchFile {
                    // A start that failed early, or a GIF never begun, wrote nothing.
                } catch {
                    RecordingLog.note("Recording: \(url.lastPathComponent) could not be removed: \(error.localizedDescription)")
                    return
                }
            }
        }
    }
}
