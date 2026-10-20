import CoreGraphics

/// How light the frozen screen is around the cursor, so the selection crosshair can be drawn in a
/// colour that shows up on it.
nonisolated enum Luminance {
    /// The side of the square sampled around the cursor, in points.
    static let sampleSide: CGFloat = 24
    /// The sample buffer's largest side; a bigger crop is drawn smaller, which averages it.
    static let maxBufferSide = 32

    /// The mean luma of `rect` in `image`, from 0 (black) to 1 (white), using Rec. 709 weights on
    /// the sRGB values. `rect` is in image pixels with the origin at the top left, as for
    /// `CGImage.cropping(to:)`; the part outside the image is ignored, and nil means nothing was
    /// left. The crop is drawn into an 8-bit RGBA buffer of at most 32 by 32 pixels, so a call costs
    /// the same at any display scale.
    static func mean(of image: CGImage, in rect: CGRect) -> Double? {
        let visible = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !visible.isNull, !visible.isEmpty, let cropped = image.cropping(to: visible),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = min(cropped.width, maxBufferSide)
        let height = min(cropped.height, maxBufferSide)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])
        }
        return total / Double(width * height) / 255
    }
}

/// The colour of the crosshair and the selection border for what is under the cursor.
nonisolated enum CrosshairStyle: Equatable, Sendable {
    /// Black at 0.8 alpha, on a light background.
    case dark
    /// White at 0.8 alpha, on a dark background.
    case light
    /// White with a one-pixel black edge beneath, readable on anything. Used until the snapshot
    /// arrives, and when the cursor is outside it.
    case outlined

    init(luminance: Double?) {
        guard let luminance else {
            self = .outlined
            return
        }
        self = luminance > 0.5 ? .dark : .light
    }
}
