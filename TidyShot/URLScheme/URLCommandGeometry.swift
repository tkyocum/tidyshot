import CoreGraphics

/// A rect in CoreGraphics global points (origin top left of the main display, y down) and the
/// display it lies on.
nonisolated struct ScreenRect: Equatable, Sendable {
    var rect: CGRect
    var displayID: CGDirectDisplayID
}

/// A URL command's x, y, width and height on screen (spec 2.9, decision 13). Pure. The command
/// gives points from the bottom-left corner of one display, as CleanShot's API does; the capture
/// code takes CoreGraphics global points.
nonisolated enum URLCommandGeometry {
    /// A connected display, in `NSScreen.screens` order: display 1 is index 0, the main display.
    struct Display: Equatable, Sendable {
        let id: CGDirectDisplayID
        /// CoreGraphics global points.
        let frame: CGRect
    }

    enum Resolution: Equatable, Sendable {
        /// The rect clipped to its display.
        case area(ScreenRect)
        /// The display named, or display 1 when none is connected, does not exist.
        case noDisplay(Int)
        /// The rect leaves less than a point on its display.
        case outside(display: Int)
    }

    /// `display` (1-based) when given, otherwise the display at `pointerIndex`, otherwise display 1.
    /// The display's bottom-left corner is `(frame.minX, frame.maxY)` in CoreGraphics points.
    static func resolve(_ area: URLCommand.Area, display: Int?, displays: [Display], pointerIndex: Int?) -> Resolution {
        let index: Int
        if let display {
            guard displays.indices.contains(display - 1) else { return .noDisplay(display) }
            index = display - 1
        } else if let pointerIndex, displays.indices.contains(pointerIndex) {
            index = pointerIndex
        } else {
            guard !displays.isEmpty else { return .noDisplay(1) }
            index = 0
        }
        let frame = displays[index].frame
        let rect = CGRect(x: frame.minX + area.x, y: frame.maxY - area.y - area.height,
                          width: area.width, height: area.height)
        let clipped = rect.intersection(frame)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return .outside(display: index + 1) }
        return .area(ScreenRect(rect: clipped, displayID: displays[index].id))
    }

    /// The notification body for `.outside` (this plan's text; 2.9 has none for it).
    static func outsideMessage(display: Int) -> String {
        "The area leaves less than a point on display \(display)."
    }
}
