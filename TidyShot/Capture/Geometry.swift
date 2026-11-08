import CoreGraphics

/// Coordinate conversions between AppKit global space (origin bottom-left of the primary screen,
/// y up) and CoreGraphics / ScreenCaptureKit global space (origin top-left of the primary display,
/// y down). `primaryHeight` is `NSScreen.screens[0].frame.height`.
enum Geometry {
    static func cgRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The same flip: it is its own inverse.
    static func appKitRect(fromCG rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        cgRect(fromAppKit: rect, primaryHeight: primaryHeight)
    }

    static func cgPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    /// Converts a CG-global rect into the coordinate system of a display whose CG-global frame is `displayFrame`.
    static func displayLocal(_ rect: CGRect, in displayFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (Int((points.width * scale).rounded()), Int((points.height * scale).rounded()))
    }
}
