import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The manual scrolling session on synthetic frames (spec 2.8, Session model): a fake source, the
/// real stitch engine, a fake clock. Frames are 160 x 400 pixels at scale 2: a 40 row header, a
/// 30 row footer and a 330 row band over a 2,000 row page.
struct ScrollCaptureSessionTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    nonisolated struct StreamBroke: LocalizedError {
        var errorDescription: String? { "The display went to sleep." }
    }

    func makePage() -> SyntheticPage {
        SyntheticPage(width: 160, height: 400, header: 40, footer: 30, pageHeight: 2000)
    }

    func makeSession(_ page: SyntheticPage, maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight)
        -> (session: ScrollCaptureSession, source: FakeFrameSource, clock: FakeScrollClock) {
        let source = FakeFrameSource()
        let clock = FakeScrollClock()
        let session = ScrollCaptureSession(
            source: source, engine: ScrollStitchEngine(finder: page.finder, maxPixelHeight: maxPixelHeight),
            area: CGRect(x: 100, y: 100, width: CGFloat(page.width) / 2, height: CGFloat(page.height) / 2),
            scale: 2, colorSpace: sRGB, clock: clock)
        return (session, source, clock)
    }

    func send(_ page: inout SyntheticPage, _ source: FakeFrameSource, offsets: [Int]) {
        for offset in offsets {
            source.send(.frame(page.frame(at: offset, animated: false)))
        }
    }

    /// Start, frames scrolled by the user, Done: the page from the top down to where the user
    /// stopped, header once, footer once, pixel for pixel.
    @Test func startFramesAndDoneGiveTheStitchedPage() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        var ended: [ScrollCaptureOutcome] = []
        session.onEnd = { ended.append($0) }
        #expect(session.phase == .ready)
        #expect(session.status == .readyManual)
        #expect(session.widthPixels == 160)
        #expect(session.heightPixels == 400)
        #expect(source.startCount == 0)

        await session.start()
        #expect(source.startCount == 1)
        #expect(session.phase == .capturing(.manual))
        #expect(session.status == .manualCapturing)
        send(&page, source, offsets: [0, 60, 120, 200, 300])
        try await eventually { session.heightPixels == 700 }
        #expect(session.framesRead == 5)

        await session.done()
        #expect(source.stopCount == 1)
        #expect(session.phase == .ended)
        #expect(ended.count == 1)
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        #expect(image.scale == 2)
        let comparison = page.compare(try stitchedPixels(of: image), reached: 300)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
        #expect(session.outcome?.failureNotice == nil)

        // A second Done, a Cancel or a Start after the end change nothing.
        await session.done()
        await session.cancel()
        await session.start()
        #expect(ended.count == 1)
        #expect(source.startCount == 1)
    }

    /// Cancel discards everything at once and stops the stream; before Start it never starts it.
    @Test func cancelGivesNothingAndStopsTheStream() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.start()
        send(&page, source, offsets: [0, 80])
        try await eventually { session.heightPixels == 480 }

        await session.cancel()
        guard case .cancelled? = session.outcome else {
            Issue.record("not cancelled")
            return
        }
        #expect(session.phase == .ended)
        #expect(source.stopCount >= 1)
        #expect(session.outcome?.imageToSave == nil)
        #expect(session.outcome?.failureNotice == nil)

        let (unstarted, idleSource, _) = makeSession(page)
        await unstarted.cancel()
        guard case .cancelled? = unstarted.outcome else {
            Issue.record("not cancelled")
            return
        }
        #expect(idleSource.startCount == 0)
    }

    /// `advance()` is Start, then Done. Done waits for the first frame; with no movement the
    /// result is that frame alone, which is also the preview until rows are stitched.
    @Test func doneWithoutMovementGivesTheFirstFrame() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.advance()
        #expect(session.phase == .capturing(.manual))
        await session.advance()
        #expect(session.phase == .capturing(.manual))
        #expect(!session.hasFirstFrame)
        #expect(source.stopCount == 0)

        let first = page.frame(at: 0, animated: false)
        source.send(.frame(first))
        source.send(.frame(page.frame(at: 0, animated: false)))
        try await eventually { session.hasFirstFrame }
        #expect(session.preview?.width == 160)
        #expect(session.preview?.height == 400)

        await session.advance()
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        let stitched = try stitchedPixels(of: image)
        #expect(stitched.height == 400)
        #expect(stitched.bgra == first.bgra)
    }

    /// At the cap the limit line shows for `endLineDelay`, then the session finishes by itself
    /// with exactly `maxPixelHeight` rows.
    @Test func theCapFinishesByItselfAfterTheLimitLine() async throws {
        var page = makePage()
        let (session, source, clock) = makeSession(page, maxPixelHeight: 600)
        await session.start()
        send(&page, source, offsets: [0, 100, 200, 300, 400])
        try await eventually { session.status == .heightLimit }
        #expect(session.heightPixels == 600)
        #expect(session.phase == .capturing(.manual))
        #expect(session.outcome == nil)

        await clock.advance(by: ScrollCaptureSession.endLineDelay)
        try await eventually { session.phase == .ended }
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        let stitched = try stitchedPixels(of: image)
        #expect(stitched.height == 600)
        #expect(page.compare(stitched, reached: 400).mismatched == 0)
    }

    /// A jump past the band loses the place: the too-fast line shows until a frame overlaps the
    /// last accepted one again, and the output has no gap.
    @Test func tooFastShowsTheLineUntilTheNextMovement() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.start()
        send(&page, source, offsets: [0, 100])
        try await eventually { session.heightPixels == 500 }
        #expect(session.status == .manualCapturing)

        send(&page, source, offsets: [700])
        try await eventually { session.status == .manualLost }
        #expect(session.status.text == "Too fast. Scroll back up a little.")
        #expect(session.heightPixels == 500)

        send(&page, source, offsets: [200])
        try await eventually { session.status == .manualCapturing && session.heightPixels == 600 }

        await session.done()
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        let comparison = page.compare(try stitchedPixels(of: image), reached: 200)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// A stream that stops by itself keeps what was stitched; with nothing stitched, or a stream
    /// that cannot start, there is only the reason. The notices use the spec's exact strings.
    @Test func aStreamErrorKeepsWhatWasStitched() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.start()
        send(&page, source, offsets: [0, 100])
        try await eventually { session.heightPixels == 500 }
        source.send(.stopped(StreamBroke()))
        try await eventually { session.phase == .ended }
        guard case .failed(let reason, let partial?)? = session.outcome else {
            Issue.record("no partial image")
            return
        }
        #expect(reason == "The display went to sleep.")
        let comparison = page.compare(try stitchedPixels(of: partial), reached: 100)
        #expect(comparison.actualHeight == 500)
        #expect(comparison.mismatched == 0)
        #expect(session.outcome?.imageToSave?.image.height == 500)
        #expect(session.outcome?.failureNotice?.title == "Scrolling capture stopped")
        #expect(session.outcome?.failureNotice?.body
                == "The capture stopped early: The display went to sleep. TidyShot saved what it had.")

        let (empty, emptySource, _) = makeSession(page)
        await empty.start()
        emptySource.send(.stopped(StreamBroke()))
        try await eventually { empty.phase == .ended }
        guard case .failed(let emptyReason, nil)? = empty.outcome else {
            Issue.record("expected a failure without an image")
            return
        }
        #expect(emptyReason == "The display went to sleep.")
        #expect(empty.outcome?.imageToSave == nil)
        #expect(empty.outcome?.failureNotice?.title == "Scrolling capture failed")
        #expect(empty.outcome?.failureNotice?.body == "The display went to sleep.")

        let (refused, refusedSource, _) = makeSession(page)
        refusedSource.startError = StreamBroke()
        await refused.start()
        guard case .failed("The display went to sleep.", nil)? = refused.outcome else {
            Issue.record("expected the start error")
            return
        }
        #expect(refused.phase == .ended)
    }

    /// The preview grows with the stitched rows, rebuilt at most every `previewInterval`, and
    /// is never wider than `ScrollCaptureLimits.previewMaxWidth`.
    @Test func previewFollowsTheStitchAtMostFourTimesASecond() async throws {
        var page = makePage()
        let (session, source, clock) = makeSession(page)
        #expect(ScrollCaptureSession.previewInterval == .milliseconds(250))
        await session.start()
        // The first move commits the first frame's header and band: 370 rows.
        send(&page, source, offsets: [0, 60])
        try await eventually { session.preview?.height == 370 }
        #expect(session.preview?.width == 160)
        #expect((session.preview?.width ?? .max) <= ScrollCaptureLimits.previewMaxWidth)

        // The next 60 rows come too soon after; they show once the interval has passed.
        send(&page, source, offsets: [120])
        try await eventually { session.heightPixels == 520 }
        #expect(session.preview?.height == 370)
        await clock.advance(by: .milliseconds(250))
        try await eventually { session.preview?.height == 430 }
        await session.cancel()
    }

    /// The checkbox counts only with the grant: without it the ready line is manual's and Start
    /// starts manual mode; the grant arriving while the panel shows enables it, and unticking
    /// the box is reported for `AppSettings`.
    @Test func autoScrollNeedsTheGrantAndTheCheckbox() async throws {
        let clock = FakeScrollClock()
        let world = FakeScrollWorld(page: makePage(), clock: clock, pointer: CGPoint(x: 140, y: 200))
        world.permitted = false
        let session = ScrollCaptureSession(
            source: world.source, engine: ScrollStitchEngine(finder: world.page.finder),
            area: CGRect(x: 100, y: 100, width: 80, height: 200), scale: 2, colorSpace: sRGB, clock: clock,
            autoScrollEnvironment: world.environment, prefersAutoScroll: true)
        var stored: [Bool] = []
        session.onAutoScrollChanged = { stored.append($0) }
        #expect(session.autoScroll)
        #expect(!session.isAutoScrollPermitted)
        #expect(!session.usesAutoScroll)
        #expect(session.status == .readyManual)

        world.permitted = true
        session.refreshAutoScrollPermission()
        #expect(session.isAutoScrollPermitted)
        #expect(session.status == .readyAuto)
        #expect(session.status.text == "Click Start, then hold the pointer over the area.")

        session.autoScroll = false
        #expect(session.status == .readyManual)
        #expect(stored == [false])

        await session.start()
        #expect(session.phase == .capturing(.manual))
        world.showFrame()
        try await eventually { session.hasFirstFrame }
        try await clock.run(for: .seconds(1))
        #expect(world.posted.isEmpty)
        await session.cancel()
    }
}
