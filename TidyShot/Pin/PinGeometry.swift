import CoreGraphics

/// Pin to screen's geometry (spec 2.9). AppKit global points, origin bottom-left.
nonisolated enum PinGeometry {
    /// The shorter side of a pin never goes below this by resizing or zooming, or below what it
    /// is when it starts under it (a fitted strip).
    static let minimumSide: CGFloat = 40
    /// A pin opens at most this fraction of the visible frame on each axis.
    static let fitFraction: CGFloat = 0.8
    /// Command-plus multiplies the size by this, Command-minus divides by it.
    static let zoomStep: CGFloat = 1.1
    /// An image with a side over this many pixels is shown from a downsample.
    static let maxPixelSide = 8_192

    /// Where a pin opens: `imagePoints` (the capture's size in points) scaled down, never up, to fit
    /// `fitFraction` of `visibleFrame`, centred on `preferred`'s centre (the area the capture was
    /// taken from) or on the visible frame, with a whole-point origin, then moved inside
    /// `visibleFrame`. `imagePoints` has positive sides.
    static func initialFrame(imagePoints: CGSize, preferred: CGRect?, visibleFrame: CGRect) -> CGRect {
        let fit = min(1, visibleFrame.width * fitFraction / imagePoints.width,
                      visibleFrame.height * fitFraction / imagePoints.height)
        let size = CGSize(width: imagePoints.width * fit, height: imagePoints.height * fit)
        let centre = preferred.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        var x = (centre.x - size.width / 2).rounded()
        var y = (centre.y - size.height / 2).rounded()
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// An arrow key: one point, or ten with Shift, in the direction (`dx`, `dy`), up being +1.
    static func nudged(_ frame: CGRect, dx: Int, dy: Int, shift: Bool) -> CGRect {
        let step: CGFloat = shift ? 10 : 1
        return frame.offsetBy(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
    }

    /// `frame` scaled by `factor` about its centre. A factor that would take the shorter side
    /// below `min(minimumSide, its current value)` is raised to the one that reaches it exactly.
    /// The result is capped to `visibleFrame` and whole-point (see `settled`).
    static func zoomed(_ frame: CGRect, factor: CGFloat, visibleFrame: CGRect) -> CGRect {
        let shorter = min(frame.width, frame.height)
        let floor = min(minimumSide, shorter)
        let applied = shorter * factor < floor ? floor / shorter : factor
        return settled(centre: CGPoint(x: frame.midX, y: frame.midY),
                       size: CGSize(width: frame.width * applied, height: frame.height * applied),
                       visibleFrame: visibleFrame)
    }

    /// The capture's point size, about the centre of `frame`, capped to `visibleFrame` and
    /// whole-point (see `settled`).
    static func actualSize(_ frame: CGRect, imagePoints: CGSize, visibleFrame: CGRect) -> CGRect {
        settled(centre: CGPoint(x: frame.midX, y: frame.midY), size: imagePoints, visibleFrame: visibleFrame)
    }

    /// A frame of `size` about `centre`: scaled down, keeping the aspect ratio, to fit
    /// `visibleFrame`, then with the size and the origin rounded to whole points.
    private static func settled(centre: CGPoint, size: CGSize, visibleFrame: CGRect) -> CGRect {
        let cap = min(1, visibleFrame.width / size.width, visibleFrame.height / size.height)
        let width = (size.width * cap).rounded()
        let height = (size.height * cap).rounded()
        return CGRect(x: (centre.x - width / 2).rounded(), y: (centre.y - height / 2).rounded(),
                      width: width, height: height)
    }

    /// The panel's `contentMinSize`: the image's aspect with the shorter side at
    /// `min(minimumSide, the shorter side of initial)`.
    static func minimumSize(aspect: CGSize, initial: CGSize) -> CGSize {
        let floor = min(minimumSide, initial.width, initial.height)
        if aspect.width <= aspect.height {
            return CGSize(width: floor, height: floor * aspect.height / aspect.width)
        }
        return CGSize(width: floor * aspect.width / aspect.height, height: floor)
    }

    /// The longest side to downsample to, or nil when the image needs none: only an image with a
    /// side over `maxPixelSide` is, to the screen's longer pixel side, never above `maxPixelSide`.
    static func downsampleMaxSide(pixelWidth: Int, pixelHeight: Int, screenPixelSide: Int) -> Int? {
        guard max(pixelWidth, pixelHeight) > maxPixelSide else { return nil }
        return min(max(screenPixelSide, 1), maxPixelSide)
    }
}

/// A pin's opacity: 10 % to 100 % in steps of 5 %, in whole percents so nothing drifts.
nonisolated enum PinOpacity {
    static let presets: [Double] = [1.0, 0.9, 0.75, 0.5, 0.25]
    private static let step = 5
    private static let range = 10...100

    /// `opacity` moved by `steps` of 5 %, snapped to the 5 % grid and clamped to 10 % to 100 %.
    static func changed(_ opacity: Double, steps: Int) -> Double {
        let percent = Int((opacity * 100).rounded())
        let snapped = Int((Double(percent) / Double(step)).rounded()) * step
        let next = min(max(snapped + steps * step, range.lowerBound), range.upperBound)
        return Double(next) / 100
    }

    /// `90%` for 0.9: the menu item's title.
    static func title(for opacity: Double) -> String {
        "\(Int((opacity * 100).rounded()))%"
    }

    /// Whether two opacities are the same preset (the menu's check mark).
    static func matches(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.001
    }
}

/// What a key does while a pin is key.
nonisolated enum PinCommand: Equatable, Sendable {
    case nudge(dx: Int, dy: Int, shift: Bool)
    case zoomIn
    case zoomOut
    case actualSize
    case copyImage
    case close
}

nonisolated enum PinKeys {
    /// The command for a key press, or nil. Escape and the arrows without Command; Command with
    /// `=`/`+`, `-`, `0`, `c` or `w` (`characters` is `charactersIgnoringModifiers`). Option and
    /// Control cancel any match, and Shift only counts for the arrows and the zoom keys (`+` is
    /// Shift-`=`).
    static func command(keyCode: UInt16, characters: String?, command: Bool, shift: Bool,
                        option: Bool, control: Bool) -> PinCommand? {
        guard !option, !control else { return nil }
        if !command {
            switch keyCode {
            case 53: return .close
            case 123: return .nudge(dx: -1, dy: 0, shift: shift)
            case 124: return .nudge(dx: 1, dy: 0, shift: shift)
            case 125: return .nudge(dx: 0, dy: -1, shift: shift)
            case 126: return .nudge(dx: 0, dy: 1, shift: shift)
            default: return nil
            }
        }
        switch characters?.lowercased() ?? "" {
        case "=", "+": return .zoomIn
        case "-", "_": return .zoomOut
        case "0": return shift ? nil : .actualSize
        case "c": return shift ? nil : .copyImage
        case "w": return shift ? nil : .close
        default: return nil
        }
    }
}
