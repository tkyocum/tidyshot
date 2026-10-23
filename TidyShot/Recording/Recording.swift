import CoreGraphics
import Foundation

/// A finished recording, handed to `saveRecording`. The pixel size, duration and poster are
/// read from the finished file, never from the stream.
nonisolated struct Recording: Sendable {
    /// Minted at the start. It names `tmp/Recording/<id>.mp4` and becomes the record's id.
    let id: UUID
    let fileURL: URL
    let startedAt: Date
    let pixelWidth: Int
    let pixelHeight: Int
    let duration: TimeInterval
    let poster: CGImage?
    let displayID: CGDirectDisplayID

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
        directory.appending(path: "\(id.uuidString).mp4", directoryHint: .notDirectory)
    }
}
