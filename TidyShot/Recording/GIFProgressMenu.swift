import Foundation

/// The status menu's GIF items while conversions run (design, While it runs; plan Gap 5): the
/// disabled progress title and its Stop. With more than one conversion the percentage covers them
/// all, each weighted by its output frame count, and Stop stops every one.
nonisolated enum GIFProgressMenu {
    /// Nil when nothing converts. The percentage is rounded down and held at 99, so 100 % never
    /// shows while a conversion runs: the maker reports 1 once the GIF is written, and the entry
    /// stays until the save returns.
    static func items(_ conversions: [GIFProgress]) -> (progress: String, stop: String)? {
        guard !conversions.isEmpty else { return nil }
        let frames = conversions.reduce(0) { $0 + max(0, $1.frameCount) }
        let fraction = frames > 0
            ? conversions.reduce(0) { $0 + $1.fraction * Double(max(0, $1.frameCount)) } / Double(frames)
            : conversions.reduce(0) { $0 + $1.fraction } / Double(conversions.count)
        // The margin keeps 0.57 at 57 despite 0.57 × 100 being 56.999….
        let percent = min(Int((min(max(fraction, 0), 1) * 100 + 1e-9).rounded(.down)), 99)
        if conversions.count == 1 {
            return ("Making GIF… \(percent) %", "Stop Making GIF")
        }
        return ("Making \(conversions.count) GIFs… \(percent) %", "Stop Making GIFs")
    }
}
