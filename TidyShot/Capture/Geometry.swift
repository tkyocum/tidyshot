import AppKit

/// Coordinate conversions between AppKit global space (origin bottom-left of the primary screen,
/// y up) and CoreGraphics / ScreenCaptureKit global space (origin top-left of the primary display,
/// y down). `primaryHeight` is `NSScreen.screens[0].frame.height`; the overloads without it read
/// it, the ones with it stay pure for the tests.
enum Geometry {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func cgRect(fromAppKit rect: CGRect) -> CGRect { cgRect(fromAppKit: rect, primaryHeight: primaryHeight) }
    static func appKitRect(fromCG rect: CGRect) -> CGRect { cgRect(fromAppKit: rect, primaryHeight: primaryHeight) }
    static func cgPoint(fromAppKit point: CGPoint) -> CGPoint { cgPoint(fromAppKit: point, primaryHeight: primaryHeight) }

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

nonisolated extension CGRect {
    /// `size` centred on `centre` with a whole-point origin, then moved inside `frame`.
    static func centred(_ size: CGSize, on centre: CGPoint, within frame: CGRect) -> CGRect {
        let x = min(max((centre.x - size.width / 2).rounded(), frame.minX), frame.maxX - size.width)
        let y = min(max((centre.y - size.height / 2).rounded(), frame.minY), frame.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
