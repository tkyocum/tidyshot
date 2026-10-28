import Foundation
import Testing
@testable import TidyShot

/// How long a ring shows and in how many frames (design, Click highlights, Animation).
struct ClickRingTimingTests {
    @Test func theConstants() {
        #expect(ClickRingTiming.grow == 0.15)
        #expect(ClickRingTiming.fade == 0.35)
        #expect(ClickRingTiming.startScale == 0.5)
        #expect(ClickRingTiming.fadeScale == 1.3)
    }

    /// Grow 0.15 s, then the 0.35 s fade.
    @Test func aQuickClickIsVisibleHalfASecond() {
        #expect(abs(ClickRingTiming.fadeStart(down: 2, up: 2.08) - 2.15) < 1e-9)
        #expect(abs(ClickRingTiming.visibleDuration(down: 2, up: 2.08) - 0.5) < 1e-9)
        #expect(abs(ClickRingTiming.visibleDuration(down: 0, up: 0) - 0.5) < 1e-9)
    }

    @Test func anUpDuringTheGrowWaitsForIt() {
        #expect(abs(ClickRingTiming.fadeStart(down: 1, up: 1.05) - 1.15) < 1e-9)
        #expect(abs(ClickRingTiming.fadeStart(down: 1, up: 1.15) - 1.15) < 1e-9)
    }

    @Test func aDragsRingLastsFromDownToUpPlusTheFade() {
        #expect(ClickRingTiming.fadeStart(down: 1, up: 3) == 3)
        #expect(abs(ClickRingTiming.visibleDuration(down: 1, up: 3) - 2.35) < 1e-9)
    }

    /// A quick click shows in about 5 frames at 10 fps, 7 at 15, 10 at 20, 15 at 30 and 30 at 60,
    /// give or take one, wherever it starts within a frame.
    @Test(arguments: [(10, 5), (15, 7), (20, 10), (30, 15), (60, 30)])
    func aQuickClicksFrames(fps: Int, frames: Int) {
        let duration = ClickRingTiming.visibleDuration(down: 0, up: 0)
        for start in [0, 0.02, 0.049] {
            let shown = ClickRingTiming.framesShowing(start: start, duration: duration, fps: fps)
            #expect(abs(shown - frames) <= 1, "start \(start) at \(fps) fps showed \(shown)")
        }
    }

    /// The frames `i` with `start ≤ i / fps < start + duration`.
    @Test func framesShowingCountsTheHalfOpenSpan() {
        #expect(ClickRingTiming.framesShowing(start: 0, duration: 0.5, fps: 10) == 5)
        #expect(ClickRingTiming.framesShowing(start: 0, duration: 0.5, fps: 15) == 8)
        #expect(ClickRingTiming.framesShowing(start: 0.02, duration: 0.5, fps: 15) == 7)
        #expect(ClickRingTiming.framesShowing(start: 0.1, duration: 0.1, fps: 10) == 1)
        #expect(ClickRingTiming.framesShowing(start: 0.01, duration: 0.05, fps: 10) == 0)
        #expect(ClickRingTiming.framesShowing(start: 1, duration: 0, fps: 30) == 0)
    }
}
