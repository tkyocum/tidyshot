import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// Records what `URLCommandHandler` asked the app to do, in order.
final class URLTargetRecorder: URLCommandTarget {
    enum Call: Equatable {
        case area(CaptureIntent)
        case areaAt(ScreenRect, CaptureIntent)
        case window(CaptureIntent)
        case fullscreen(CaptureIntent)
        case previousArea(CaptureIntent)
        /// The handler always passes `fromURLCommand: true`, which the default lets the expectations check.
        case allInOne(CaptureIntent, ScreenRect?, fromURLCommand: Bool = true)
        case selfTimer(CaptureIntent)
        case scrolling(CaptureIntent, ScreenRect?)
        case restore
        case text
        case textAt(ScreenRect)
        case desktopIconsHidden(Bool)
        case toggleDesktopIcons
        case startRecording(CaptureIntent, ScreenRect?)
        case stopRecording(String?)
    }

    var captureRefusal: CaptureRefusal?
    private(set) var calls: [Call] = []

    func captureArea(intent: CaptureIntent) async { calls.append(.area(intent)) }
    func captureArea(at area: ScreenRect, intent: CaptureIntent) async { calls.append(.areaAt(area, intent)) }
    func captureWindow(intent: CaptureIntent) async { calls.append(.window(intent)) }
    func captureFullscreen(intent: CaptureIntent) async { calls.append(.fullscreen(intent)) }
    func capturePreviousArea(intent: CaptureIntent) async { calls.append(.previousArea(intent)) }
    func captureAllInOne(intent: CaptureIntent, preselect: ScreenRect?, fromURLCommand: Bool) async {
        calls.append(.allInOne(intent, preselect, fromURLCommand: fromURLCommand))
    }
    func captureSelfTimer(intent: CaptureIntent) async { calls.append(.selfTimer(intent)) }
    func captureScrolling(intent: CaptureIntent, preselect: ScreenRect?) async { calls.append(.scrolling(intent, preselect)) }
    func restoreClosedOverlay() async { calls.append(.restore) }
    func captureText() async { calls.append(.text) }
    func captureText(at area: ScreenRect) async { calls.append(.textAt(area)) }
    func setDesktopIconsHidden(_ hidden: Bool) async { calls.append(.desktopIconsHidden(hidden)) }
    func toggleDesktopIconsHidden() async { calls.append(.toggleDesktopIcons) }
    /// Appends and returns at once, as the real one does once its `Task` is under way.
    func startRecording(intent: CaptureIntent, preselect: ScreenRect?) { calls.append(.startRecording(intent, preselect)) }
    func stopRecordingCommand(sender: String?) { calls.append(.stopRecording(sender)) }
}

/// The notices a handler posted.
final class URLNoticeLog {
    var notices: [URLCommandNotice] = []
}

/// The queue, the gate, the busy rule, the errors and the routing to every capture function
/// (spec 2.9, URL scheme and URL security).
struct URLCommandHandlerTests {
    let settings: AppSettings
    let target = URLTargetRecorder()
    let log = URLNoticeLog()
    /// Display 1 is 1920 x 1080 at the origin; display 2 sits to its right, 1280 x 800, top-aligned.
    let screens = URLCommandHandler.Screens(
        displays: [URLCommandGeometry.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                   URLCommandGeometry.Display(id: 2, frame: CGRect(x: 1920, y: 0, width: 1280, height: 800))],
        pointerIndex: 0)
    let refusal = " captures without a selection. Allow it in Settings > General > URL commands."

    init() {
        let name = "URLCommandHandlerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
        // Tim's mode, so the intents below differ from the default `.upload`.
        settings.afterCaptureAction = .uploadOnly
    }

    /// The intent a URL without `action` from Raycast carries.
    var standard: CaptureIntent { CaptureIntent(action: .uploadOnly, sender: "Raycast") }

