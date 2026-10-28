import Foundation

/// A ring's animation (design, Click highlights, Animation): it grows from half size over
/// `grow`, holds while the button is down, and once the grow has finished and the button is up
/// it expands to `fadeScale` and fades out over `fade`.
nonisolated enum ClickRingTiming {
    static let grow: TimeInterval = 0.15
    static let fade: TimeInterval = 0.35
    static let startScale: CGFloat = 0.5
    static let fadeScale: CGFloat = 1.3

    /// When the fade starts: at the up, but never before the grow has finished.
    static func fadeStart(down: TimeInterval, up: TimeInterval) -> TimeInterval {
        max(up, down + grow)
    }

    /// From the down to the end of the fade: 0.5 s for a quick click.
    static func visibleDuration(down: TimeInterval, up: TimeInterval) -> TimeInterval {
        fadeStart(down: down, up: up) - down + fade
    }

    /// How many frames at `fps` show a ring visible from `start` for `duration`: the frames `i`
    /// with `start ≤ i / fps < start + duration`.
    static func framesShowing(start: TimeInterval, duration: TimeInterval, fps: Int) -> Int {
        guard fps > 0, duration > 0 else { return 0 }
        let rate = Double(fps)
        let end = start + duration
        let first = max(0, Int((start * rate).rounded(.down)))
        let last = Int((end * rate).rounded(.up))
        guard first <= last else { return 0 }
        return (first...last).count { i in
            let time = Double(i) / rate
            return start <= time && time < end
        }
    }
}
