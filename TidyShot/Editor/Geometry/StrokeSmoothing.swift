import CoreGraphics

/// Freehand strokes: the pointer's samples are thinned when they are recorded, and the curve
/// through the thinned points is rebuilt from them whenever it is drawn or hit. All points are
/// image pixels.
nonisolated enum StrokeSmoothing {
    /// The spacing the tool keeps between recorded points, in view points. The tool divides it by
    /// the zoom, so a stroke made zoomed in is finer in the image.
    static let spacingPoints: CGFloat = 2
    /// Samples the curve gets between each pair of neighbouring points.
    static let segmentsPerSpan = 8

    /// `points` without those closer than `minDistance` to the last point kept, measured from that
    /// point and not from the previous sample, so a slow drift still adds points. The first and the
    /// last sample are always kept, so the stroke starts and ends where the pointer did.
    static func decimated(_ points: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var kept = [last]
        for point in points.dropFirst() {
            if hypot(point.x - last.x, point.y - last.y) >= minDistance {
                kept.append(point)
                last = point
            }
        }
        if let end = points.last, end != last { kept.append(end) }
        return kept
    }

    /// A uniform Catmull-Rom curve through `points`: the first point, then `segmentsPerSpan`
    /// samples for each span, the last of which is the span's end point itself, so the curve passes
    /// through every point and ends exactly on the last. The first and last points are repeated as
    /// their own neighbours. Fewer than three points come back unchanged.
    static func catmullRom(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var curve = [points[0]]
        curve.reserveCapacity(1 + (points.count - 1) * segmentsPerSpan)
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            for step in 1..<segmentsPerSpan {
                let t = CGFloat(step) / CGFloat(segmentsPerSpan)
                curve.append(CGPoint(x: spline(p0.x, p1.x, p2.x, p3.x, t), y: spline(p0.y, p1.y, p2.y, p3.y, t)))
            }
            // t = 1 is p2; appending it avoids a rounding error on the stroke's last point.
            curve.append(p2)
        }
        return curve
    }

    /// The smoothed curve as a path of straight pieces. Built on each call and never stored. One
    /// point gives a zero-length piece, which a round cap draws as a dot.
    static func path(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let curve = catmullRom(points)
        guard let first = curve.first else { return path }
        if curve.count == 1 {
            path.move(to: first)
            path.addLine(to: first)
        } else {
            path.addLines(between: curve)
        }
        return path
    }

    /// One coordinate of the uniform Catmull-Rom spline between `b` and `c` at `t` in 0...1.
    private static func spline(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
    }
}
