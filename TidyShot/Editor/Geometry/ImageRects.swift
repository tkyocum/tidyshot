import CoreGraphics

/// Rects in image pixels. The model uses a top-left origin (CGImage row 0 at the top, as for
/// `CGImage.cropping(to:)` and `Luminance.mean(of:in:)`); Core Graphics bitmap contexts and
/// Core Image use a bottom-left one, where y = 0 is the image's last row.
nonisolated enum ImageRects {
    /// `rect` rounded outward to whole pixels and clipped to an image of `size`. `.zero` when
    /// nothing is left: an empty or null rect, or one wholly outside or only touching an edge.
    static func integral(_ rect: CGRect, clippedTo size: CGSize) -> CGRect {
        guard !rect.isEmpty, !rect.isInfinite else { return .zero }
        let minX = rect.minX.rounded(.down)
        let minY = rect.minY.rounded(.down)
        let outward = CGRect(x: minX, y: minY, width: rect.maxX.rounded(.up) - minX, height: rect.maxY.rounded(.up) - minY)
        let clipped = outward.intersection(CGRect(origin: .zero, size: size))
        return clipped.isEmpty ? .zero : clipped
    }

    /// A top-left rect in the bottom-left space of an image `imageHeight` pixels tall.
    static func bottomLeft(_ topLeft: CGRect, imageHeight: Int) -> CGRect {
        flipped(topLeft, imageHeight: imageHeight)
    }

    /// A bottom-left rect in the model's top-left space. The inverse of `bottomLeft`.
    static func topLeft(_ bottomLeft: CGRect, imageHeight: Int) -> CGRect {
        flipped(bottomLeft, imageHeight: imageHeight)
    }

    private static func flipped(_ rect: CGRect, imageHeight: Int) -> CGRect {
        guard !rect.isNull else { return rect }
        return CGRect(x: rect.minX, y: CGFloat(imageHeight) - rect.maxY, width: rect.width, height: rect.height)
    }
}
