import CoreGraphics

/// A colour in sRGB, each component from 0 to 1. The editor model stores this rather than a
/// CGColor or an NSColor, so documents stay Codable and Sendable.
nonisolated struct RGBA: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The colour in the sRGB colour space, made on each call and never stored.
    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
