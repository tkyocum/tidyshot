import CoreGraphics
import Foundation

/// Shift and Option constraints on a pointer drag, and the minimum drag. Points are image pixels
/// with a top-left origin; `zoom` is view points per image pixel.
nonisolated enum DragGeometry {
    /// A drag shorter than this many view points is a click: 2 / zoom image pixels.
    static let minimumDragPoints: CGFloat = 2

    /// The rect a drag spans, standardized. `square` (Shift) makes both sides the longer one and
    /// grows toward the pointer in each axis, so the square stays in the drag's quadrant.
    /// `fromCentre` (Option) treats `from` as the centre and mirrors the pointer's offset.
    static func rect(from: CGPoint, to: CGPoint, square: Bool, fromCentre: Bool) -> CGRect {
        var dx = to.x - from.x
        var dy = to.y - from.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if fromCentre {
            return CGRect(x: from.x - abs(dx), y: from.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
        }
        return CGRect(x: from.x, y: from.y, width: dx, height: dy).standardized
    }

    /// The end of a two-point drag. With `snap45` (Shift), `to` is projected onto the nearest of
    /// the eight 45-degree directions around `from`: a horizontal or vertical snap keeps the
    /// pointer's x or y, and a diagonal snap keeps the mean of the two offsets.
    static func segmentEnd(from: CGPoint, to: CGPoint, snap45: Bool) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard snap45, dx != 0 || dy != 0 else { return to }
        // 0 is right, 2 is down (image y grows downward), 4 is left, 6 is up.
        let octant = (Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 8
        switch octant {
        case 0, 4:
            return CGPoint(x: to.x, y: from.y)
        case 2, 6:
            return CGPoint(x: from.x, y: to.y)
        default:
            let sx: CGFloat = octant == 1 || octant == 7 ? 1 : -1
            let sy: CGFloat = octant == 1 || octant == 3 ? 1 : -1
            let offset = (dx * sx + dy * sy) / 2
            return CGPoint(x: from.x + sx * offset, y: from.y + sy * offset)
        }
    }

    /// Shift during a move: the larger component of the total delta since mouseDown, the other
    /// zeroed. A tie keeps the horizontal one.
    static func axisLocked(_ delta: CGVector) -> CGVector {
        abs(delta.dx) >= abs(delta.dy) ? CGVector(dx: delta.dx, dy: 0) : CGVector(dx: 0, dy: delta.dy)
    }

    /// For the rect tools: both sides at least `minimumDragPoints / zoom`. `CGRect.width` and
    /// `height` are magnitudes, so an unstandardized rect works too.
    static func isLargeEnough(_ rect: CGRect, zoom: CGFloat) -> Bool {
        let minimum = minimumDragPoints / zoom
        return rect.width >= minimum && rect.height >= minimum
    }

    /// For the two-point tools: the segment at least `minimumDragPoints / zoom` long, so a
    /// horizontal or vertical arrow is kept.
    static func isLongEnough(from: CGPoint, to: CGPoint, zoom: CGFloat) -> Bool {
        hypot(to.x - from.x, to.y - from.y) >= minimumDragPoints / zoom
    }
}
