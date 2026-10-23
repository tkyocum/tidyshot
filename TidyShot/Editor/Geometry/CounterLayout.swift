import CoreGraphics

/// Where a new counter sits and how big its number is drawn (spec 2.12, Counter), in image pixels
/// with a top-left origin. Pure, so the model, `AnnotationDrawing` and the tests share it.
nonisolated enum CounterLayout {
    /// The number's size when it fits: this fraction of the diameter.
    static let fontSizeFraction: CGFloat = 0.55
    /// The widest the number's line may be: this fraction of the diameter.
    static let widthFraction: CGFloat = 0.8
    /// How many times `fontSize` measures again after shrinking. It settles in a few; this bounds a
    /// line that keeps landing a hair over the limit.
    private static let maximumPasses = 10

    /// The size of `number`'s font in a counter `diameter` across: `fontSizeFraction × diameter`,
    /// or smaller when the line's typographic width there is over `widthFraction × diameter`, so any
    /// number of digits fits. One and two digits keep the full size; three are the first to shrink.
    /// 0 for a diameter that is not positive.
    static func fontSize(number: Int, diameter: CGFloat) -> CGFloat {
        guard diameter > 0 else { return 0 }
        let text = String(number)
        let limit = widthFraction * diameter
        var size = fontSizeFraction * diameter
        var width = TextLayout.width(of: text, font: TextLayout.font(size: size))
        // The system font's optical sizes are wider per point at smaller sizes, so the width does
        // not scale exactly with the size and one pass may not be enough.
        var passes = 0
        while width > limit, passes < maximumPasses {
            size *= limit / width
            width = TextLayout.width(of: text, font: TextLayout.font(size: size))
            passes += 1
        }
        return size
    }

    /// The centre of a counter `diameter` across placed by a press at `press`: on each axis the
    /// press clamped so the whole circle is inside `bounds` (the image, or the applied crop), or the
    /// middle of `bounds` on an axis where they are narrower than the counter.
    static func center(forPress press: CGPoint, diameter: CGFloat, within bounds: CGRect) -> CGPoint {
        func axis(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            guard high - low >= diameter else { return (low + high) / 2 }
            return min(max(value, low + diameter / 2), high - diameter / 2)
        }
        return CGPoint(x: axis(press.x, bounds.minX, bounds.maxX), y: axis(press.y, bounds.minY, bounds.maxY))
    }
}
