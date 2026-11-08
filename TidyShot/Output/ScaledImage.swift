import CoreGraphics
import Foundation

/// A captured or decoded image with its backing scale. It is the only image type that crosses
/// between the annotation editor and `AppCoordinator`: `CaptureResult` cannot, because its
/// `CaptureTarget` is MainActor.
nonisolated struct ScaledImage: Sendable {
    let image: CGImage
    /// Pixels per point: the display's backing scale for a capture, or DPI / 72 for a decoded PNG.
    let scale: CGFloat
}

extension CaptureResult {
    /// The image and scale without the MainActor `target`.
    var scaled: ScaledImage { ScaledImage(image: image, scale: scale) }
}

/// The encodes the coordinator makes of a capture or an edit, each off the main actor.
extension ScaledImage {
    /// The image as PNG at its scale.
    func encodedPNG() async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try ImageEncoder.pngData(from: image, scale: scale)
        }.value
    }

    /// The PNG and, with `tiff`, the clipboard's companion TIFF (`Pasteboard.companionTIFF`, nil
    /// above its size limit), in one hop.
    func encodedForClipboard(tiff: Bool = true) async throws -> (png: Data, tiff: Data?) {
        try await Task.detached(priority: .userInitiated) { () throws -> (png: Data, tiff: Data?) in
            (try ImageEncoder.pngData(from: image, scale: scale), tiff ? Pasteboard.companionTIFF(of: image, scale: scale) : nil)
        }.value
    }

    /// The clipboard's companion TIFF alone.
    func companionTIFF() async -> Data? {
        await Task.detached(priority: .userInitiated) {
            Pasteboard.companionTIFF(of: image, scale: scale)
        }.value
    }

    /// The image as TIFF at any size: the clipboard's only copy when the PNG encode failed.
    func encodedTIFF() async -> Data? {
        await Task.detached(priority: .userInitiated) {
            Pasteboard.tiffData(of: image, scale: scale)
        }.value
    }
}
