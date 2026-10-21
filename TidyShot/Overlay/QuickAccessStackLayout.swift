import CoreGraphics

/// Where each Quick Access card goes. `visibleFrame` is an AppKit screen rect (origin
/// bottom-left). Index 0 is the newest card, at the corner (`OverlayGeometry.frame`); each older
/// card sits one card height plus `spacing` further from the corner: below it from a top
/// corner, above it from a bottom corner.
nonisolated enum QuickAccessStackLayout {
    static let margin: CGFloat = 16
    static let spacing: CGFloat = 10

    static func frames(count: Int, cardSize: CGSize, corner: OverlayCorner, visibleFrame: CGRect,
                       margin: CGFloat = QuickAccessStackLayout.margin,
                       spacing: CGFloat = QuickAccessStackLayout.spacing) -> [CGRect] {
        guard count > 0 else { return [] }
        let first = OverlayGeometry.frame(size: cardSize, corner: corner, in: visibleFrame, margin: margin)
        let step = cardSize.height + spacing
        let direction: CGFloat = switch corner {
        case .topLeft, .topRight: -1
        case .bottomLeft, .bottomRight: 1
        }
        return (0..<count).map { first.offsetBy(dx: 0, dy: direction * step * CGFloat($0)) }
    }

    /// How many cards fit `visibleHeight` with `margin` above and below, at most `limit` and
    /// never fewer than one.
    static func capacity(cardHeight: CGFloat, visibleHeight: CGFloat,
                         margin: CGFloat = QuickAccessStackLayout.margin,
                         spacing: CGFloat = QuickAccessStackLayout.spacing, limit: Int) -> Int {
        let fits = Int(((visibleHeight - 2 * margin + spacing) / (cardHeight + spacing)).rounded(.down))
        return max(1, min(limit, fits))
    }
}