    func notice(_ body: String, from sender: String? = "Raycast") -> URLCommandNotice {
        URLCommandNotice(title: "TidyShot URL command", subtitle: sender.map { "From \($0)" }, body: body)
    }

    /// A handler that has started, unless `ready` is false.
    func makeHandler(ready: Bool = true) async -> URLCommandHandler {
        let screens = screens
        let log = log
        let handler = URLCommandHandler(settings: settings, target: target, screens: { screens },
                                        post: { log.notices.append($0) })
        if ready {
            await handler.ready()
        }
        return handler
    }

    func send(_ handler: URLCommandHandler, _ string: String, from sender: String? = "Raycast") async throws {
        await handler.handle(try #require(URL(string: string)), sender: sender)
    }

    @Test func everyCommandReachesItsCaptureFunction() async throws {
        settings.urlCommandsAllowSilent = true
        let handler = await makeHandler()
        for string in ["capture-area", "capture-area?x=100&y=100&width=200&height=50", "capture-window",
                       "capture-fullscreen", "capture-previous-area", "all-in-one",
                       "all-in-one?x=10&y=10&width=300&height=200&display=2", "self-timer", "capture-scrolling",
                       "scrolling-capture?x=0&y=0&width=400&height=600", "restore-recently-closed",
                       "capture-text", "capture-text?x=100&y=100&width=200&height=50&action=copy",
                       "hide-desktop-icons", "show-desktop-icons", "toggle-desktop-icons?action=copy"] {
            try await send(handler, "tidyshot://\(string)")
        }
        let small = ScreenRect(rect: CGRect(x: 100, y: 930, width: 200, height: 50), displayID: 1)
        let second = ScreenRect(rect: CGRect(x: 1930, y: 590, width: 300, height: 200), displayID: 2)
        let tall = ScreenRect(rect: CGRect(x: 0, y: 480, width: 400, height: 600), displayID: 1)
        #expect(target.calls == [.area(standard), .areaAt(small, standard), .window(standard), .fullscreen(standard),
                                 .previousArea(standard), .allInOne(standard, nil), .allInOne(standard, second),
                                 .selfTimer(standard), .scrolling(standard, nil), .scrolling(standard, tall), .restore,
                                 .text, .textAt(small), .desktopIconsHidden(true), .desktopIconsHidden(false),
                                 .toggleDesktopIcons])
        #expect(log.notices.isEmpty)
    }

    @Test func theActionTravelsAsTheIntent() async throws {
        let handler = await makeHandler()
        for action in ["copy", "save", "upload", "annotate"] {
            try await send(handler, "tidyshot://capture-window?action=\(action)")
        }
        try await send(handler, "tidyshot://capture-window?action=pin", from: nil)
        #expect(target.calls == [
            .window(CaptureIntent(action: .uploadOnly, copyOnly: true, sender: "Raycast")),
            .window(CaptureIntent(action: .save, sender: "Raycast")),
            .window(CaptureIntent(action: .uploadOnly, sender: "Raycast")),
            .window(CaptureIntent(action: .uploadOnly, then: .annotate, sender: "Raycast")),
            .window(CaptureIntent(action: .uploadOnly, then: .pin)),
        ])
    }

    @Test func silentCommandsAreRefusedByDefaultNamingTheSender() async throws {
        let handler = await makeHandler()
        try await send(handler, "tidyshot://capture-fullscreen?action=copy", from: "Keyboard Maestro")
        try await send(handler, "tidyshot://capture-previous-area", from: nil)
        try await send(handler, "tidyshot://capture-area?x=0&y=0&width=10&height=10")
        try await send(handler, "tidyshot://capture-text?x=0&y=0&width=10&height=10")
        #expect(target.calls.isEmpty)
        #expect(log.notices == [
            notice("capture-fullscreen from Keyboard Maestro" + refusal, from: "Keyboard Maestro"),
            notice("capture-previous-area" + refusal, from: nil),
            notice("capture-area from Raycast" + refusal),
            notice("capture-text from Raycast" + refusal),
        ])
    }

    @Test func commandsThatWaitForTheUserRunWithSilentCapturesOff() async throws {
        let handler = await makeHandler()
        for string in ["capture-area?action=copy", "capture-window", "all-in-one?x=100&y=100&width=200&height=50",
                       "self-timer", "capture-scrolling?x=0&y=0&width=400&height=600", "restore-recently-closed",
                       "capture-text", "toggle-desktop-icons"] {
            try await send(handler, "tidyshot://\(string)")
        }
        let small = ScreenRect(rect: CGRect(x: 100, y: 930, width: 200, height: 50), displayID: 1)
        let tall = ScreenRect(rect: CGRect(x: 0, y: 480, width: 400, height: 600), displayID: 1)
        #expect(target.calls == [.area(CaptureIntent(action: .uploadOnly, copyOnly: true, sender: "Raycast")),
                                 .window(standard), .allInOne(standard, small), .selfTimer(standard),
                                 .scrolling(standard, tall), .restore, .text, .toggleDesktopIcons])
        #expect(log.notices.isEmpty)
    }

    /// Off means off: nothing is parsed, so a bad URL gets the same answer as a good one.
    @Test func withURLCommandsOffEveryURLIsRefusedAlike() async throws {
        settings.urlCommandsEnabled = false
        settings.urlCommandsAllowSilent = true
        let handler = await makeHandler()
        for string in ["capture-area", "restore-recently-closed", "capture-everything", "capture-area?action=print",
                       "hide-desktop-icons"] {
            try await send(handler, "tidyshot://\(string)")
        }
        #expect(target.calls.isEmpty)
        #expect(log.notices == Array(repeating: notice("URL commands are off. Turn them on in Settings > General."), count: 5))
    }

    @Test func errorsArePostedAndRunNothing() async throws {
        settings.urlCommandsAllowSilent = true
        let handler = await makeHandler()
        for string in ["capture-everything", "capture-area?x=1&y=2", "all-in-one?x=0&y=0&width=10&height=10&display=3",
                       "capture-scrolling?x=5000&y=0&width=10&height=10", "capture-area?action=copy&action=upload"] {
            try await send(handler, "tidyshot://\(string)")
        }
        #expect(target.calls.isEmpty)
        #expect(log.notices == [
            notice("Unknown command “capture-everything”."),
            notice("x, y, width and height must be given together, as numbers, with width and height above 0."),
            notice("There is no display 3."),
            notice("The area leaves less than a point on display 1."),
            notice("“action” is given more than once."),
        ])
    }

    /// Never queued behind a running capture, nor while the microphone or the camera prompt is open
    /// (each sets `captureRefusal`); a scrolling session is never advanced by a URL.
    @Test(arguments: [CaptureRefusal.captureRunning, .recordingStarting, .recordingRunning,
                      .permissionPrompt(.microphone), .permissionPrompt(.camera)])
    func captureCommandsAreDroppedWhileCapturesAreRefused(reason: CaptureRefusal) async throws {
        settings.urlCommandsAllowSilent = true
        target.captureRefusal = reason
        let handler = await makeHandler()
        for string in ["capture-area", "capture-fullscreen", "capture-scrolling", "all-in-one", "self-timer",
                       "capture-text", "capture-text?x=0&y=0&width=10&height=10"] {
            try await send(handler, "tidyshot://\(string)")
        }
        #expect(target.calls.isEmpty)
        #expect(log.notices.isEmpty)
        // Restore and the desktop-icon commands capture nothing, so they still run.
        for string in ["restore-recently-closed", "hide-desktop-icons", "show-desktop-icons", "toggle-desktop-icons"] {
            try await send(handler, "tidyshot://\(string)")
        }
        #expect(target.calls == [.restore, .desktopIconsHidden(true), .desktopIconsHidden(false), .toggleDesktopIcons])
    }

    /// The dropped command's log line says why (R2 design, Decided 2026-10-24, 9; R4 design): a
    /// burst's later capture command, a running capture, a count-in or a recording, or a prompt
    /// alone, named; nil when nothing drops it.
    @Test func theLogSaysWhyACaptureCommandWasDropped() {
        #expect(URLCommandHandler.dropReason(busy: false, refusal: nil) == nil)
        #expect(URLCommandHandler.dropReason(busy: false, refusal: .captureRunning) == "a capture is running")
        #expect(URLCommandHandler.dropReason(busy: false, refusal: .recordingStarting) == "a recording is starting")
        #expect(URLCommandHandler.dropReason(busy: false, refusal: .recordingRunning) == "a recording is running")
        #expect(URLCommandHandler.dropReason(busy: false, refusal: .permissionPrompt(.microphone))
                == "the microphone prompt is open")
        #expect(URLCommandHandler.dropReason(busy: false, refusal: .permissionPrompt(.camera)) == "the camera prompt is open")
        #expect(URLCommandHandler.dropReason(busy: true, refusal: nil) == "a queued capture command ran first")
        #expect(URLCommandHandler.dropReason(busy: true, refusal: .recordingRunning) == "a queued capture command ran first")
        #expect(URLCommandHandler.dropReason(busy: true, refusal: .permissionPrompt(.microphone))
                == "a queued capture command ran first")
        #expect(URLCommandHandler.dropReason(busy: true, refusal: .permissionPrompt(.camera))
                == "a queued capture command ran first")
    }

    @Test func urlsWaitUntilTheAppHasStartedThenRunInOrder() async throws {
        let handler = await makeHandler(ready: false)
        try await send(handler, "tidyshot://capture-window")
        try await send(handler, "tidyshot://restore-recently-closed")
        try await send(handler, "tidyshot://capture-fullscreen")
        #expect(target.calls.isEmpty)
        #expect(log.notices.isEmpty)
        await handler.ready()
        #expect(target.calls == [.window(standard), .restore])
        #expect(log.notices == [notice("capture-fullscreen from Raycast" + refusal)])
        await handler.ready()
        #expect(target.calls.count == 2)
    }

    /// A burst of capture URLs before launch runs only the first capture command; others still run.
    @Test func onlyTheFirstQueuedCaptureCommandRuns() async throws {
        settings.urlCommandsAllowSilent = true
        let handler = await makeHandler(ready: false)
        try await send(handler, "tidyshot://capture-area?action=bogus")
        try await send(handler, "tidyshot://capture-window")
        try await send(handler, "tidyshot://restore-recently-closed")
        try await send(handler, "tidyshot://capture-fullscreen")
        try await send(handler, "tidyshot://capture-scrolling?x=0&y=0&width=400&height=400")
        try await send(handler, "tidyshot://all-in-one")
        await handler.ready()
        // The refused URL does not count as the first capture command.
        #expect(target.calls == [.window(standard), .restore])
        #expect(log.notices == [notice("Unknown action “bogus”. Use upload, save, copy, annotate or pin.")])
        // Once started, URLs run as they come again.
        try await send(handler, "tidyshot://capture-fullscreen")
        #expect(target.calls == [.window(standard), .restore, .fullscreen(standard)])
    }

    /// `record-screen` reaches `startRecording` with the action's intent (R4 design, Parameters):
    /// none takes the setting, `upload` is upload-only in Tim's mode, `save` saves.
    @Test func recordScreenStartsWithTheActionsIntent() async throws {
        let handler = await makeHandler()
        for string in ["record-screen", "record-screen?action=upload", "record-screen?action=save"] {
            try await send(handler, "tidyshot://\(string)")
        }
        try await send(handler, "tidyshot://record-screen", from: nil)
        #expect(target.calls == [.startRecording(standard, nil), .startRecording(standard, nil),
                                 .startRecording(CaptureIntent(action: .save, sender: "Raycast"), nil),
                                 .startRecording(CaptureIntent(action: .uploadOnly), nil)])
        #expect(log.notices.isEmpty)
    }

    /// A rect is resolved as for every command and preselected; it needs only the first switch.
    @Test func recordScreenWithARectPassesTheResolvedRect() async throws {
        let handler = await makeHandler()
        try await send(handler, "tidyshot://record-screen?x=100&y=100&width=200&height=50")
        try await send(handler, "tidyshot://record-screen?x=10&y=10&width=300&height=200&display=2&action=save")
        // Clipped to display 1's right edge, still 32 pt wide.
        try await send(handler, "tidyshot://record-screen?x=1888&y=0&width=100&height=100")
        let small = ScreenRect(rect: CGRect(x: 100, y: 930, width: 200, height: 50), displayID: 1)
        let second = ScreenRect(rect: CGRect(x: 1930, y: 590, width: 300, height: 200), displayID: 2)
        let edge = ScreenRect(rect: CGRect(x: 1888, y: 980, width: 32, height: 100), displayID: 1)
        #expect(target.calls == [.startRecording(standard, small),
                                 .startRecording(CaptureIntent(action: .save, sender: "Raycast"), second),
                                 .startRecording(standard, edge)])
        #expect(log.notices.isEmpty)
    }

    /// A rect under 32 × 32 pt, after clipping to its display, could never record: refused before
    /// the target (R4 design, Parameters).
    @Test func recordScreenRefusesARectUnder32Points() async throws {
        let handler = await makeHandler()
        for string in ["record-screen?x=0&y=0&width=31&height=200", "record-screen?x=0&y=0&width=200&height=31",
                       "record-screen?x=1900&y=0&width=100&height=100", "record-screen?x=0&y=1060&width=100&height=100"] {
            try await send(handler, "tidyshot://\(string)")
        }
        try await send(handler, "tidyshot://record-screen?x=0&y=0&width=10&height=10", from: nil)
        #expect(target.calls.isEmpty)
        let message = "The area must be at least 32 by 32 points to record."
        #expect(log.notices == Array(repeating: notice(message), count: 4) + [notice(message, from: nil)])
    }

    /// `record-screen` is a capture: dropped while captures are refused, with no notice.
    @Test(arguments: [CaptureRefusal.captureRunning, .recordingStarting, .recordingRunning,
                      .permissionPrompt(.microphone), .permissionPrompt(.camera)])
    func recordScreenIsDroppedWhileCapturesAreRefused(reason: CaptureRefusal) async throws {
        target.captureRefusal = reason
        let handler = await makeHandler()
        try await send(handler, "tidyshot://record-screen")
        try await send(handler, "tidyshot://record-screen?x=0&y=0&width=200&height=200&action=save")
        #expect(target.calls.isEmpty)
        #expect(log.notices.isEmpty)
    }

    /// `stop-recording` captures nothing: it reaches the target under every refusal, with the
    /// cleaned sender, or nil for an unknown one.
    @Test(arguments: [nil, CaptureRefusal.captureRunning, .recordingStarting, .recordingRunning,
                      .permissionPrompt(.microphone), .permissionPrompt(.camera)])
    func stopRecordingReachesTheTargetUnderEveryRefusal(reason: CaptureRefusal?) async throws {
        target.captureRefusal = reason
        let handler = await makeHandler()
        try await send(handler, "tidyshot://stop-recording")
        try await send(handler, "tidyshot://stop-recording", from: nil)
        try await send(handler, "tidyshot://stop-recording", from: "\u{202E}")
        try await send(handler, "tidyshot://stop-recording?action=copy&x=1", from: "Key\u{0}board\u{202E} Maestro")
        #expect(target.calls == [.stopRecording("Raycast"), .stopRecording(nil), .stopRecording(nil),
                                 .stopRecording("Keyboard Maestro")])
        #expect(log.notices.isEmpty)
    }

    /// In a launch burst `record-screen` is the first capture command: a later capture command is
    /// dropped as today, and `stop-recording` is never dropped and runs after the start, which
    /// returned at once (R4 design, Names).
    @Test func aBurstStartsThenStopsAndDropsALaterCapture() async throws {
        let handler = await makeHandler(ready: false)
        try await send(handler, "tidyshot://record-screen")
        try await send(handler, "tidyshot://capture-area")
        try await send(handler, "tidyshot://stop-recording")
        try await send(handler, "tidyshot://record-screen?action=save")
        await handler.ready()
        #expect(target.calls == [.startRecording(standard, nil), .stopRecording("Raycast")])
        #expect(log.notices.isEmpty)
    }

    /// A capture command first in a burst drops a later `record-screen`, as any later capture.
    @Test func aBurstDropsRecordScreenAfterACapture() async throws {
        let handler = await makeHandler(ready: false)
        try await send(handler, "tidyshot://capture-window")
        try await send(handler, "tidyshot://record-screen")
        try await send(handler, "tidyshot://stop-recording")
        await handler.ready()
        #expect(target.calls == [.window(standard), .stopRecording("Raycast")])
    }

    @Test func theQueueHoldsAtMostEightURLs() async throws {
        #expect(URLCommandHandler.queueLimit == 8)
        let handler = await makeHandler(ready: false)
        for _ in 0..<10 {
            try await send(handler, "tidyshot://restore-recently-closed")
        }
        await handler.ready()
        #expect(target.calls.count == 8)
    }

    /// URL text reaches logs and notifications as data, never as a format string.
    @Test func formatSpecifiersInAURLAreJustText() async throws {
        let handler = await makeHandler()
        try await send(handler, "tidyshot://capture-area?action=%25@%25@%25s%25n", from: "%@ %n App")
        #expect(log.notices == [notice("Unknown action “%@%@%s%n”. Use upload, save, copy, annotate or pin.", from: "%@ %n App")])
    }

    @Test func aSenderNameIsCleanedAndAnEmptyOneIsUnknown() async throws {
        let handler = await makeHandler()
        try await send(handler, "tidyshot://capture-fullscreen", from: "\u{202E}")
        try await send(handler, "tidyshot://capture-fullscreen", from: "Key\u{0}board\u{202E} Maestro")
        #expect(log.notices == [notice("capture-fullscreen" + refusal, from: nil),
                                notice("capture-fullscreen from Keyboard Maestro" + refusal, from: "Keyboard Maestro")])
        #expect(URLCommandHandler.senderName("  ") == "  ")
        #expect(URLCommandHandler.senderName(nil) == nil)
    }

    /// phase-6b :153. `capture-area?display=7` with no rect opens the normal selection: the display counts only with
    /// a rect. `display=abc`'s notice is `URLCommandTests.theDisplayIsAWholeNumberFromOne`.
    @Test func aDisplayWithoutARectOpensTheNormalSelection() async throws {
        let handler = await makeHandler()

        try await send(handler, "tidyshot://capture-area?display=7")

        #expect(target.calls == [.area(standard)])
        #expect(log.notices.isEmpty)
    }

    /// phase-6b :161. With silent captures off, a `capture-fullscreen` the gate refuses, queued ahead of a
    /// `capture-window` before the launch finished, does not count as the first capture command: the window
    /// selection still opens.
    @Test func aGateRefusedCaptureDoesNotCountAsTheFirstQueuedOne() async throws {
        settings.urlCommandsAllowSilent = false
        let handler = await makeHandler(ready: false)
        try await send(handler, "tidyshot://capture-fullscreen")
        try await send(handler, "tidyshot://capture-window")

        await handler.ready()

        #expect(target.calls == [.window(standard)])
        #expect(log.notices == [notice("capture-fullscreen from Raycast" + refusal)])
    }
}
