import CoreGraphics

/// The webcam bubble's size (design, Webcam bubble, Sizes), stored as `recordingBubbleSize`.
nonisolated enum BubbleSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    /// Anything but the three raw values reads as Medium.
    init(stored: String) {
        self = BubbleSize(rawValue: stored) ?? .medium
    }

    /// The circle's diameter in points.
    var diameter: CGFloat {
        switch self {
        case .small: 120
        case .medium: 180
        case .large: 260
        }
    }

    /// The size a double-click steps to.
    var next: BubbleSize {
        switch self {
        case .small: .medium
        case .medium: .large
        case .large: .small
        }
    }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

/// The bubble's right and bottom edges' distance from the recorded rect's, the one place
/// remembered across recordings and displays.
nonisolated struct BubbleInsets: Equatable, Sendable {
    var right: CGFloat
    var bottom: CGFloat

    static let standard = BubbleInsets(right: 16, bottom: 16)

    /// A stored inset; a negative or non-finite value reads as 16.
    static func reading(_ value: Double) -> CGFloat {
        value.isFinite && value >= 0 ? CGFloat(value) : 16
    }
}

/// Where the bubble sits in the recorded rect (design, Webcam bubble, Where it starts, and
/// memory; Dragging; Double-click). AppKit points, y up. The recorded rect is the area, or the
/// display's visible frame for fullscreen.
nonisolated enum BubblePlacement {
    /// What last moved the bubble; only the user's moves are remembered (plan Gap 14).
    enum Move: Equatable, Sendable {
        case start
        case reclamp
        case dragEnded
        case sizeStepped
    }

    /// The start: `insets` from the rect's right and bottom edges, then clamped.
    static func frame(recorded: CGRect, size: BubbleSize, insets: BubbleInsets) -> CGRect {
        let d = size.diameter
        let frame = CGRect(x: recorded.maxX - insets.right - d, y: recorded.minY + insets.bottom,
                           width: d, height: d)
        return clamp(frame, into: recorded)
    }

    /// The whole bubble inside `recorded`; in a dimension too small for it, centred on it.
    static func clamp(_ frame: CGRect, into recorded: CGRect) -> CGRect {
        func fit(_ origin: CGFloat, length: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
            guard upper - lower >= length else { return (lower + upper) / 2 - length / 2 }
            return Swift.min(Swift.max(origin, lower), upper - length)
        }
        let x = fit(frame.minX, length: frame.width, min: recorded.minX, max: recorded.maxX)
        let y = fit(frame.minY, length: frame.height, min: recorded.minY, max: recorded.maxY)
        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// `startFrame` moved by the pointer's travel from `start` to `current`, then clamped.
    static func drag(startFrame: CGRect, from start: CGPoint, to current: CGPoint,
                     in recorded: CGRect) -> CGRect {
        let moved = startFrame.offsetBy(dx: current.x - start.x, dy: current.y - start.y)
        return clamp(moved, into: recorded)
    }

    /// `size`'s diameter about the same centre, then clamped.
    static func step(_ frame: CGRect, to size: BubbleSize, in recorded: CGRect) -> CGRect {
        let d = size.diameter
        let centred = CGRect(x: frame.midX - d / 2, y: frame.midY - d / 2, width: d, height: d)
        return clamp(centred, into: recorded)
    }

    static func insets(of frame: CGRect, in recorded: CGRect) -> BubbleInsets {
        BubbleInsets(right: recorded.maxX - frame.maxX, bottom: frame.minY - recorded.minY)
    }

    /// The insets to store after `move`: only a drag's end writes them. A size step writes the
    /// size alone, so a clamp never makes the memory drift.
    static func storedInsets(after move: Move, frame: CGRect, recorded: CGRect) -> BubbleInsets? {
        switch move {
        case .start, .reclamp, .sizeStepped: nil
        case .dragEnded: insets(of: frame, in: recorded)
        }
    }
}
