import CoreGraphics
import Foundation

/// How far auto-scroll moves and how it posts the move (spec 2.8, Settling and the end). Pure.
nonisolated enum AutoScrollPlan {
    /// One wheel event moves at most this many points.
    static let maxEventPoints: CGFloat = 50
    /// Wheel events of one step are posted this far apart.
    static let eventSpacing: Duration = .milliseconds(10)
    /// A shrunk step never goes below this many points.
    static let minimumStepPoints: CGFloat = 40
    /// Each step after the first is this fraction of the last band's height.
    static let bandFraction: CGFloat = 0.6

    /// A step of `points` as whole-point wheel events of at most 50: 120 gives 50, 50, 20.
    static func events(forPoints points: CGFloat) -> [CGFloat] {
        var remaining = points.rounded()
        var events: [CGFloat] = []
        while remaining > 0 {
            let event = min(maxEventPoints, remaining)
            events.append(event)
            remaining -= event
        }
        return events
    }

    /// Half the area's height.
    static func firstStep(areaHeightPoints: CGFloat) -> CGFloat {
        (areaHeightPoints / 2).rounded()
    }

    /// 0.6 of the last accepted band (rows between the sticky header and footer), in whole points.
    static func nextStep(bandHeightPixels: Int, scale: CGFloat) -> CGFloat {
        max(1, (CGFloat(bandHeightPixels) * bandFraction / scale).rounded())
    }

    /// The step after a `.lost`: half, but not below 40 points and never larger than `points`.
    static func shrunk(_ points: CGFloat) -> CGFloat {
        min(points, max(minimumStepPoints, (points / 2).rounded()))
    }
}
