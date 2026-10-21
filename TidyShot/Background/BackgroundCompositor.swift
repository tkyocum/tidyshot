import CoreGraphics

/// Puts a capture on a background. CoreGraphics only: it runs off the main actor and needs no
/// NSGraphicsContext.
nonisolated enum BackgroundCompositor {
    /// The shadow under the content, in points; `scale` turns them into pixels. The editor's
    /// preview draws the same shadow with a layer.
    static let shadowOffset: CGFloat = 8
    static let shadowBlur: CGFloat = 24
    static let shadowAlpha: CGFloat = 0.35

    /// `content` on the fill `style` names, as an 8-bit premultiplied RGBA bitmap in sRGB. The
    /// desktop picture and the custom image arrive as `fillImage`; when it is nil, those fills draw
    /// gradient preset 0. Nil when the layout is nil or no bitmap can be made.
    static func compose(_ content: CGImage, style: BackgroundStyle, scale: CGFloat,
                        fillImage: CGImage?) -> CGImage? {
        let contentSize = CGSize(width: content.width, height: content.height)
        guard let layout = BackgroundLayout.make(contentSize: contentSize, style: style, scale: scale),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(layout.canvasSize.width),
                                      height: Int(layout.canvasSize.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        drawFill(style.fill, fillImage: fillImage, in: context, canvas: canvas, space: space)

        // The layout is top-left origin; the context is bottom-left.
        let rect = CGRect(x: layout.contentRect.minX,
                          y: canvas.height - layout.contentRect.maxY,
                          width: layout.contentRect.width, height: layout.contentRect.height)
        let path = CGPath(roundedRect: rect, cornerWidth: layout.radius, cornerHeight: layout.radius,
                          transform: nil)
        context.saveGState()
        if style.shadow {
            context.setShadow(offset: CGSize(width: 0, height: -shadowOffset * scale),
                              blur: shadowBlur * scale,
                              color: CGColor(gray: 0, alpha: shadowAlpha))
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        context.addPath(path)
        context.clip()
        context.interpolationQuality = .none
        context.draw(content, in: rect)
        if style.shadow { context.endTransparencyLayer() }
        context.restoreGState()
        return context.makeImage()
    }

    /// The fill alone, `size` pixels, as `compose` draws it under the content: the editor's preview
    /// shows it behind the capture's layers. Nil when no bitmap can be made.
    static func fill(_ fill: BackgroundFill, size: CGSize, fillImage: CGImage?) -> CGImage? {
        guard size.width >= 1, size.height >= 1,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        drawFill(fill, fillImage: fillImage, in: context,
                 canvas: CGRect(x: 0, y: 0, width: context.width, height: context.height), space: space)
        return context.makeImage()
    }

    private static func drawFill(_ fill: BackgroundFill, fillImage: CGImage?, in context: CGContext,
                                 canvas: CGRect, space: CGColorSpace) {
        switch fill {
        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(canvas)
        case .desktopPicture, .customImage:
            if let fillImage, fillImage.width > 0, fillImage.height > 0 {
                drawAspectFill(fillImage, in: context, canvas: canvas)
            } else {
                drawGradient(0, in: context, canvas: canvas, space: space)
            }
        case .gradient(let index):
            drawGradient(index, in: context, canvas: canvas, space: space)
        }
    }

    /// Top-left corner to bottom-right corner. An index out of range draws preset 0.
    private static func drawGradient(_ index: Int, in context: CGContext, canvas: CGRect,
                                     space: CGColorSpace) {
        let presets = BackgroundPresets.gradients
        let preset = presets.indices.contains(index) ? presets[index] : presets[0]
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: [preset.first.cgColor, preset.second.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: canvas.minX, y: canvas.maxY),
                                   end: CGPoint(x: canvas.maxX, y: canvas.minY), options: [])
    }

    /// Scaled to cover the canvas, centred, and clipped by it.
    private static func drawAspectFill(_ image: CGImage, in context: CGContext, canvas: CGRect) {
        let factor = max(canvas.width / CGFloat(image.width), canvas.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
        let rect = CGRect(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2,
                          width: size.width, height: size.height)
        context.saveGState()
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        context.restoreGState()
    }
}
