import CoreGraphics

/// The editor's fixed colours and line widths. Widths here are points; the model stores pixels.
nonisolated enum EditorPalette {
    private static let black = RGBA(red: 0, green: 0, blue: 0)
    private static let red = rgb(255, 59, 48)
    private static let orange = rgb(255, 149, 0)
    private static let yellow = rgb(255, 204, 0)
    private static let green = rgb(52, 199, 89)
    private static let teal = rgb(48, 176, 199)
    private static let blue = rgb(0, 122, 255)
    private static let purple = rgb(175, 82, 222)
    private static let pink = rgb(255, 45, 85)
    private static let white = RGBA(red: 1, green: 1, blue: 1)

    /// The colour popover's swatches, in order.
    static let swatches: [RGBA] = [black, red, orange, yellow, green, teal, blue, purple, pink, white]
    /// Rectangle and Arrow.
    static let defaultStroke = red
    /// Redact.
    static let defaultRedact = black
    /// The options popover's widths, also on keys 1 to 6.
    static let lineWidthsPoints: [CGFloat] = [2, 3, 4, 6, 8, 12]
    /// Text sizes in points, on keys 1 to 6 while the Text tool is active.
    static let textSizesPoints: [CGFloat] = [12, 16, 20, 28, 40, 56]
    /// New text starts at this size. It is not persisted: AppSettings keeps its seven editor keys.
    static let defaultTextSizePoints: CGFloat = 20
    /// A highlighter stroke's alpha. Any colour picked for the highlighter keeps it, so text stays
    /// readable under the multiply.
    static let highlighterAlpha: Double = 0.45
    /// The highlighter's colour until another is picked: the palette's yellow at `highlighterAlpha`.
    static let defaultHighlight = yellow.withAlpha(highlighterAlpha)
    /// The highlighter's width in points; also the last stop of `lineWidthsPoints`.
    static let highlighterWidthPoints: CGFloat = 12
    /// The Dim row's stops: the spotlight overlay's black alpha.
    static let spotlightDims: [Double] = [0.3, 0.5, 0.7]
    /// The Size row's counter diameters in points: Small, Medium and Large.
    static let counterDiametersPoints: [CGFloat] = [24, 32, 44]
    static let defaultCounterDiameterPoints: CGFloat = 32

    /// `color` at the highlighter's alpha.
    static func highlighterColor(from color: RGBA) -> RGBA {
        color.withAlpha(highlighterAlpha)
    }

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> RGBA {
        RGBA(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

/// Blur radius and pixel block in image pixels, from the points chosen in the UI.
nonisolated enum RedactionDefaults {
    /// The blur slider's range, in points.
    static let blurRangePoints: ClosedRange<CGFloat> = 4...24
    /// The pixel block slider's range, in points.
    static let blockRangePoints: ClosedRange<CGFloat> = 6...32

    /// The Gaussian sigma: `points` times the capture scale, never below 4 pt.
    static func blurRadius(points: CGFloat, scale: CGFloat) -> CGFloat {
        max(points, blurRangePoints.lowerBound) * scale
    }

    /// The mosaic block in whole pixels, so the grid stays on pixel boundaries: `points` times the
    /// capture scale, never below 6 pt, then capped at the region's shorter side (rounded down) so
    /// the region holds at least one block. Never below 1.
    static func block(points: CGFloat, scale: CGFloat, region: CGRect) -> CGFloat {
        let wanted = (max(points, blockRangePoints.lowerBound) * scale).rounded()
        let rect = region.standardized
        let shorterSide = min(rect.width, rect.height).rounded(.down)
        return max(1, min(wanted, shorterSide))
    }
}

/// The colours and sizes a new editor starts with, in points. AppSettings persists them, and an
/// editor reads them once when it opens.
nonisolated struct EditorDefaults: Equatable, Sendable {
    var strokeColor: RGBA
    var redactColor: RGBA
    var lineWidthPoints: CGFloat
    var blurRadiusPoints: CGFloat
    var blockPoints: CGFloat
    /// Spotlight's Shape: an ellipse when true, else a rectangle.
    var spotlightEllipse: Bool
    var counterDiameterPoints: CGFloat

    static let standard = EditorDefaults(strokeColor: EditorPalette.defaultStroke,
                                         redactColor: EditorPalette.defaultRedact,
                                         lineWidthPoints: 4, blurRadiusPoints: 8, blockPoints: 10,
                                         spotlightEllipse: false,
                                         counterDiameterPoints: EditorPalette.defaultCounterDiameterPoints)
}
