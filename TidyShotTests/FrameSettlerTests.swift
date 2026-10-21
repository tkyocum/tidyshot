import Foundation
import Testing
@testable import TidyShot

struct FrameSettlerTests {
    let t0 = ContinuousClock.now

    func at(_ milliseconds: Int) -> ContinuousClock.Instant { t0 + .milliseconds(milliseconds) }

    func frame(_ hash: UInt64, _ milliseconds: Int) -> FrameSettler.Observation {
        .frame(hash: hash, at: at(milliseconds))
    }

    /// A grey frame of `width` by `height` whose pixels are `value(x, y)`.
    func grey(width: Int = 12, height: Int = 9, _ value: (Int, Int) -> UInt8) -> ScrollFrame {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = value(x, y)
                let i = (y * width + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return ScrollFrame(bgra: Data(bytes), width: width, height: height, bytesPerRow: width * 4)
    }

    /// The answer to each observation, in order, from a fresh settler.
    func settled(_ observations: [FrameSettler.Observation], baseline: UInt64? = nil,
                 quiet: Duration = FrameSettler.defaultQuiet,
                 timeout: Duration = FrameSettler.defaultTimeout) -> [Bool] {
        var settler = FrameSettler(stepStart: t0, baselineHash: baseline, quiet: quiet, timeout: timeout)
        return observations.map { settler.observe($0) }
    }

    @Test func settlesOnceNothingNewArrivedForTheQuietTime() {
        let answers = settled([frame(1, 20), frame(2, 60), .idle(at: at(150)), .idle(at: at(209)), .idle(at: at(210))])
        #expect(answers == [false, false, false, false, true])
    }

    /// A repeat of the same hash is not new content, so it does not restart the quiet time.
    @Test func framesWithTheSameHashDoNotRestartTheQuietTime() {
        #expect(settled([frame(7, 10), frame(7, 100), frame(7, 159), frame(7, 160)]) == [false, false, false, true])
    }

    /// A display that keeps changing (a video, a spinner) settles at the timeout.
    @Test func changingContentSettlesAtTheTimeout() {
        let times = Array(stride(from: 50, through: 2000, by: 50))
        let answers = settled(times.enumerated().map { frame(UInt64($0.offset), $0.element) })
        #expect(times[answers.firstIndex(of: true)!] == 1500)
        #expect(answers.filter { $0 }.count == times.filter { $0 >= 1500 }.count)
    }

    @Test func aBaselineHashMeansTheFirstUnchangedFrameIsNotNews() {
        #expect(settled([frame(9, 150)], baseline: 9) == [true])
        #expect(settled([frame(9, 150)], baseline: 8) == [false])
        #expect(settled([frame(9, 10), frame(9, 150), frame(9, 160)]) == [false, false, true])
    }

    @Test func idleFramesCountAsUnchanged() {
        #expect(settled([.idle(at: at(100)), .idle(at: at(150))], baseline: 1) == [false, true])
    }

    /// A timer can ask without a frame: the quiet time runs from the step when nothing arrived.
    @Test func settledCanBeAskedWithoutAnObservation() {
        let settler = FrameSettler(stepStart: t0)
        #expect(!settler.isSettled(at: at(149)))
        #expect(settler.isSettled(at: at(150)))
        var busy = FrameSettler(stepStart: t0)
        let answer = busy.observe(frame(1, 1000))
        #expect(!answer)
        #expect(!busy.isSettled(at: at(1100)))
        #expect(busy.isSettled(at: at(1500)))
    }

    @Test func customQuietAndTimeoutApply() {
        let quiet = Duration.milliseconds(40), timeout = Duration.milliseconds(100)
        #expect(settled([frame(1, 10), frame(1, 50)], quiet: quiet, timeout: timeout) == [false, true])
        #expect(settled([frame(1, 30), frame(2, 60), frame(3, 100)], quiet: quiet, timeout: timeout) == [false, false, true])
    }

    @Test func contentHashIsStableAndSeesContentChanges() {
        let a = grey { x, y in UInt8((x * 7 + y * 13) % 200) }
        let same = grey { x, y in UInt8((x * 7 + y * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) == FrameSettler.contentHash(of: same, ignoringRightColumns: 2))
        let changed = grey { x, y in x == 4 && y == 3 ? 0 : UInt8((x * 7 + y * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) != FrameSettler.contentHash(of: changed, ignoringRightColumns: 2))
        let scrolled = grey { x, y in UInt8((x * 7 + (y + 1) * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) != FrameSettler.contentHash(of: scrolled, ignoringRightColumns: 2))
    }

    /// The scrollbar fades in and out after a scroll; its columns are not content.
    @Test func contentHashIgnoresTheScrollbarColumns() {
        let a = grey { x, y in UInt8((x * 7 + y * 13) % 200) }
        let fading = grey { x, y in x >= 10 ? 5 : UInt8((x * 7 + y * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) == FrameSettler.contentHash(of: fading, ignoringRightColumns: 2))
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 0) != FrameSettler.contentHash(of: fading, ignoringRightColumns: 0))
    }
}
