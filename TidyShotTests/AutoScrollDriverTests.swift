import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// Auto-scroll on a fake world (spec 2.8, Auto-scroll driver): the real session, engine, end
/// detector, settler and step plan; a fake wheel, pointer, grant and clock. The area is 80 x 200
/// points at scale 2, so frames are 160 x 400 pixels: a 40 row header, a 330 row band and a
/// 30 row footer over a 2,000 row page (largest offset 1,670).
struct AutoScrollDriverTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let area = CGRect(x: 100, y: 100, width: 80, height: 200)
    static let inside = CGPoint(x: 140, y: 200)
    static let outside = CGPoint(x: 20, y: 20)

    func makeWorld(clock: FakeScrollClock, offset: Int = 0, pointer: CGPoint = inside) -> FakeScrollWorld {
        FakeScrollWorld(page: SyntheticPage(width: 160, height: 400, header: 40, footer: 30, pageHeight: 2000),
                        clock: clock, offset: offset, pointer: pointer)
    }

    func makeSession(_ world: FakeScrollWorld, maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight,
                     area: CGRect = Self.area) -> ScrollCaptureSession {
        ScrollCaptureSession(source: world.source,
                             engine: ScrollStitchEngine(finder: world.page.finder, maxPixelHeight: maxPixelHeight),
                             area: area, scale: 2, colorSpace: sRGB, clock: world.clock,
                             autoScrollEnvironment: world.environment, prefersAutoScroll: true)
    }

    /// Start, then the first frame: the page as the user arranged it.
    func start(_ session: ScrollCaptureSession, _ world: FakeScrollWorld) async throws {
        await session.start()
        world.showFrame()
        try await eventually { session.hasFirstFrame }
    }

    func image(of session: ScrollCaptureSession) throws -> StitchedImage {
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            throw FakeClockTimedOut()
        }
        return try stitchedPixels(of: image)
    }

    /// Steps of half the area, then 0.6 of the band, down to the end; one still retries, the
    /// second shows the end line and finishes. The image is the whole page.
    @Test func scrollsToTheEndAndFinishesOnTheSecondStill() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world)
        #expect(session.usesAutoScroll)
        #expect(session.status == .readyAuto)
        try await start(session, world)
        #expect(session.phase == .capturing(.auto))

        try await clock.run(until: { session.status == .autoReachedEnd })
        #expect(session.phase == .capturing(.auto))
        #expect(world.offset == world.page.maxOffset)
        // Whole-point events of at most 50, all downwards; the first step is 100 pt.
        #expect(world.posted.allSatisfy { $0 > 0 && $0 <= 50 })
        #expect(Array(world.posted.prefix(2)) == [50, 50])
        // Later steps are at most 0.6 of the 330 row band at scale 2, 99 pt (a blank stretch under
        // the header can measure the band shorter), and together they cover the page.
        #expect(world.posted.reduce(0, +) * 2 >= CGFloat(world.page.maxOffset))

        try await clock.run(until: { session.phase == .ended })
        let comparison = world.page.compare(try image(of: session), reached: world.page.maxOffset)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// Frames that reach the session 400 ms after each post, longer than the 150 ms quiet time:
    /// the frame from before the step is never taken as the settled one, so no step reads as
    /// still, the driver never reverses, and the image is the whole page.
    @Test func settlesOnlyOnAFrameFromAfterTheStep() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.frameDelay = .milliseconds(400)
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.status == .autoReachedEnd })
        #expect(world.posted.allSatisfy { $0 > 0 })
        #expect(world.offset == world.page.maxOffset)
        try await clock.run(until: { session.phase == .ended })
        let comparison = world.page.compare(try image(of: session), reached: world.page.maxOffset)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// A page that loads more when the user reaches its bottom: the first still waits 700 ms and
    /// tries again, finds new content, and goes on to the real end.
    @Test func waitsForLazyLoadingBeforeEnding() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.loadedLimit = 600
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .ended })
        #expect(world.blockedPosts > 0)
        #expect(world.loadedLimit == nil)
        let comparison = world.page.compare(try image(of: session), reached: world.page.maxOffset)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// Nothing is posted while the pointer is outside the area; moving it in starts, moving it
    /// out pauses after the step in progress.
    @Test func postsOnlyWhileThePointerIsOverTheArea() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock, pointer: Self.outside)
        let session = makeSession(world)
        try await start(session, world)
        let checks = world.permissionChecks
        try await clock.run(for: .seconds(1))
        #expect(world.posted.isEmpty)
        #expect(session.status == .autoPaused)
        #expect(session.status.text == "Paused. Move the pointer over the area to continue.")
        // While paused the grant (a TCC preflight) is never asked: the pointer is checked first.
        #expect(world.permissionChecks == checks)

        world.pointer = Self.inside
        try await clock.run(until: { world.posted.count >= 2 })
        #expect(session.status == .autoScrolling)

        world.pointer = Self.outside
        try await clock.run(for: .seconds(2))
        let count = world.posted.count
        try await clock.run(for: .seconds(2))
        #expect(world.posted.count == count)
        #expect(session.status == .autoPaused)
        #expect(session.phase == .capturing(.auto))
        await session.cancel()
        guard case .cancelled? = session.outcome else {
            Issue.record("not cancelled")
            return
        }
    }

    /// The app inverts synthetic deltas: the first step moves the page up, so the driver flips
    /// the direction once and stitches from where the user started down to the end.
    @Test func reversesOnceWhenTheFirstStepGoesBackwards() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock, offset: 600)
        world.inverted = true
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .ended })
        #expect(Array(world.posted.prefix(2)) == [50, 50])
        #expect(world.posted.dropFirst(2).allSatisfy { $0 < 0 })
        #expect(world.offset == world.page.maxOffset)
        // Header, page rows 600 to the end, footer.
        #expect(try image(of: session).height == 40 + (world.page.maxOffset - 600) + 330 + 30)
    }

    /// At the top of a page in an app that inverts synthetic deltas, the first step pushes
    /// against the top and nothing moves. The driver tries the other direction once, as a fresh
    /// first step, and stitches the whole page.
    @Test func triesTheOtherDirectionWhenTheFirstStepIsStill() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.inverted = true
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .ended })
        #expect(Array(world.posted.prefix(2)) == [50, 50])
        #expect(world.posted.dropFirst(2).allSatisfy { $0 < 0 })
        #expect(world.offset == world.page.maxOffset)
        let comparison = world.page.compare(try image(of: session), reached: world.page.maxOffset)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// A pane that does not scroll either way: the first step, the other direction, its 700 ms
    /// retry, then `Reached the end.` and the first frame alone.
    @Test func aPageThatNeverMovesEndsAfterTryingBothDirections() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.gain = 0
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.status == .autoReachedEnd })
        #expect(world.posted == [50, 50, -50, -50, -50, -50])
        try await clock.run(until: { session.phase == .ended })
        #expect(try image(of: session).height == world.page.height)
    }

    /// Every step jumps past the band: each loss scrolls back and halves the step (100, 50,
    /// then the 40 pt floor), and the third hands over. Then the user scrolls and Done saves.
    @Test func shrinksThenHandsOverAfterThreeLosses() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.gain = 5
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .capturing(.manual) })
        #expect(session.status == .autoHandedOver)
        #expect(session.status.text == "Auto-scroll lost its place. Scroll back up a little, or click Done.")
        #expect(world.posted == [50, 50, -50, -50, 50, -50, 40])

        // Manual from here: the user scrolls back into overlap with the first frame.
        world.scroll(to: 200)
        try await eventually { session.status == .manualCapturing }
        try await clock.run(for: .seconds(1))
        #expect(world.posted.count == 7)
        await session.done()
        let comparison = world.page.compare(try image(of: session), reached: 200)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// A step of four events (the first step of a 400 pt area is 200 pt): the pointer leaves the
    /// area after the second, as it might onto the panel inside the area. The other two are never
    /// posted, the part that went out settles and is stitched, and the driver pauses.
    @Test func aBurstStopsWhenThePointerLeavesMidStep() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let area = CGRect(x: 100, y: 100, width: 80, height: 400)
        world.afterPost = { world in
            if world.posted.count == 2 { world.pointer = Self.outside }
        }
        let session = makeSession(world, area: area)
        try await start(session, world)
        try await clock.run(for: .seconds(2))
        #expect(world.posted == [50, 50])
        #expect(world.offset == 200)
        #expect(session.status == .autoPaused)
        // The 200 row move of the partial step is stitched.
        #expect(session.heightPixels == 600)
        try await clock.run(for: .seconds(2))
        #expect(world.posted.count == 2)
        await session.cancel()
    }

    /// The grant going mid-burst stops the burst too, and the next step hands over.
    @Test func aBurstStopsWhenTheGrantGoesMidStep() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.afterPost = { world in
            if world.posted.count == 2 { world.permitted = false }
        }
        let session = makeSession(world, area: CGRect(x: 100, y: 100, width: 80, height: 400))
        try await start(session, world)
        try await clock.run(until: { session.phase == .capturing(.manual) })
        #expect(world.posted == [50, 50])
        #expect(session.status == .autoHandedOver)
        await session.cancel()
    }

    /// The scroll-back after a lost step waits for the pointer like a step does: with the pointer
    /// moved away after the first post, nothing more is posted, and the back goes out once it
    /// returns, over just what went out.
    @Test func theScrollBackWaitsForThePointer() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.gain = 5
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { world.posted.count >= 1 })
        world.pointer = Self.outside
        try await clock.run(for: .seconds(2))
        // The rest of the step stays unposted; the part that went out loses the place, and its
        // scroll-back is owed.
        #expect(world.posted == [50])
        try await clock.run(for: .seconds(2))
        #expect(world.posted == [50])
        #expect(session.status == .autoPaused)

        world.pointer = Self.inside
        try await clock.run(until: { world.posted.count >= 2 })
        #expect(Array(world.posted.prefix(2)) == [50, -50])
        await session.cancel()
    }

    /// Done and Cancel stop the driver: nothing is posted afterwards.
    @Test func doneStopsPostingAndFinishesWithTheImage() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { world.posted.count >= 1 })
        await session.done()
        let count = world.posted.count
        try await clock.run(for: .seconds(2))
        #expect(world.posted.count == count)
        guard case .image? = session.outcome else {
            Issue.record("not an image")
            return
        }
    }

    @Test func cancelStopsPostingAndDiscards() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { world.posted.count >= 1 })
        await session.cancel()
        let count = world.posted.count
        try await clock.run(for: .seconds(2))
        #expect(world.posted.count == count)
        guard case .cancelled? = session.outcome else {
            Issue.record("not cancelled")
            return
        }
    }

    /// The grant is checked before every step: once it is gone, the driver hands over and posts
    /// nothing more.
    @Test func handsOverWhenTheGrantGoes() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { world.posted.count >= 2 })
        world.permitted = false
        try await clock.run(until: { session.phase == .capturing(.manual) })
        #expect(session.status == .autoHandedOver)
        let count = world.posted.count
        try await clock.run(for: .seconds(2))
        #expect(world.posted.count == count)
        await session.cancel()
    }

    /// At the cap the limit line shows for 0.4 s and the session finishes with exactly the
    /// limit's rows, posting nothing more.
    @Test func theCapEndsAutoScroll() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world, maxPixelHeight: 700)
        try await start(session, world)
        try await clock.run(until: { session.status == .heightLimit })
        #expect(session.phase == .capturing(.auto))
        let count = world.posted.count
        try await clock.run(until: { session.phase == .ended })
        #expect(world.posted.count == count)
        let stitched = try image(of: session)
        #expect(stitched.height == 700)
        #expect(world.page.compare(stitched, reached: world.offset).mismatched == 0)
    }
}
