import AVFoundation
import CoreGraphics
import Foundation

/// A finished recording's first frame, for its card and its thumbnail. It decodes one frame,
/// never the whole video.
nonisolated enum PosterFrame {
    /// The longer side's limit in pixels. A smaller video keeps its size.
    static let maxSide = 800

    /// Nil when the file cannot be read.
    @concurrent
    static func image(of url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSide, height: maxSide)
        do {
            return try await generator.image(at: .zero).image
        } catch {
            RecordingLog.note("Recording: no poster frame for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }
}
