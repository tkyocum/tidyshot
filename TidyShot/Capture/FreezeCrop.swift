import CoreGraphics

/// One display's screenshot taken before the selection overlay appeared (Freeze screen). Pixels
/// run top to bottom as in any `CGImage`; `scale` is the display's pixels per point.
nonisolated struct FrozenSnapshot: Sendable {
    let displayID: CGDirectDisplayID
    let image: CGImage
    let scale: CGFloat
}

/// Cuts a selection out of a frozen display snapshot. Pure.
enum FreezeCrop {
    /// Pixels of slack for rounding: origin and size are rounded separately, so a rect that
    /// touches the far edge can come out one pixel too wide, or one too far left.
    static let roundingSlack: CGFloat = 1

    /// The selection (CoreGraphics global points) as a pixel rect in a snapshot of the display
    /// whose frame is `displayFrame`, top-left origin as `CGImage.cropping(to:)` takes it. The
    /// size is rounded as `Geometry.pixelSize` rounds it, so it equals the size of a live
    /// capture of the same rect. A rect that sticks out by at most `roundingSlack` pixels is
    /// moved inside, keeping its size. Nil when the size rounds to nothing, the scale or the
    /// image is empty, or the rect lies further outside the image.
    static func pixelRect(selection: CGRect, displayFrame: CGRect, scale: CGFloat, imageSize: CGSize) -> CGRect? {
        guard scale > 0, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let local = Geometry.displayLocal(selection, in: displayFrame)
        let size = Geometry.pixelSize(points: local.size, scale: scale)
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)
        guard width >= 1, height >= 1, width <= imageSize.width, height <= imageSize.height else { return nil }
        var x = (local.minX * scale).rounded()
        var y = (local.minY * scale).rounded()
        guard x >= -roundingSlack, y >= -roundingSlack else { return nil }
        x = max(x, 0)
        y = max(y, 0)
        let pastRight = x + width - imageSize.width
        let pastBottom = y + height - imageSize.height
        guard pastRight <= roundingSlack, pastBottom <= roundingSlack else { return nil }
        // Both are at most `x` and `y`, because the size fits the image, so the origin stays >= 0.
        x -= max(pastRight, 0)
        y -= max(pastBottom, 0)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// `image` cut to the selection, or nil when `pixelRect` is nil. The result shares the
    /// snapshot's pixels, so it keeps the whole display image alive for as long as it lives:
    /// up to about 60 MB for a 5K display while its Quick Access card shows. That is accepted.
    static func cropped(_ image: CGImage, selection: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGImage? {
        guard let rect = pixelRect(selection: selection, displayFrame: displayFrame, scale: scale,
                                   imageSize: CGSize(width: image.width, height: image.height)) else { return nil }
        return image.cropping(to: rect)
    }
}
