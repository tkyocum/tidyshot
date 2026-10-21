import CoreGraphics

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
