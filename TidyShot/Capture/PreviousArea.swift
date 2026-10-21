import CoreGraphics

/// A rectangle kept in UserDefaults as JSON (`lastAreaRect`): CoreGraphics global points, origin
/// top left of the primary display, as `Selection.area` carries them. Four named numbers, so the
/// stored value is readable and Task 10 and Task 13 can share it.
nonisolated struct StoredRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Capture Previous Area (spec 2.9). Pure: which display the stored rect belongs to now, and the
/// rect clipped to it. All rects are CoreGraphics global points.
nonisolated enum PreviousArea {
    /// A connected display as the decision needs it. The coordinator builds these from `SCDisplay`.
    struct Display: Equatable, Sendable {
        let id: CGDirectDisplayID
        let frame: CGRect
    }

    enum Resolution: Equatable, Sendable {
        /// No usable rect: none stored, or smaller than one point on a side.
        case none
        /// A rect whose centre is on no connected display.
        case offScreen
        /// The rect clipped to the display holding its centre, and that display.
        case area(CGRect, CGDirectDisplayID)
    }

    /// The display holding the rect's centre (the first, when frames overlap, as with mirrored
    /// displays), and the rect clipped to it. The centre decides, not the larger overlap, so a rect
    /// that a display change split between two displays still lands on one.
    static func resolve(rect: CGRect?, displays: [Display]) -> Resolution {
        guard let rect, !rect.isNull, !rect.isInfinite, rect.width >= 1, rect.height >= 1 else { return .none }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = displays.first(where: { $0.frame.contains(centre) }) else { return .offScreen }
        return .area(rect.intersection(display.frame), display.id)
    }
}
