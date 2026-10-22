import AVFoundation
import CoreGraphics
import Foundation

/// What `AVURLAsset` reads from a movie file. A missing or unreadable file is not playable and
/// has no tracks.
nonisolated struct VideoFacts: Equatable, Sendable {
    var isPlayable: Bool
    var duration: TimeInterval
    /// The first video track's size in pixels; nil without one.
    var naturalSize: CGSize?
    var videoTracks: Int
    var audioTracks: Int
    var byteCount: Int64
    /// Playable, with a video track, and at least `RecordingLimits.minimumDuration` long: what
    /// the end rule keeps.
    var meetsMinimum: Bool
}

/// The asset check behind the end rule, Clop's result check and the launch check. It reads the
/// file's header and track table, never its media.
nonisolated enum VideoValidation {
    @concurrent
    static func inspect(_ url: URL) async -> VideoFacts {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let unplayable = VideoFacts(isPlayable: false, duration: 0, naturalSize: nil, videoTracks: 0, audioTracks: 0,
                                    byteCount: byteCount, meetsMinimum: false)
        guard byteCount > 0 else { return unplayable }

        let asset = AVURLAsset(url: url)
        do {
            let (isPlayable, time, tracks) = try await asset.load(.isPlayable, .duration, .tracks)
            let video = tracks.filter { $0.mediaType == .video }
            let audioTracks = tracks.count { $0.mediaType == .audio }
            let naturalSize = try await video.first?.load(.naturalSize)
            let duration = time.isNumeric ? max(0, time.seconds) : 0
            let meetsMinimum = isPlayable && !video.isEmpty && duration >= RecordingLimits.minimumDuration
            return VideoFacts(isPlayable: isPlayable, duration: duration, naturalSize: naturalSize,
                              videoTracks: video.count, audioTracks: audioTracks, byteCount: byteCount,
                              meetsMinimum: meetsMinimum)
        } catch {
            return unplayable
        }
    }
}
