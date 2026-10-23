import CoreGraphics

/// Where a capture sits on its background, in pixels. Pure: no drawing.
nonisolated struct BackgroundLayout: Equatable, Sendable {
    /// The longest side of content a background accepts.
    static let maximumContentSide = 16_384
    /// The longest side of the finished canvas.
    static let maximumCanvasSide = 32_768
    /// The most pixels the finished canvas may have (16,384 x 16,384, about 1 GB at 4 bytes each).
    static let maximumCanvasArea = 16_384 * 16_384

    let canvasSize: CGSize
    /// The content's place on the canvas, top-left origin, whole pixels.
    let contentRect: CGRect
    /// The corner radius of the content, in pixels.
    let radius: CGFloat

    /// The layout for content of `contentSize` pixels, or nil when the content or the canvas (a side
    /// or the area) is too large to draw (or the content is empty).
    static func make(contentSize: CGSize, style: BackgroundStyle, scale: CGFloat) -> BackgroundLayout? {
        let contentWidth = Int(contentSize.width.rounded(.up))
        let contentHeight = Int(contentSize.height.rounded(.up))
        guard contentWidth > 0, contentHeight > 0,
              max(contentWidth, contentHeight) <= maximumContentSide else { return nil }

        let padding = (max(0, style.padding) * Double(scale)).rounded()
        guard padding <= Double(maximumCanvasSide) else { return nil }
        let pad = Int(padding)

        var width = contentWidth + 2 * pad
        var height = contentHeight + 2 * pad
        if var terms = style.aspect.terms {
            if contentHeight > contentWidth { terms = (terms.height, terms.width) }
            if width * terms.height < height * terms.width {
                width = (height * terms.width + terms.height - 1) / terms.height
            } else {
                height = (width * terms.height + terms.width - 1) / terms.width
            }
        }
        guard width <= maximumCanvasSide, height <= maximumCanvasSide,
              width * height <= maximumCanvasArea else { return nil }

        let origin = CGPoint(x: (width - contentWidth) / 2, y: (height - contentHeight) / 2)
        let radius = min(max(0, style.cornerRadius * Double(scale)),
                         Double(min(contentWidth, contentHeight)) / 2)
        return BackgroundLayout(
            canvasSize: CGSize(width: width, height: height),
            contentRect: CGRect(origin: origin, size: CGSize(width: contentWidth, height: contentHeight)),
            radius: CGFloat(radius))
    }
}
