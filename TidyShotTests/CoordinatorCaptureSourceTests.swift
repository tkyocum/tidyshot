import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The capture entry points over the fake capture source and selection overlay (capture seams design 2.2, `CAPSRC`:
/// `world.source`, `world.selector`). Nothing reads ScreenCaptureKit, the screen or the pointer, and no overlay window
/// is built. Every entry gets an explicit intent (the default `.standard` reads `AppSettings.shared`), and a capture
/// that reaches a save is copy-only, so no save folder is asked for and no record is made. A test-built display has
/// no ScreenCaptureKit object, so a scrolling capture stops after the 100 pt check and the store, before the session.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorCaptureSourceTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
        // A card's screen is read from `NSScreen`.
        world.settings.showOverlay = false
    }

    nonisolated enum StoredArea: CaseIterable, Sendable {
        case none
        case offItsDisplay
    }

    /// phase-6a:209 (:254), full; phase-6a:214 (:260), full. With no stored area, or one that leaves under a point on
    /// its display (the line's own strip: x -0.4, 1.2 pt wide, its centre on display 1's left edge and 0.8 pt of it on
    /// the display), ⌃⇧6 posts its refusal under `No previous area` and captures nothing, asks no overlay and leaves
    /// the stored value as it was. The two resolutions are `PreviousAreaTests.noRectResolvesToNone` and
    /// `.aRectLeavingUnderOnePointOnItsDisplayIsOffScreen`; the stored value across a relaunch is
    /// `AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears`. The `defaults` commands and the quit
    /// and reopen are replaced by the setting.
    @Test(arguments: StoredArea.allCases)
    func capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing(stored: StoredArea) async throws {
        defer { world.removeAll() }
        let rect: StoredRect?
        let message: String
        switch stored {
        case .none:
            rect = nil
            message = "Capture an area first."
        case .offItsDisplay:
            rect = StoredRect(CGRect(x: -0.4, y: 100, width: 1.2, height: 200))
            message = "The previous area is not on a connected display."
        }
        world.settings.lastAreaRect = rect
        let coordinator = world.makeCoordinator()

        await coordinator.capturePreviousArea(intent: CaptureIntent(action: .save))

        #expect(world.notifier.calls == [.error(title: "No previous area", message: message)])
        #expect(world.source.contentReads == 1)
        #expect(world.source.captures.isEmpty)
        #expect(world.source.windowLookups.isEmpty)
        #expect(world.selector.selects.isEmpty)
        #expect(world.selector.allInOnes.isEmpty)
        #expect(world.clipboard.copies.isEmpty)
        #expect(coordinator.history.records.isEmpty)
        #expect(world.shutterCount == 0)
        #expect(world.cards.calls.isEmpty)
        #expect(world.logLines.isEmpty)
        #expect(world.settings.lastAreaRect == rect)
        #expect(!coordinator.isCapturing)
    }

    /// phase-6b:62 (:77), in part; phase-6b:104 (:122), in part; phase-6b:105 (:123), in part. ⌃⇧1 opens All-in-One
    /// on the stored area armed; `t 'all-in-one?x=0&y=0&width=500&height=400'` opens it on the URL's rect disarmed, and
    /// `t all-in-one` on the stored area disarmed; Escape in each leaves the stored area unchanged. Stays: the rect
    /// shown selected and adjustable, and none when its display is unplugged (`SelectionController.placePreselected`,
    /// `SELINT`'s); arming by a W change or the lock toggle, and Return typed in another app as the overlay appears
    /// (by hand). The restore rule is `SelectionAdjustTests.restoreKeepsARectOnItsDisplay` and
    /// `.restoreRefusesARectOffEveryDisplay`; the URL's routing and rect are
    /// `URLCommandHandlerTests.everyCommandReachesItsCaptureFunction` and
    /// `URLCommandGeometryTests.theOriginIsTheBottomLeftOfTheMainDisplay`; a disarmed rect's keys are
    /// `SelectionViewArmingTests`.
    @Test func allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing() async throws {
        defer { world.removeAll() }
        let previous = CGRect(x: 100, y: 120, width: 300, height: 200)
        // Where the URL's x 0, y 0, 500 x 400 lands on the 900 pt high display: y = 900 - 0 - 400.
        let urlRect = CGRect(x: 0, y: 500, width: 500, height: 400)
        let intent = CaptureIntent(action: .save)
        world.settings.lastAreaRect = StoredRect(previous)
        let coordinator = world.makeCoordinator()

        await coordinator.captureAllInOne(intent: intent)
        await coordinator.captureAllInOne(intent: intent, preselect: ScreenRect(rect: urlRect, displayID: 1),
                                          fromURLCommand: true)
        await coordinator.captureAllInOne(intent: intent, preselect: nil, fromURLCommand: true)

        #expect(world.selector.allInOnes == [
            FakeSelector.AllInOne(freeze: nil, preselect: previous, armed: true),
            FakeSelector.AllInOne(freeze: nil, preselect: urlRect, armed: false),
            FakeSelector.AllInOne(freeze: nil, preselect: previous, armed: false),
        ])
        #expect(world.settings.lastAreaRect == StoredRect(previous))
        #expect(world.selector.dismissCount == 0)
        #expect(world.source.contentReads == 3)
        #expect(world.source.captures.isEmpty)
        #expect(world.selector.selects.isEmpty)
        #expect(world.notifier.calls.isEmpty)
        #expect(!coordinator.isCapturing)
    }

    /// phase-6b:160 (:211), full; phase-6b:159 (:210), in part (the open selection). With one `capture-window` URL's
    /// selection held open, two more `capture-window` URLs and `capture-fullscreen`, `capture-area` and
    /// `capture-scrolling` are dropped: one overlay was asked, nothing more is read, captured or posted, and no
    /// scrolling session starts. Stays: while a self-timer counts (`STAGE`'s), and during a scrolling session before
    /// and after Start (`SCROLL`'s). The dropped line's text is
    /// `URLCommandHandlerTests.theLogSaysWhyACaptureCommandWasDropped` and the drop with the refusal faked is
    /// `.captureCommandsAreDroppedWhileCapturesAreRefused`. The selection is held.
    @Test func aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting() async throws {
        defer { world.removeAll() }
        defer { world.selector.answer(nil) }
        // `capture-fullscreen` captures without a selection, which the gate refuses unless this is on.
        world.settings.urlCommandsAllowSilent = true
        world.selector.holds = true
        let coordinator = world.makeCoordinator()
        let handler = URLCommandHandler(settings: world.settings, target: coordinator,
                                        screens: { URLCommandHandler.Screens(displays: [], pointerIndex: nil) },
                                        post: { notice in Issue.record("posted \(notice.body)") })
        await handler.ready()
        let window = try #require(URL(string: "tidyshot://capture-window"))
        let first = Task { await handler.handle(window, sender: "Terminal") }
        defer { first.cancel() }
        let firstWatch = TaskWatch(first)
        try await eventually { world.selector.isWaiting }

        let others = ["capture-window", "capture-window", "capture-fullscreen", "capture-area", "capture-scrolling"]
        var watches: [TaskWatch] = []
        for name in others {
            let url = try #require(URL(string: "tidyshot://\(name)"))
            watches.append(TaskWatch(Task { await handler.handle(url, sender: "Terminal") }))
        }
        try await eventually { watches.allSatisfy(\.hasReturned) }

        #expect(world.selector.selects == [FakeSelector.Select(mode: .window, freeze: nil, preselect: nil, armed: false)])
        #expect(world.selector.allInOnes.isEmpty)
        #expect(world.source.contentReads == 1)
        #expect(world.source.captures.isEmpty)
        #expect(world.notifier.calls.isEmpty)
        #expect(coordinator.isCapturing)
        #expect(!firstWatch.hasReturned)
        #expect(!coordinator.scrollCapture.isRunning)

        world.selector.answer(nil)
        try await eventually { firstWatch.hasReturned }
        #expect(!coordinator.isCapturing)
        #expect(world.source.captures.isEmpty)
        #expect(world.selector.selects.count == 1)
        #expect(world.selector.dismissCount == 0)
    }

    /// phase-7b:81 (:87), full. Capture Text takes its area without storing it, so ⌃⇧6 after it captures the earlier
    /// image area (300 x 200, on the clipboard), not the 40 x 20 text selection. The text recognizer runs for real on
    /// the fake's red image and finds nothing; its notice is not read here.
    @Test func capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea() async throws {
        defer { world.removeAll() }
        let earlier = CGRect(x: 100, y: 100, width: 300, height: 200)
        let textArea = CGRect(x: 600, y: 400, width: 40, height: 20)
        let options = CaptureOptions(showsCursor: false, windowShadow: false)
        world.settings.lastAreaRect = StoredRect(earlier)
        world.selector.selections = [.area(rect: textArea, display: FakeCaptureSource.display)]
        let coordinator = world.makeCoordinator()

        await coordinator.captureText()

        let textCapture = FakeCaptureSource.Capture(target: .area(rect: textArea, display: FakeCaptureSource.display),
                                                    options: options, excludedWindowIDs: [])
        #expect(world.settings.lastAreaRect == StoredRect(earlier))
        #expect(world.selector.selects == [FakeSelector.Select(mode: .area, freeze: nil, preselect: nil)])
        #expect(world.selector.frozenAsked == [1])
        #expect(world.selector.overlayLookups == 1)
        #expect(world.selector.dismissCount == 1)
        #expect(world.source.captures == [textCapture])

        await coordinator.capturePreviousArea(intent: CaptureIntent(action: .save, copyOnly: true))

        #expect(world.settings.lastAreaRect == StoredRect(earlier))
        #expect(world.source.contentReads == 2)
        #expect(world.source.captures == [
            textCapture,
            FakeCaptureSource.Capture(target: .area(rect: earlier, display: FakeCaptureSource.display),
                                      options: options, excludedWindowIDs: []),
        ])
        #expect(world.clipboard.pngs.count == 1)
        let png = try #require(world.clipboard.pngs.first)
        let decoded = try EditorPixels.decoded(png)
        #expect(decoded.image.width == 300)
        #expect(decoded.image.height == 200)
        #expect(decoded.scale == 1)
    }

    /// The harness, no checklist line: a content read that fails with Screen Recording granted is logged and posted
    /// under `Capture failed`, and the capture asks no overlay. The permission window's branch is not reached (the
    /// fake's grant is always on).
    @Test func aFailedContentReadIsLoggedAndPostedAndAsksNothingMore() async throws {
        defer { world.removeAll() }
        world.source.contentFailures = [FakeCaptureError()]
        let coordinator = world.makeCoordinator()
        await coordinator.captureArea(intent: CaptureIntent(action: .save))
        #expect(world.logLines == ["Shareable content failed: The fake source failed."])
        #expect(world.notifier.calls == [.error(title: "Capture failed",
                                                message: "Could not list screens and windows: The fake source failed.")])
        #expect(world.selector.selects.isEmpty)
        #expect(world.source.captures.isEmpty)
        #expect(world.source.contentReads == 1)
        #expect(!coordinator.isCapturing)
    }

    /// phase-5:78 (:78), in part; phase-6a:211 (:256), in part (a refused scrolling area does not replace the stored
    /// one). A 400 x 60 pt scrolling drag is refused with `Select an area at least 100 points tall.` under
    /// `Scrolling capture`, no session starts and the previous area stays; the next ⌃⇧5 gets an overlay again, and a
    /// URL command's 60 pt rect is refused the same way. Stays: the session on an accepted area (`SCROLL`'s), the drag
    /// in the overlay (by hand), and of phase-6a:211 a window click becoming the scrolling area (`SELINT`'s).
    @Test func aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks() async throws {
        defer { world.removeAll() }
        let stored = StoredRect(CGRect(x: 10, y: 20, width: 300, height: 200))
        let drag = CGRect(x: 100, y: 100, width: 400, height: 60)
        let intent = CaptureIntent(action: .save)
        world.settings.lastAreaRect = stored
        world.selector.selections = [.area(rect: drag, display: FakeCaptureSource.display),
                                     .area(rect: drag, display: FakeCaptureSource.display)]
        let coordinator = world.makeCoordinator()

        await coordinator.captureScrolling(intent: intent)
        await coordinator.captureScrolling(intent: intent)
        await coordinator.captureScrolling(intent: intent, preselect: ScreenRect(rect: drag, displayID: 1))

        let refusal = FakeNotifier.Call.error(title: "Scrolling capture",
                                              message: "Select an area at least 100 points tall.")
        #expect(world.notifier.calls == [refusal, refusal, refusal])
        let scrolling = FakeSelector.Select(mode: .scrolling, freeze: nil, preselect: nil)
        #expect(world.selector.selects == [scrolling, scrolling])
        #expect(world.selector.dismissCount == 3)
        #expect(world.source.contentReads == 3)
        #expect(world.settings.lastAreaRect == stored)
        #expect(world.source.captures.isEmpty)
        #expect(!coordinator.isCapturing)
        #expect(!coordinator.scrollCapture.isRunning)
    }

    /// phase-6a:211 (:256), in part; phase-6b:127 (:162), in part; phase-5:78 (:78), in part (an area exactly 100 pt
    /// tall is accepted). A window capture and a fullscreen capture leave the previous area; a `capture-area` URL rect
    /// replaces it once captured, and ⌃⇧6 captures it again; a URL rect whose capture fails does not; a 100 pt tall
    /// scrolling drag replaces it. Stays: the scrolling session on the accepted area, and a `capture-scrolling` rect
    /// stored only once the stitched image is saved (`SCROLL`'s); a window click becoming the scrolling area
    /// (`SELINT`'s); the drag in the overlay (by hand). The relaunch is
    /// `AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears`.
    @Test func windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt() async throws {
        defer { world.removeAll() }
        let stored = StoredRect(CGRect(x: 10, y: 20, width: 300, height: 200))
        let window = CaptureWindow(windowID: 7, frame: CGRect(x: 200, y: 150, width: 300, height: 200))
        let urlArea = ScreenRect(rect: CGRect(x: 50, y: 60, width: 200, height: 120), displayID: 1)
        let failedArea = ScreenRect(rect: CGRect(x: 400, y: 300, width: 200, height: 120), displayID: 1)
        let drag = CGRect(x: 100, y: 100, width: 400, height: 100)
        // Copy-only: no save folder, no record.
        let copy = CaptureIntent(action: .save, copyOnly: true)
        let options = CaptureOptions(showsCursor: false, windowShadow: false)
        world.settings.lastAreaRect = stored
        world.selector.selections = [.window(window)]
        let coordinator = world.makeCoordinator()

        // 1. Capture Window: the window, nothing excluded; the previous area stays.
        await coordinator.captureWindow(intent: copy)
        #expect(world.source.captures == [FakeCaptureSource.Capture(target: .window(window), options: options,
                                                                    excludedWindowIDs: [])])
        #expect(world.selector.selects == [FakeSelector.Select(mode: .window, freeze: nil, preselect: nil)])
        #expect(world.settings.lastAreaRect == stored)
        #expect(world.clipboard.pngs.count == 1)
        let windowPNG = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
        #expect(windowPNG.image.width == 300)
        #expect(windowPNG.image.height == 200)
        #expect(windowPNG.scale == 1)
        #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "300 × 200 px", subtitle: nil))
        #expect(world.shutterCount == 1)
        #expect(world.selector.dismissCount == 1)

        // 2. Capture Fullscreen: the display under the pointer; the previous area stays.
        await coordinator.captureFullscreen(intent: copy)
        #expect(world.source.captures.count == 2)
        #expect(world.source.captures.last == FakeCaptureSource.Capture(target: .display(FakeCaptureSource.display),
                                                                        options: options, excludedWindowIDs: []))
        #expect(world.settings.lastAreaRect == stored)
        #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "1440 × 900 px", subtitle: nil))
        #expect(world.shutterCount == 2)

        // 3. A `capture-area` URL rect: captured, then stored.
        await coordinator.captureArea(at: urlArea, intent: copy)
        #expect(world.source.captures.count == 3)
        #expect(world.source.captures.last == FakeCaptureSource.Capture(
            target: .area(rect: urlArea.rect, display: FakeCaptureSource.display), options: options,
            excludedWindowIDs: []))
        #expect(world.settings.lastAreaRect == StoredRect(urlArea.rect))
        #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil))

        // 4. ⌃⇧6 captures the URL rect again.
        await coordinator.capturePreviousArea(intent: copy)
        #expect(world.source.captures.count == 4)
        #expect(world.source.captures.last == FakeCaptureSource.Capture(
            target: .area(rect: urlArea.rect, display: FakeCaptureSource.display), options: options,
            excludedWindowIDs: []))
        #expect(world.settings.lastAreaRect == StoredRect(urlArea.rect))
        #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil))
        #expect(world.shutterCount == 4)

        // 5. A URL rect whose capture fails is not stored.
        world.source.captureFailure = FakeCaptureError()
        await coordinator.captureArea(at: failedArea, intent: copy)
        #expect(world.source.captures.count == 5)
        #expect(world.source.captures.last?.target == .area(rect: failedArea.rect, display: FakeCaptureSource.display))
        #expect(world.settings.lastAreaRect == StoredRect(urlArea.rect))
        #expect(world.logLines == ["Capture failed: The fake source failed."])
        #expect(world.notifier.calls.last == .error(title: "Capture failed", message: "The fake source failed."))
        #expect(world.shutterCount == 4)
        world.source.captureFailure = nil

        // 6. A scrolling drag exactly 100 pt tall passes the check and is stored before the session.
        world.selector.selections = [.area(rect: drag, display: FakeCaptureSource.display)]
        await coordinator.captureScrolling(intent: CaptureIntent(action: .save))
        #expect(world.settings.lastAreaRect == StoredRect(drag))
        #expect(world.selector.selects.last == FakeSelector.Select(mode: .scrolling, freeze: nil, preselect: nil))
        #expect(world.selector.dismissCount == 2)
        #expect(!coordinator.isCapturing)
        #expect(!coordinator.scrollCapture.isRunning)
        #expect(world.source.captures.count == 5)

        #expect(world.notifier.calls == [
            .notice(title: "Image copied", body: "300 × 200 px", subtitle: nil),
            .notice(title: "Image copied", body: "1440 × 900 px", subtitle: nil),
            .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil),
            .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil),
            .error(title: "Capture failed", message: "The fake source failed."),
        ])
    }
}
