import AppKit
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit
import Testing
@testable import TidyShot

/// One recording from the start to the outcome, on a fake driver and chrome and a clock the test
/// moves (design, While recording, Stopping and End rule). Nothing here needs Screen Recording.
@Suite(.timeLimit(.minutes(1)))
struct RecordingControllerTests {
    let world = RecordingTestWorld()
    let display = RecordingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2)
    let options = RecordingOptions(framesPerSecond: 30, retina: true, systemAudio: false, showsCursor: true)
    /// The recorded window's id.
    let windowID: CGWindowID = 77

    var areaRequest: RecordingRequest {
        request(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display))
    }

    var windowRequest: RecordingRequest {
        request(.window(id: windowID, frame: CGRect(x: 200, y: 150, width: 1000, height: 700), scale: 2))
    }

    func request(_ source: RecordingSource, gif: GIFSettings? = nil, microphoneID: String? = nil,
                 systemAudio: Bool = false, lag: TimeInterval = RecordingMute.defaultLag,
                 extras: RecordingExtrasStart? = nil) -> RecordingRequest {
        let id = UUID()
        var options = options
        options.format = gif == nil ? .mp4 : .gif
        options.microphoneID = microphoneID
        options.systemAudio = systemAudio
        return RecordingRequest(id: id, configuration: .make(source, options: options), displayID: display.id,
                                outputURL: URL(filePath: "/private/tmp/RecordingControllerTests/Recording/\(id.uuidString).mp4"),
                                muteLogURL: URL(filePath: "/private/tmp/RecordingControllerTests/Mute/\(id.uuidString).json"),
                                lag: lag, gif: gif, extras: extras)
    }

    /// Both R3 features on at the start, with a usable camera.
    let bothOn = RecordingExtrasStart(highlights: true, bubbleToggle: true,
                                      bubble: BubbleButtonState(isEnabled: true, disabledToolTip: nil))

    /// An area recording with the R3 features.
    var extrasRequest: RecordingRequest {
        request(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display), extras: bothOn)
    }

    /// Runs `request` on a new controller with `driver` and `chrome`, and lets the start run.
    func begin(_ request: RecordingRequest, driver: FakeRecordingDriver, chrome: FakeRecordingChrome,
               onStarted: @escaping () -> Void = {}) async -> (RecordingController, Task<RecordingOutcome, Never>) {
        let controller = RecordingController(environment: world.environment, makeDriver: { driver })
        let run = Task { await controller.run(request, chrome: chrome, onStarted: onStarted) }
        await world.advance(by: .zero)
        return (controller, run)
    }

    /// The log after the first frame.
    func entriesAfterFirstFrame() -> [String] {
        Array(world.log.entries.drop { $0 != "recordingStarted" }.dropFirst())
    }

    // MARK: The stop wait

    @Test func aFinishBeforeStopReturnsEndsTheWait() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let request = areaRequest
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        let outcome = await run.value
        let recording = try #require(outcome.kept)
        #expect(outcome.notice == nil)
        #expect(world.log.entries == ["show", "start", "recordingStarted", "activity begun", "stop", "recordingFinished",
                                      "stop returned", "inspect", "poster"])
        #expect(recording.id == request.id)
        #expect(recording.fileURL == request.outputURL)
        #expect(recording.startedAt == world.date)
        #expect(recording.pixelWidth == 1600)
        #expect(recording.pixelHeight == 1000)
        #expect(recording.duration == 10)
        #expect(recording.poster === world.poster)
        #expect(recording.displayID == display.id)
        controller.close()
    }

    @Test func aFinishAfterStopReturnsEndsTheWait() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .afterReturning
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "stop returned", "recordingFinished", "inspect", "poster"])
        controller.close()
    }

    @Test func withNoFinishTheWaitEndsAfterFifteenSeconds() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        await world.advance(by: .milliseconds(14_900))
        #expect(world.log.fileAccesses.isEmpty)
        #expect(controller.isRunning)
        await world.advance(by: .milliseconds(100))
        let outcome = await run.value
        // The timeout never deletes a playable file, and a Stop saves it silently.
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        #expect(world.log.fileAccesses == ["inspect", "poster"])
        #expect(!controller.isRunning)
        controller.close()
    }

    @Test func nothingTouchesTheFileBeforeTheWaitEnds() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressStop()
        await world.advance(by: .seconds(5))
        #expect(driver.stopCount == 1)
        #expect(world.log.fileAccesses.isEmpty)

        driver.send(.recordingFinished)
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "stop returned", "recordingFinished", "inspect", "poster"])
        controller.close()
    }

    @Test func aFinishAfterASleepLongerThanTheTimeoutKeepsTheFile() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        world.center.post(name: NSWorkspace.willSleepNotification, object: nil)
        await world.advance(by: .seconds(1))
        #expect(driver.stopCount == 1)
        // The Mac sleeps before the output has finished the file, which cannot be opened until then.
        world.facts = .unplayable
        await world.sleepTheMac(for: RecordingLimits.stopTimeout * 4)
        await world.advance(by: .seconds(1))
        #expect(world.log.fileAccesses.isEmpty)
        #expect(controller.isRunning)

        world.facts = .playable(seconds: 3)
        driver.send(.recordingFinished)
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "Your Mac went to sleep."))
        #expect(world.log.fileAccesses == ["inspect", "poster"])
        controller.close()
    }

    @Test func theTimeoutCountsOnlyTimeAwake() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        await world.advance(by: .seconds(5))
        await world.sleepTheMac(for: .seconds(60))
        await world.advance(by: .milliseconds(9_900))
        #expect(world.log.fileAccesses.isEmpty)
        #expect(controller.isRunning)
        await world.advance(by: .milliseconds(100))
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(world.log.fileAccesses == ["inspect", "poster"])
        controller.close()
    }

    @Test func theAppTimesTheStopWaitOnTheClockThatStopsWhileTheMacSleeps() async throws {
        let environment = RecordingEnvironment.live(cardWindowNumbers: { [] }, coverWindowNumbers: { _ in [] },
                                                    microphones: FakeMicrophoneDevices())
        let clock = try #require(environment.awakeClock as? SuspendingScrollClock)
        let before = clock.now
        try await clock.sleep(for: .milliseconds(10))
        #expect(clock.now - before >= .milliseconds(10))
    }

    /// The app's loss reason: an input missing from the list was disconnected; a listed one whose
    /// access is no longer authorized lost its access; otherwise the error says what happened.
    @Test func theAppSaysWhichWayTheMicrophoneWasLost() {
        let rode = MicrophoneDevice(uniqueID: Self.microphoneID, name: "RODE AI-1")
        let microphones = FakeMicrophoneDevices(devices: [rode], access: .authorized)
        let environment = RecordingEnvironment.live(cardWindowNumbers: { [] }, coverWindowNumbers: { _ in [] },
                                                    microphones: microphones)
        #expect(environment.microphoneLossReason(Self.microphoneID) == nil)

        for access in [MicrophoneAccess.denied, .restricted, .notDetermined] {
            microphones.currentAccess = access
            #expect(environment.microphoneLossReason(Self.microphoneID) == "Microphone access is off for TidyShot.")
        }
        microphones.devices = []
        #expect(environment.microphoneLossReason(Self.microphoneID) == "The microphone was disconnected.")
        microphones.currentAccess = .authorized
        #expect(environment.microphoneLossReason(Self.microphoneID) == "The microphone was disconnected.")
    }

    // MARK: GIF

    @Test func aKeptGIFRecordingCarriesTheRequestsGIFSettings() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let settings = GIFSettings(fps: 20, maxSide: 0)
        let (controller, run) = await begin(request(.display(display), gif: settings), driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.gif == settings)
        // The recorder's file is the MP4, saved or converted after it.
        #expect(recording.mediaKind == .video)
        #expect(recording.recoveryURL == recording.fileURL)
        controller.close()
    }

    @Test func aKeptMP4RecordingHasNoGIFSettings() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.gif == nil)
        #expect(recording.mediaKind == .video)
        controller.close()
    }

    @Test func theChromeShowsTheGIFBarForAGIFRequestAndThePlainBarOtherwise() async throws {
        for (gif, bar) in [(GIFSettings?.some(GIFSettings(fps: 15, maxSide: 1280)), RecordingPanelLayout.Bar.gif),
                           (nil, .plain)] {
            let driver = FakeRecordingDriver(log: world.log)
            let chrome = FakeRecordingChrome(log: world.log)
            let (controller, run) = await begin(request(.display(display), gif: gif), driver: driver, chrome: chrome)
            #expect(chrome.shownBars == [bar])
            chrome.pressStop()
            _ = await run.value
            controller.close()
        }
    }

    // MARK: Mute (design, Microphone, Mute)

    /// An area recording with system audio, so its bar has the mute button.
    func soundRequest(lag: TimeInterval = RecordingMute.defaultLag) -> RecordingRequest {
        request(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display), systemAudio: true, lag: lag)
    }

    func closed(_ start: TimeInterval, _ end: TimeInterval) -> MuteInterval {
        MuteInterval(start: start, end: end)
    }

    /// The bar follows the effective configuration: never a mute button for a GIF, nor for an MP4
    /// with no sound.
    @Test func theChromeShowsTheMuteBarOnlyForAnMP4WithSound() async throws {
        let area = RecordingSource.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display)
        let cases: [(RecordingRequest, RecordingPanelLayout.Bar)] = [
            (request(area, systemAudio: true), .mute),
            (request(area, microphoneID: Self.microphoneID), .mute),
            (request(area), .plain),
            (request(area, gif: GIFSettings(fps: 15, maxSide: 1280), microphoneID: Self.microphoneID, systemAudio: true), .gif),
        ]
        for (request, bar) in cases {
            let driver = FakeRecordingDriver(log: world.log)
            let chrome = FakeRecordingChrome(log: world.log)
            let (controller, run) = await begin(request, driver: driver, chrome: chrome)
            #expect(chrome.shownBars == [bar])
            chrome.pressStop()
            _ = await run.value
            controller.close()
        }
    }

    @Test func muteAtTwoAndUnmuteAtFiveGivesTwoToFive() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(soundRequest(), driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressMute()
        #expect(controller.isMuted)
        await world.advance(by: .seconds(3))
        chrome.pressMute()
        #expect(!controller.isMuted)
        await world.advance(by: .seconds(2))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.muteIntervals == [closed(2, 5)])
        #expect(chrome.mutedShown == [true, false])
        controller.close()
    }

    /// An interval still open at the end closes at the end's elapsed time.
    @Test func muteAtFourAndStopAtSevenGivesFourToSeven() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(soundRequest(), driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(4))
        chrome.pressMute()
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.muteIntervals == [closed(4, 7)])
        #expect(chrome.mutedShown == [true])
        controller.close()
    }

    /// The button is live from `show`, while the stream is still starting.
    @Test func aPressBeforeTheFirstFrameOpensAtZero() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.holdsStart = true
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(soundRequest(), driver: driver, chrome: chrome)
        await world.advance(by: .seconds(1))
        #expect(driver.isHoldingStart)
        chrome.pressMute()
        #expect(controller.isMuted)
        driver.releaseStart()
        await world.advance(by: .seconds(1))
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressMute()
        await world.advance(by: .seconds(1))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.muteIntervals == [closed(0, 3)])
        controller.close()
    }

    @Test func aPressOnceTheRecordingIsEndingIsIgnored() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(soundRequest(), driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressMute()
        await world.muteLogWrites.waitForWrites(1)
        await world.advance(by: .seconds(1))
        chrome.pressStop()
        await world.advance(by: .seconds(1))
        // In the stop wait.
        #expect(controller.isRunning)
        chrome.pressMute()
        controller.toggleMute()
        #expect(controller.isMuted)
        #expect(chrome.mutedShown == [true])

        driver.send(.recordingFinished)
        let recording = try #require(await run.value.kept)
        #expect(recording.muteIntervals == [closed(2, 3)])
        #expect(world.muteLogWrites.logs.map(\.sequence) == [1])
        // A press after the run is ignored too.
        controller.toggleMute()
        #expect(chrome.mutedShown == [true])
        controller.close()
    }

    @Test func theStateAndTheListResetAtEachRun() async throws {
        let drivers = [FakeRecordingDriver(log: world.log), FakeRecordingDriver(log: world.log)]
        var unused = drivers
        let controller = RecordingController(environment: world.environment, makeDriver: { unused.removeFirst() })
        let firstChrome = FakeRecordingChrome(log: world.log)
        let firstRun = Task { await controller.run(soundRequest(), chrome: firstChrome, onStarted: {}) }
        await world.advance(by: .zero)
        drivers[0].send(.recordingStarted)
        await world.advance(by: .seconds(1))
        firstChrome.pressMute()
        await world.advance(by: .seconds(1))
        firstChrome.pressStop()
        #expect(try #require(await firstRun.value.kept).muteIntervals == [closed(1, 2)])
        // Stopped while muted.
        #expect(controller.isMuted)
        controller.close()

        let chrome = FakeRecordingChrome(log: world.log)
        let request = soundRequest()
        let run = Task { await controller.run(request, chrome: chrome, onStarted: {}) }
        await world.advance(by: .zero)
        #expect(!controller.isMuted)
        drivers[1].send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressMute()
        await world.advance(by: .seconds(1))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.muteIntervals == [closed(3, 4)])
        // Its own writer, whose numbers start again.
        #expect(world.muteLogWritersMade.count == 2)
        #expect(world.muteLogWritersMade.last == request.muteLogURL)
        #expect(world.muteLogWrites.logs.last == MuteLog(intervals: [MuteInterval(start: 3, end: nil)], lag: request.lag,
                                                         sequence: 1))
        controller.close()
    }

    /// The writer is made at the first toggle (plan Gap 8) and gets every toggle's snapshot: the
    /// intervals so far, an open one as its start, the request's lag and a rising number.
    @Test func eachToggleYieldsTheIntervalsSoFarWithAHigherSequenceNumber() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let request = soundRequest(lag: 0.65)
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(1))
        #expect(world.muteLogWritersMade.isEmpty)
        for toggle in 1...3 {
            chrome.pressMute()
            await world.muteLogWrites.waitForWrites(toggle)
            await world.advance(by: .seconds(1))
        }
        #expect(world.muteLogWritersMade == [request.muteLogURL])
        #expect(world.muteLogWrites.logs == [
            MuteLog(intervals: [MuteInterval(start: 1, end: nil)], lag: 0.65, sequence: 1),
            MuteLog(intervals: [closed(1, 2)], lag: 0.65, sequence: 2),
            MuteLog(intervals: [closed(1, 2), MuteInterval(start: 3, end: nil)], lag: 0.65, sequence: 3),
        ])
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.muteIntervals == [closed(1, 2), closed(3, 4)])
        #expect(recording.lag == 0.65)
        controller.close()
    }

    @Test func theEndAwaitsTheWriterBeforeItTouchesTheFileOrReturns() async throws {
        world.muteLogWrites.holdWrites()
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(soundRequest(), driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressMute()
        await world.advance(by: .seconds(1))
        chrome.pressStop()
        await world.advance(by: .seconds(5))
        #expect(controller.isRunning)
        #expect(world.log.fileAccesses.isEmpty)
        #expect(world.muteLogWrites.logs.isEmpty)

        world.muteLogWrites.releaseWrites()
        let recording = try #require(await run.value.kept)
        #expect(world.muteLogWrites.logs.map(\.sequence) == [1])
        #expect(recording.muteIntervals == [closed(2, 3)])
        // The kept log is the save's: the mute ladder removes it.
        #expect(world.removals.isEmpty)
        controller.close()
    }

    nonisolated enum Discard: CaseIterable, Sendable {
        /// Under 5 s, so without a question.
        case cancel
        /// The end rule removes an unplayable file.
        case endRule
        /// An end before the first frame removes the file whatever it holds.
        case beforeTheFirstFrame
        /// The stream never started.
        case startFailure
    }

    /// Each place that discards the recording removes its mute log too, after the file in the same
    /// ordered removal, and only once the writer has finished, so no write lands after the removal.
    @Test(arguments: Discard.allCases)
    func aDiscardRemovesTheMuteLogOnceTheWriterHasFinished(_ discard: Discard) async throws {
        world.muteLogWrites.holdWrites()
        if discard == .endRule { world.facts = .unplayable }
        let driver = FakeRecordingDriver(log: world.log)
        driver.holdsStart = discard == .startFailure
        if discard == .startFailure { driver.startError = RecordingStartError.displayGone }
        let chrome = FakeRecordingChrome(log: world.log)
        let request = soundRequest()
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)
        if discard != .beforeTheFirstFrame && discard != .startFailure {
            driver.send(.recordingStarted)
            await world.advance(by: .seconds(2))
        }
        chrome.pressMute()
        await world.advance(by: .seconds(1))
        switch discard {
        case .cancel: chrome.pressCancel()
        case .endRule, .beforeTheFirstFrame: chrome.pressStop()
        case .startFailure: driver.releaseStart()
        }
        await world.advance(by: .seconds(1))
        #expect(controller.isRunning)
        #expect(world.removals.isEmpty)

        world.muteLogWrites.releaseWrites()
        let outcome = await run.value
        #expect(outcome.kept == nil)
        #expect(world.removals == [RecordingTestWorld.Removal(urls: [request.outputURL, request.muteLogURL],
                                                              writesLanded: 1)])
        controller.close()
    }

    /// A recording never muted has no log: no writer is made and only the file is removed.
    @Test func aRecordingNeverMutedHasNoLog() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let request = soundRequest()
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressCancel()

        #expect(await run.value.kept == nil)
        #expect(world.removedURLs == [request.outputURL])
        #expect(world.muteLogWritersMade.isEmpty)
        controller.close()
    }

    @Test func theKeptRecordingCarriesTheRequestsLag() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(soundRequest(lag: 0.6), driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        #expect(recording.lag == 0.6)
        #expect(recording.muteIntervals.isEmpty)
        controller.close()
    }

    // MARK: The start

    @Test func aStopDuringTheStartStopsTheNewStreamAndRemovesTheFile() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.holdsStart = true
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        #expect(driver.isHoldingStart)
        chrome.pressStop()
        #expect(driver.stopCount == 0)

        driver.releaseStart()
        let outcome = await run.value
        #expect(driver.stopCount == 1)
        #expect(outcome.kept == nil)
        #expect(outcome.notice == nil)
        // The file goes only after the wait.
        #expect(world.log.entries == ["show", "start", "stop", "recordingFinished", "stop returned", "remove"])
        #expect(world.activitiesBegun == 0)
        controller.close()
    }

    @Test func aCancelDuringTheStartStopsTheNewStreamWithoutAsking() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.holdsStart = true
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        chrome.pressCancel()
        driver.releaseStart()

        let outcome = await run.value
        #expect(driver.stopCount == 1)
        #expect(outcome.kept == nil)
        #expect(outcome.notice == nil)
        #expect(world.log.fileAccesses == ["remove"])
        #expect(!chrome.calls.contains { $0.hasPrefix("ask") })
        controller.close()
    }

    @Test func aStartThatThrowsFailsWithItsDescriptionAndNoFile() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.startError = RecordingStartError.windowGone
        let chrome = FakeRecordingChrome(log: world.log)
        var startedCalls = 0
        let (controller, run) = await begin(windowRequest, driver: driver, chrome: chrome) { startedCalls += 1 }

        let outcome = await run.value
        #expect(outcome.kept == nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording failed", body: "The window is no longer on screen."))
        #expect(driver.stopCount == 0)
        #expect(startedCalls == 0)
        #expect(world.log.fileAccesses == ["remove"])
        controller.close()
        #expect(world.activitiesBegun == 0)
        #expect(world.activitiesEnded == 0)
    }

    @Test func startErrorsSayWhatWentWrong() {
        #expect(RecordingStartError.cannotHideOwnWindows.localizedDescription == "TidyShot could not hide its own windows.")
        #expect(RecordingStartError.windowGone.localizedDescription == "The window is no longer on screen.")
        #expect(RecordingStartError.displayGone.localizedDescription == "The display is no longer connected.")
    }

    @Test func anOutputFailureBeforeTheFirstFrameFailsWithNoFile() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.outputFailed("The file could not be written."))

        // The output is done, so the stop needs no wait; the file is removed whatever it holds.
        let outcome = await run.value
        #expect(outcome.kept == nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording failed", body: "The file could not be written."))
        #expect(driver.stopCount == 1)
        #expect(world.log.fileAccesses == ["remove"])
        #expect(world.activitiesBegun == 0)
        controller.close()
    }

    @Test func theDriverGetsTheChromeTheCardsAndTheDisplaysCovers() async throws {
        world.coverWindows = [1: [90], 2: [91]]
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let request = areaRequest
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)

        // The chrome is on screen before the driver reads the shareable content.
        #expect(world.log.entries == ["show", "start"])
        #expect(driver.exclusions == RecordingExclusions(chromeWindows: [41, 42], cardWindows: [7], coverWindows: [90]))
        #expect(driver.configuration == request.configuration)
        #expect(driver.outputURL == request.outputURL)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    @Test func oneRunAtATime() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        #expect(controller.isRunning)

        let second = await controller.run(areaRequest, chrome: FakeRecordingChrome(log: world.log), onStarted: {})
        #expect(second.kept == nil)
        #expect(second.notice == nil)
        #expect(driver.startCount == 1)
        chrome.pressStop()
        _ = await run.value
        #expect(!controller.isRunning)
        controller.close()
    }

    // MARK: What the filter films (R3 design, Lookup misses; plan Gap 4)

    @Test func aRequestWithExtrasGivesTheDriverTheFilmedWindows() async throws {
        world.coverWindows = [1: [90]]
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)

        #expect(driver.exclusions == RecordingExclusions(chromeWindows: [41, 42], cardWindows: [7], coverWindows: [90],
                                                         filmedWindows: [51, 52]))
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    @Test func aRequestWithoutExtrasFilmsNoOwnWindowAndNeverSetsFilmed() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)

        #expect(driver.exclusions?.filmedWindows == [])
        driver.send(.recordingStarted)
        chrome.pressStop()
        _ = await run.value
        #expect(chrome.filmedShown.isEmpty)
        #expect(controller.extrasSummary.missed.isEmpty)
        controller.close()
    }

    @Test(arguments: [
        (Set<CGWindowID>([51, 52]), Set<FilmedFeature>([.bubble, .highlights])),
        (Set<CGWindowID>([51]), Set<FilmedFeature>([.bubble])),
        (Set<CGWindowID>([52]), Set<FilmedFeature>([.highlights])),
        (Set<CGWindowID>(), Set<FilmedFeature>()),
    ])
    func theDriversSetReachesTheChromeAsFeatures(found: Set<CGWindowID>, filmed: Set<FilmedFeature>) async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.filmed = found
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)

        #expect(chrome.filmedShown == [filmed])
        #expect(controller.extrasSummary.missed == Set(FilmedFeature.allCases).subtracting(filmed))
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    @Test func theFallbackFilmsEveryFilmedWindow() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)

        // A nil `filmed` returns all of the exclusions' filmed windows, as the fallback filter does.
        #expect(chrome.filmedShown == [[.bubble, .highlights]])
        #expect(controller.extrasSummary.missed.isEmpty)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    @Test func aFeatureWithNoWindowNumberIsMissed() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        chrome.filmedWindowNumbers = [.highlights: 52]
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)

        #expect(driver.exclusions?.filmedWindows == [52])
        #expect(chrome.filmedShown == [[.highlights]])
        #expect(controller.extrasSummary.missed == [.bubble])
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    @Test func aStartThatThrowsNeitherSetsFilmedNorMissesAnything() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.startError = RecordingStartError.displayGone
        driver.filmed = []
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)

        _ = await run.value
        #expect(chrome.filmedShown.isEmpty)
        #expect(controller.extrasSummary.missed.isEmpty)
        controller.close()
    }

    @Test func theSummaryResetsAtTheNextRun() async throws {
        let first = FakeRecordingDriver(log: world.log)
        first.filmed = []
        let second = FakeRecordingDriver(log: world.log)
        var drivers = [first, second]
        let controller = RecordingController(environment: world.environment, makeDriver: { drivers.removeFirst() })
        let chrome = FakeRecordingChrome(log: world.log)

        let run = Task { await controller.run(extrasRequest, chrome: chrome, onStarted: {}) }
        await world.advance(by: .zero)
        #expect(controller.extrasSummary.missed == [.bubble, .highlights])
        chrome.pressStop()
        _ = await run.value

        let again = Task { await controller.run(areaRequest, chrome: chrome, onStarted: {}) }
        await world.advance(by: .zero)
        #expect(controller.extrasSummary == RecordingExtrasSummary())
        chrome.pressStop()
        _ = await again.value
        controller.close()
    }

    // MARK: The bar's two buttons (R3 design, Bar)

    /// An area recording with `extras`.
    func extrasRequest(_ extras: RecordingExtrasStart, gif: GIFSettings? = nil) -> RecordingRequest {
        request(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display), gif: gif, extras: extras)
    }

    /// Both R3 toggles off, with a usable camera.
    let bothOff = RecordingExtrasStart(highlights: false, bubbleToggle: false,
                                       bubble: BubbleButtonState(isEnabled: true, disabledToolTip: nil))

    /// The chrome's highlights and bubble calls, in order.
    func toggleCalls(_ chrome: FakeRecordingChrome) -> [String] {
        chrome.calls.filter { $0.hasPrefix("highlights") || $0.hasPrefix("bubble") }
    }

    @Test func theTogglesFlipAndReachTheChrome() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        let on = BarToggle(isOn: true, isEnabled: true, disabledToolTip: nil)
        #expect(chrome.shownToggles.map(\.highlights) == [on])
        #expect(chrome.shownToggles.map(\.bubble) == [on])
        #expect(controller.highlightsClicks)
        #expect(controller.showsBubble)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))

        chrome.pressHighlights()
        #expect(!controller.highlightsClicks)
        chrome.pressBubble()
        #expect(!controller.showsBubble)
        controller.toggleHighlights()
        #expect(controller.highlightsClicks)
        controller.toggleBubble()
        #expect(controller.showsBubble)
        #expect(toggleCalls(chrome) == ["highlights on monitoring on", "highlights off monitoring off", "bubble off",
                                        "highlights on monitoring on", "bubble on"])
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    /// The bubble has been on screen since the count-in, so its press applies at once; the monitors
    /// wait for the first frame (plan Gap 5).
    @Test func aBubblePressBeforeTheFirstFrameAppliesAtOnceAndAHighlightsPressAtIt() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.holdsStart = true
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest(bothOff), driver: driver, chrome: chrome)
        #expect(driver.isHoldingStart)
        #expect(!controller.highlightsClicks)
        #expect(!controller.showsBubble)

        chrome.pressBubble()
        chrome.pressHighlights()
        #expect(toggleCalls(chrome) == ["bubble on", "highlights on monitoring off"])
        #expect(controller.extrasSummary.bubbleWanted)
        #expect(!controller.extrasSummary.highlightsUsed)
        driver.releaseStart()
        await world.advance(by: .seconds(1))
        #expect(toggleCalls(chrome) == ["bubble on", "highlights on monitoring off"])
        driver.send(.recordingStarted)
        #expect(toggleCalls(chrome) == ["bubble on", "highlights on monitoring off", "highlights on monitoring on"])
        #expect(controller.extrasSummary.highlightsUsed)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    @Test func aBarPressOnceTheRecordingIsEndingIsIgnored() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressStop()
        await world.advance(by: .seconds(1))
        // In the stop wait.
        #expect(controller.isRunning)
        chrome.pressHighlights()
        chrome.pressBubble()
        controller.toggleHighlights()
        controller.toggleBubble()
        #expect(controller.highlightsClicks)
        #expect(controller.showsBubble)

        driver.send(.recordingFinished)
        _ = await run.value
        // A press after the run is ignored too.
        controller.toggleHighlights()
        controller.toggleBubble()
        #expect(controller.highlightsClicks)
        #expect(controller.showsBubble)
        #expect(toggleCalls(chrome) == ["highlights on monitoring on"])
        controller.close()
    }

    @Test func bothResetAtTheNextRun() async throws {
        let drivers = [FakeRecordingDriver(log: world.log), FakeRecordingDriver(log: world.log),
                       FakeRecordingDriver(log: world.log)]
        var unused = drivers
        let controller = RecordingController(environment: world.environment, makeDriver: { unused.removeFirst() })
        let first = FakeRecordingChrome(log: world.log)
        let firstRun = Task { await controller.run(extrasRequest, chrome: first, onStarted: {}) }
        await world.advance(by: .zero)
        drivers[0].send(.recordingStarted)
        first.pressHighlights()
        first.pressBubble()
        #expect(!controller.highlightsClicks)
        #expect(!controller.showsBubble)
        first.pressStop()
        _ = await firstRun.value
        controller.close()

        let second = FakeRecordingChrome(log: world.log)
        let secondRun = Task { await controller.run(extrasRequest, chrome: second, onStarted: {}) }
        await world.advance(by: .zero)
        #expect(controller.highlightsClicks)
        #expect(controller.showsBubble)
        #expect(second.shownToggles.map(\.highlights.isOn) == [true])
        #expect(second.shownToggles.map(\.bubble.isOn) == [true])
        second.pressStop()
        _ = await secondRun.value
        controller.close()

        // A window recording has neither.
        let third = FakeRecordingChrome(log: world.log)
        let thirdRun = Task { await controller.run(areaRequest, chrome: third, onStarted: {}) }
        await world.advance(by: .zero)
        #expect(!controller.highlightsClicks)
        #expect(!controller.showsBubble)
        third.pressStop()
        _ = await thirdRun.value
        controller.close()
    }

    @Test func theBubbleStartsOffAndDisabledWithTheToggleOnAndNoCamera() async throws {
        let noCamera = BubbleButtonState(isEnabled: false, disabledToolTip: CameraChoice.noCameraText)
        let extras = RecordingExtrasStart(highlights: false, bubbleToggle: true, bubble: noCamera)
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest(extras), driver: driver, chrome: chrome)

        #expect(!controller.showsBubble)
        #expect(chrome.shownToggles.map(\.bubble) == [BarToggle(isOn: false, isEnabled: false,
                                                                disabledToolTip: CameraChoice.noCameraText)])
        driver.send(.recordingStarted)
        chrome.pressBubble()
        #expect(!controller.showsBubble)
        #expect(toggleCalls(chrome).isEmpty)
        // The toggle was on, so the camera's note may post.
        #expect(controller.extrasSummary.bubbleWanted)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    /// A feature the filter does not film is off, and its button does nothing.
    @Test func aMissedFeaturesPressIsIgnored() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.filmed = []
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        #expect(!controller.highlightsClicks)
        #expect(!controller.showsBubble)

        driver.send(.recordingStarted)
        chrome.pressHighlights()
        chrome.pressBubble()
        #expect(!controller.highlightsClicks)
        #expect(!controller.showsBubble)
        #expect(toggleCalls(chrome).isEmpty)
        #expect(controller.extrasSummary == RecordingExtrasSummary(bubbleWanted: true, highlightsAtStart: true,
                                                                   highlightsUsed: false, missed: [.bubble, .highlights]))
        chrome.pressStop()
        let recording = try #require(await run.value.kept)
        #expect(!recording.highlightedClicks)
        controller.close()
    }

    /// Only the missed feature's button stops working.
    @Test func aMissedBubbleLeavesTheHighlightsButton() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.filmed = [52]
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        chrome.pressBubble()
        chrome.pressHighlights()
        #expect(!controller.showsBubble)
        #expect(!controller.highlightsClicks)
        #expect(toggleCalls(chrome) == ["highlights on monitoring on", "highlights off monitoring off"])
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    /// The first frame can come while `start` is still awaited: highlights the filter turns out
    /// not to film reserve no GIF colours, though the monitors went on at the first frame.
    @Test func highlightsMissedAfterTheFirstFrameAreNotUsed() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.holdsStart = true
        driver.filmed = [51]
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        #expect(driver.isHoldingStart)
        driver.send(.recordingStarted)
        #expect(controller.extrasSummary.highlightsUsed)

        driver.releaseStart()
        await world.advance(by: .seconds(1))
        #expect(!controller.highlightsClicks)
        #expect(controller.extrasSummary == RecordingExtrasSummary(bubbleWanted: true, highlightsAtStart: true,
                                                                   highlightsUsed: false, missed: [.highlights]))
        chrome.pressStop()
        let recording = try #require(await run.value.kept)
        #expect(!recording.highlightedClicks)
        controller.close()
    }

    nonisolated enum HighlightsPresses: CaseIterable, Sendable {
        /// Off at the start, never pressed.
        case never
        /// On at the start.
        case onAtTheStart
        /// Off at the start, on after the first frame.
        case onMidRecording
        /// Off at the start, on and off again before the first frame.
        case onAndOffBeforeTheFirstFrame
    }

    /// `highlightsUsed` is whether rings could have been drawn: highlights on at some point from
    /// the first frame. The kept recording carries it to the GIF's palette.
    @Test(arguments: HighlightsPresses.allCases)
    func theSummaryAndTheKeptRecordingFollowThePresses(_ presses: HighlightsPresses) async throws {
        let extras = RecordingExtrasStart(highlights: presses == .onAtTheStart, bubbleToggle: false,
                                          bubble: BubbleButtonState(isEnabled: true, disabledToolTip: nil))
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest(extras), driver: driver, chrome: chrome)
        if presses == .onAndOffBeforeTheFirstFrame {
            chrome.pressHighlights()
            chrome.pressHighlights()
        }
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        if presses == .onMidRecording {
            chrome.pressHighlights()
        }
        await world.advance(by: .seconds(1))
        chrome.pressStop()

        let recording = try #require(await run.value.kept)
        let used = presses == .onAtTheStart || presses == .onMidRecording
        #expect(controller.extrasSummary.highlightsAtStart == (presses == .onAtTheStart))
        #expect(controller.extrasSummary.highlightsUsed == used)
        #expect(recording.highlightedClicks == used)
        #expect(!controller.extrasSummary.bubbleWanted)
        controller.close()
    }

    /// A bubble press on marks it wanted, for the camera's note, even if it goes off again.
    @Test func aBubblePressOnMarksTheBubbleWanted() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest(bothOff), driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        #expect(!controller.extrasSummary.bubbleWanted)
        chrome.pressBubble()
        chrome.pressBubble()
        #expect(controller.extrasSummary.bubbleWanted)
        #expect(!controller.showsBubble)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    nonisolated enum BarExit: CaseIterable, Sendable {
        case stop, cancel, sleep, outputError, startFailure, stopBeforeTheFirstFrame
    }

    @Test(arguments: BarExit.allCases)
    func closeReachesTheChromeOnceOnEveryEnd(_ exit: BarExit) async throws {
        let driver = FakeRecordingDriver(log: world.log)
        if exit == .startFailure {
            driver.startError = RecordingStartError.displayGone
        }
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        if exit != .startFailure && exit != .stopBeforeTheFirstFrame {
            driver.send(.recordingStarted)
            await world.advance(by: .seconds(2))
        }
        switch exit {
        case .stop, .stopBeforeTheFirstFrame: chrome.pressStop()
        case .cancel: chrome.pressCancel()
        case .sleep: world.center.post(name: NSWorkspace.willSleepNotification, object: nil)
        case .outputError: driver.send(.outputFailed("The file could not be written."))
        case .startFailure: break
        }
        _ = await run.value
        #expect(!chrome.calls.contains("close"))
        controller.close()
        #expect(chrome.calls.filter { $0 == "close" }.count == 1)
    }

    /// Without extras the bar is R2's, and neither button does anything.
    @Test func aRequestWithoutExtrasShowsR2sBars() async throws {
        let area = RecordingSource.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display)
        let gif = GIFSettings(fps: 15, maxSide: 1280)
        let cases: [(RecordingRequest, RecordingPanelLayout.Bar)] = [
            (request(area), .plain),
            (request(area, systemAudio: true), .mute),
            (request(area, gif: gif), .gif),
            (extrasRequest, RecordingPanelLayout.Bar(showsTag: false, showsMute: false, showsOverlayButtons: true)),
            (request(area, systemAudio: true, extras: bothOn),
             RecordingPanelLayout.Bar(showsTag: false, showsMute: true, showsOverlayButtons: true)),
            (extrasRequest(bothOn, gif: gif), RecordingPanelLayout.Bar(showsTag: true, showsMute: false, showsOverlayButtons: true)),
        ]
        for (request, bar) in cases {
            let driver = FakeRecordingDriver(log: world.log)
            let chrome = FakeRecordingChrome(log: world.log)
            let (controller, run) = await begin(request, driver: driver, chrome: chrome)
            #expect(chrome.shownBars == [bar])
            if request.extras == nil {
                driver.send(.recordingStarted)
                chrome.pressHighlights()
                chrome.pressBubble()
                #expect(!controller.highlightsClicks)
                #expect(!controller.showsBubble)
                #expect(toggleCalls(chrome).isEmpty)
            }
            chrome.pressStop()
            _ = await run.value
            controller.close()
        }
    }

    /// The recording's clock for R3's log lines (plan Gap 7).
    @Test func elapsedTimeCountsFromTheFirstFrame() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        await world.advance(by: .seconds(2))
        #expect(controller.elapsedTime == 0)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        #expect(controller.elapsedTime == 3)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    /// The next recording's camera starts before its `run`, so a loss in its count-in reads 0, not
    /// the last recording's age.
    @Test func elapsedTimeIsZeroAfterClose() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(extrasRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        chrome.pressStop()
        _ = await run.value
        controller.close()
        await world.advance(by: .seconds(5))
        #expect(controller.elapsedTime == 0)
    }

    // MARK: One controller, two runs

    /// Runs a recording on `first` whose stop never returns, so its wait times out, then starts
    /// a second on `second` with the same controller, as the app reuses one, 3 s past its first
    /// frame. `first`'s stop is still held.
    func runAgainAfterAStopThatHangs(first: FakeRecordingDriver, second: FakeRecordingDriver,
                                     chrome: FakeRecordingChrome) async -> (RecordingController, Task<RecordingOutcome, Never>) {
        first.finishTiming = .never
        first.holdsStop = true
        var drivers = [first, second]
        let controller = RecordingController(environment: world.environment, makeDriver: { drivers.removeFirst() })
        let firstChrome = FakeRecordingChrome(log: world.log)
        let firstRun = Task { await controller.run(areaRequest, chrome: firstChrome, onStarted: {}) }
        await world.advance(by: .zero)
        first.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        firstChrome.pressStop()
        await world.advance(by: RecordingLimits.stopTimeout)
        _ = await firstRun.value
        controller.close()

        let run = Task { await controller.run(areaRequest, chrome: chrome, onStarted: {}) }
        await world.advance(by: .zero)
        second.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        return (controller, run)
    }

    @Test func aLateFinishFromTheLastRunDoesNotEndThisRunsWait() async throws {
        let first = FakeRecordingDriver(log: world.log)
        let second = FakeRecordingDriver(log: world.log)
        second.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await runAgainAfterAStopThatHangs(first: first, second: second, chrome: chrome)
        #expect(first.isHoldingStop)
        let accesses = world.log.fileAccesses.count
        chrome.pressStop()
        await world.advance(by: .seconds(1))
        #expect(second.stopCount == 1)
        // The first run's output finishes long after its wait timed out.
        first.send(.recordingFinished)
        await world.advance(by: .seconds(1))
        #expect(world.log.fileAccesses.count == accesses)
        #expect(controller.isRunning)

        second.send(.recordingFinished)
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        #expect(world.log.entries.suffix(3) == ["recordingFinished", "inspect", "poster"])
        first.releaseStop()
        controller.close()
    }

    @Test func aLateFinishFromTheLastRunDoesNotEndThisRecording() async throws {
        let first = FakeRecordingDriver(log: world.log)
        let second = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await runAgainAfterAStopThatHangs(first: first, second: second, chrome: chrome)
        first.send(.recordingFinished)
        first.send(.outputFailed("The file could not be written."))
        await world.advance(by: .seconds(1))
        #expect(controller.isRunning)
        #expect(second.stopCount == 0)
        #expect(!chrome.calls.contains("stop disabled"))

        chrome.pressStop()
        let outcome = await run.value
        // A Stop, saved silently.
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        first.releaseStop()
        controller.close()
    }

    @Test func aLateStopFromTheLastRunDoesNotEndThisRunsWait() async throws {
        let first = FakeRecordingDriver(log: world.log)
        let second = FakeRecordingDriver(log: world.log)
        // The finish comes first, then the stop holds.
        second.holdsStop = true
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await runAgainAfterAStopThatHangs(first: first, second: second, chrome: chrome)
        let accesses = world.log.fileAccesses.count
        chrome.pressStop()
        await world.advance(by: .seconds(1))
        #expect(second.isHoldingStop)
        // The first run's stop returns at last.
        first.releaseStop()
        await world.advance(by: .seconds(1))
        #expect(world.log.fileAccesses.count == accesses)
        #expect(controller.isRunning)

        second.releaseStop()
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(world.log.entries.suffix(3) == ["stop returned", "inspect", "poster"])
        controller.close()
    }

    // MARK: While recording

    @Test func elapsedStartsAtTheFirstFrameAndStartedAtIsThatMoment() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        var startedCalls = 0
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome) { startedCalls += 1 }
        await world.advance(by: .seconds(2))
        #expect(chrome.elapsedShown.isEmpty)
        #expect(startedCalls == 0)
        #expect(world.activitiesBegun == 0)

        let firstFrame = Date(timeIntervalSinceReferenceDate: 800_000_042)
        world.date = firstFrame
        driver.send(.recordingStarted)
        #expect(startedCalls == 1)
        #expect(world.activitiesBegun == 1)
        world.date = firstFrame.addingTimeInterval(60)
        await world.advance(by: .milliseconds(3_500))
        #expect(chrome.elapsedShown == [1, 2, 3])
        // A second start callback changes nothing.
        driver.send(.recordingStarted)
        #expect(startedCalls == 1)

        chrome.pressStop()
        let outcome = await run.value
        #expect(outcome.kept?.startedAt == firstFrame)
        controller.close()
    }

    @Test func inactiveAndActiveStreamsEndNothing() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        driver.send(.streamInactive)
        await world.advance(by: .seconds(2))
        driver.send(.streamActive)
        await world.advance(by: .seconds(2))
        #expect(driver.stopCount == 0)

        chrome.pressStop()
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        controller.close()
    }

    @Test func sleepEndsTheRecording() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        world.center.post(name: NSWorkspace.willSleepNotification, object: nil)

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "Your Mac went to sleep."))
        controller.close()
    }

    @Test func aUserSwitchEndsTheRecording() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        world.center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "Another user took over the screen."))
        controller.close()
    }

    @Test func aWindowNoLongerListedEndsTheRecordingAtTheNextTick() async throws {
        world.listedWindows = [windowID]
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(windowRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        world.listedWindows = []
        await world.advance(by: .milliseconds(900))
        #expect(driver.stopCount == 0)
        await world.advance(by: .milliseconds(100))
        #expect(driver.stopCount == 1)

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "The recorded window closed."))
        controller.close()
    }

    @Test func anAreaRecordingLooksUpNoWindow() async throws {
        world.listedWindows = []
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        #expect(driver.stopCount == 0)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    @Test func underOneGigabyteAtAFiveSecondTickEndsTheRecording() async throws {
        world.freeBytes = RecordingLimits.runningFreeBytes - 1
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let request = areaRequest
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(4))
        #expect(driver.stopCount == 0)
        #expect(world.freeSpaceURLs.isEmpty)
        await world.advance(by: .seconds(1))
        #expect(driver.stopCount == 1)
        // The free space of tmp/Recording.
        #expect(world.freeSpaceURLs == [request.outputURL.deletingLastPathComponent()])

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "Your disk is almost full."))
        controller.close()
    }

    @Test func enoughOrUnreadableFreeSpaceKeepsRecording() async throws {
        world.freeBytes = RecordingLimits.runningFreeBytes
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(5))
        world.freeBytes = nil
        await world.advance(by: .seconds(5))
        #expect(world.freeSpaceURLs.count == 2)
        #expect(driver.stopCount == 0)
        chrome.pressStop()
        _ = await run.value
        controller.close()
    }

    // MARK: Ending

    @Test func cancelUnderFiveSecondsRemovesTheFileWithoutAsking() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .milliseconds(4_900))
        chrome.pressCancel()

        let outcome = await run.value
        #expect(outcome.kept == nil)
        #expect(outcome.notice == nil)
        #expect(!chrome.calls.contains { $0.hasPrefix("ask") })
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "recordingFinished", "stop returned", "inspect", "remove"])
        controller.close()
    }

    @Test func cancelFromFiveSecondsAsksAfterTheWaitAndSaveKeepsTheFileAsStopDoes() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        chrome.discards = false
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(5))
        chrome.pressCancel()

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        #expect(chrome.calls.contains("ask 0:05"))
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "recordingFinished", "stop returned", "ask", "inspect", "poster"])
        controller.close()
    }

    @Test func cancelFromFiveSecondsWithDiscardRemovesTheFileAndPostsNothing() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        chrome.discards = true
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(5))
        chrome.pressCancel()

        let outcome = await run.value
        #expect(outcome.kept == nil)
        #expect(outcome.notice == nil)
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "recordingFinished", "stop returned", "ask", "inspect", "remove"])
        controller.close()
    }

    @Test func theFirstEndWins() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressStop()
        world.center.post(name: NSWorkspace.willSleepNotification, object: nil)
        world.center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        controller.cancel()
        await world.advance(by: .seconds(6))
        // A later finish ends the wait but not the recording.
        driver.send(.recordingFinished)

        let outcome = await run.value
        #expect(driver.stopCount == 1)
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        #expect(!chrome.calls.contains { $0.hasPrefix("ask") })
        controller.close()
    }

    @Test func stopIsDisabledOnceAnEndArrivesAndASecondStopDoesNothing() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        #expect(!chrome.calls.contains("stop disabled"))

        world.center.post(name: NSWorkspace.willSleepNotification, object: nil)
        await world.advance(by: .zero)
        #expect(chrome.calls.filter { $0 == "stop disabled" }.count == 1)
        chrome.pressStop()
        controller.stop()
        await world.advance(by: .zero)
        #expect(driver.stopCount == 1)

        driver.send(.recordingFinished)
        let outcome = await run.value
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "Your Mac went to sleep."))
        #expect(chrome.calls.filter { $0 == "stop disabled" }.count == 1)
        // After the run, Stop does nothing at all.
        controller.stop()
        #expect(driver.stopCount == 1)
        controller.close()
    }

    /// `isEnding` (plan Gap 5): false before Stop and while recording, true from Stop through the
    /// stop wait while `isRunning` still holds, and false once the run has returned.
    @Test func isEndingHoldsFromStopUntilTheRunReturns() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        #expect(!controller.isEnding)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        #expect(controller.isRunning)
        #expect(!controller.isEnding)

        controller.stop()
        #expect(controller.isEnding)
        await world.advance(by: .zero)
        #expect(controller.isRunning)
        #expect(controller.isEnding)

        driver.send(.recordingFinished)
        _ = await run.value
        #expect(!controller.isRunning)
        #expect(!controller.isEnding)
        controller.close()
    }

    @Test func aStreamErrorWaitsForTheOutputToFinish() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        driver.send(.streamStopped("The display was disconnected."))
        await world.advance(by: .seconds(1))
        #expect(driver.stopCount == 1)
        #expect(world.log.fileAccesses.isEmpty)

        driver.send(.recordingFinished)
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "The display was disconnected."))
        controller.close()
    }

    @Test func aStreamStopAfterAnotherEndStillWaitsForTheOutputToFinish() async throws {
        world.listedWindows = [windowID]
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(windowRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        world.listedWindows = []
        await world.advance(by: .seconds(1))
        #expect(driver.stopCount == 1)
        // The stream reports the lost window while the output is still finishing the file.
        driver.send(.streamStopped("The window is no longer available."))
        await world.advance(by: .seconds(1))
        #expect(world.log.fileAccesses.isEmpty)
        #expect(controller.isRunning)

        driver.send(.recordingFinished)
        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "The recorded window closed."))
        #expect(entriesAfterFirstFrame().suffix(3) == ["recordingFinished", "inspect", "poster"])
        controller.close()
    }

    // MARK: The microphone lost mid-recording (plan Gap 7)

    /// The ID the area recordings below record from.
    static let microphoneID = "AppleUSBAudioEngine:RODE:AI-1:1"

    nonisolated static let microphoneErrors: [RecordingStreamEvent] = [
        .outputFailed("The operation couldn’t be completed."),
        .streamStopped("The operation couldn’t be completed."),
    ]

    @Test(arguments: microphoneErrors)
    func anErrorWhileTheMicrophoneIsLostSaysSo(_ error: RecordingStreamEvent) async throws {
        world.microphoneLossReasons = [Self.microphoneID: "The microphone was disconnected."]
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let request = request(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display),
                              microphoneID: Self.microphoneID)
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        driver.send(error)

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "The microphone was disconnected."))
        #expect(world.microphoneLossQueries == [Self.microphoneID])
        controller.close()
    }

    @Test(arguments: microphoneErrors)
    func anErrorWithTheMicrophoneStillThereKeepsItsDescription(_ error: RecordingStreamEvent) async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let request = request(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display),
                              microphoneID: Self.microphoneID)
        let (controller, run) = await begin(request, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        driver.send(error)

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "The operation couldn’t be completed."))
        #expect(world.microphoneLossQueries == [Self.microphoneID])
        controller.close()
    }

    @Test(arguments: microphoneErrors)
    func anErrorWithNoMicrophoneAsksNothing(_ error: RecordingStreamEvent) async throws {
        world.microphoneLossReasons = [Self.microphoneID: "The microphone was disconnected."]
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        driver.send(error)

        let outcome = await run.value
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "The operation couldn’t be completed."))
        #expect(world.microphoneLossQueries.isEmpty)
        controller.close()
    }

    @Test func aFinishNobodyAskedForKeepsTheFileAsStopped() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        driver.send(.recordingFinished)

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording stopped", body: "The screen recording stream stopped."))
        // The stream is stopped all the same.
        #expect(driver.stopCount == 1)
        controller.close()
    }

    @Test func anUnplayableFileAfterAStopIsRemovedAsTooShort() async throws {
        world.facts = .unplayable
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(2))
        chrome.pressStop()

        let outcome = await run.value
        #expect(outcome.kept == nil)
        #expect(outcome.notice == RecordingNotice(title: "Recording failed", body: "The recording is too short."))
        #expect(world.log.fileAccesses == ["inspect", "remove"])
        controller.close()
    }

    // MARK: A quit

    @Test func aQuitStopsAsStopDoes() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(3))
        controller.quit()

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "recordingFinished", "stop returned", "inspect", "poster"])
        controller.close()
    }

    /// The real alert shows only in the run loop's default mode, which AppKit never enters while it
    /// holds a quit, so a quit that waited for the answer would never reply.
    @Test func aQuitAnswersACancelsWaitingQuestionWithSave() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        chrome.holdsAsk = true
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(5))
        chrome.pressCancel()
        await world.advance(by: .seconds(1))
        #expect(chrome.isAsking)

        controller.quit()
        await world.advance(by: .zero)
        try #require(!controller.isRunning)
        let outcome = await run.value
        // Save carries on as Stop.
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        #expect(!chrome.isAsking)
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "recordingFinished", "stop returned", "ask", "inspect",
                                             "poster"])
        controller.close()
    }

    @Test func aQuitDuringACancelsStopWaitSavesWithoutAsking() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        driver.finishTiming = .never
        let chrome = FakeRecordingChrome(log: world.log)
        chrome.holdsAsk = true
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(5))
        chrome.pressCancel()
        await world.advance(by: .seconds(1))
        controller.quit()
        // The Cancel came first, so the stream is not stopped again.
        #expect(driver.stopCount == 1)
        driver.send(.recordingFinished)
        await world.advance(by: .zero)
        try #require(!controller.isRunning)

        let outcome = await run.value
        #expect(outcome.kept != nil)
        #expect(outcome.notice == nil)
        #expect(!chrome.calls.contains { $0.hasPrefix("ask") })
        #expect(entriesAfterFirstFrame() == ["activity begun", "stop", "stop returned", "recordingFinished", "inspect", "poster"])
        controller.close()
    }

    // MARK: The activity and close

    @Test func theActivityBeginsAtTheFirstFrameAndEndsAtClose() async throws {
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(areaRequest, driver: driver, chrome: chrome)
        await world.advance(by: .seconds(1))
        #expect(world.activitiesBegun == 0)
        driver.send(.recordingStarted)
        #expect(world.activitiesBegun == 1)
        chrome.pressStop()
        _ = await run.value
        // Held until the lock is released, after the hand-off.
        #expect(world.activitiesEnded == 0)
        #expect(!chrome.calls.contains("close"))

        controller.close()
        #expect(world.activitiesEnded == 1)
        #expect(chrome.calls.last == "close")
        #expect(world.log.entries.suffix(2) == ["close", "activity ended"])
        // Closing again changes nothing.
        controller.close()
        #expect(world.activitiesEnded == 1)
    }

    nonisolated enum Exit: CaseIterable, Sendable {
        case stop, cancelUnderFiveSeconds, cancelWithSave, cancelWithDiscard, sleep, userSwitch, diskFull,
             windowClosed, outputError, streamError, stopTimeout
    }

    @Test(arguments: Exit.allCases)
    func theActivityStartsAndEndsOnEveryExit(_ exit: Exit) async throws {
        world.listedWindows = [windowID]
        let driver = FakeRecordingDriver(log: world.log)
        let chrome = FakeRecordingChrome(log: world.log)
        let (controller, run) = await begin(windowRequest, driver: driver, chrome: chrome)
        driver.send(.recordingStarted)
        await world.advance(by: .seconds(exit == .cancelUnderFiveSeconds ? 2 : 6))
        switch exit {
        case .stop: chrome.pressStop()
        case .cancelUnderFiveSeconds: chrome.pressCancel()
        case .cancelWithSave:
            chrome.discards = false
            chrome.pressCancel()
        case .cancelWithDiscard: chrome.pressCancel()
        case .sleep: world.center.post(name: NSWorkspace.willSleepNotification, object: nil)
        case .userSwitch: world.center.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        case .diskFull:
            world.freeBytes = 0
            await world.advance(by: .seconds(5))
        case .windowClosed:
            world.listedWindows = []
            await world.advance(by: .seconds(1))
        case .outputError: driver.send(.outputFailed("The file could not be written."))
        case .streamError: driver.send(.streamStopped("The stream stopped."))
        case .stopTimeout:
            driver.finishTiming = .never
            chrome.pressStop()
            await world.advance(by: RecordingLimits.stopTimeout)
        }
        _ = await run.value
        #expect(world.activitiesBegun == 1)
        controller.close()
        #expect(world.activitiesEnded == 1)
    }

    @Test func thePanelIsA172By44Bar() {
        #expect(RecordingPanelLayout.size(of: .plain) == CGSize(width: 172, height: 44))
    }

    // MARK: The real driver's configuration

    @Test func anAreaStreamTakesItsSizeSourceRectFrameRateCursorAndAudioFromTheConfiguration() {
        let configuration = RecordingConfiguration.make(
            .area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display),
            options: RecordingOptions(framesPerSecond: 60, retina: true, systemAudio: true, showsCursor: false))
        let stream = ScreenRecordingDriver.streamConfiguration(configuration)
        #expect(stream.width == 1600)
        #expect(stream.height == 1000)
        #expect(stream.sourceRect == CGRect(x: 100, y: 100, width: 800, height: 500))
        #expect(stream.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        #expect(!stream.showsCursor)
        #expect(stream.capturesAudio)
        #expect(stream.excludesCurrentProcessAudio)
        #expect(!stream.scalesToFit)
        #expect(stream.preservesAspectRatio)
    }

    @Test func aStreamWithAMicrophoneCapturesItFromThatDevice() {
        let withMicrophone = request(.display(display), microphoneID: Self.microphoneID)
        let stream = ScreenRecordingDriver.streamConfiguration(withMicrophone.configuration)
        #expect(stream.captureMicrophone)
        #expect(stream.microphoneCaptureDeviceID == Self.microphoneID)

        let without = ScreenRecordingDriver.streamConfiguration(request(.display(display)).configuration)
        #expect(!without.captureMicrophone)
        #expect(without.microphoneCaptureDeviceID == nil)
    }

    @Test func aWindowStreamIgnoresTheShadowAndScalesToFit() {
        let stream = ScreenRecordingDriver.streamConfiguration(windowRequest.configuration)
        #expect(stream.width == 2000)
        #expect(stream.height == 1400)
        #expect(stream.ignoreShadowsSingleWindow)
        #expect(stream.scalesToFit)
        #expect(stream.preservesAspectRatio)
        #expect(stream.minimumFrameInterval == CMTime(value: 1, timescale: 30))
        #expect(!stream.capturesAudio)
    }

    @Test func theOutputIsAnH264MP4AtTheRequestedURL() {
        let url = areaRequest.outputURL
        let output = ScreenRecordingDriver.outputConfiguration(url)
        #expect(output.outputURL == url)
        #expect(output.outputFileType == .mp4)
        #expect(output.videoCodecType == .h264)
    }
}
