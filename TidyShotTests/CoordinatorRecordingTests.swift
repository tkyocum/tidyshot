import AppKit
import Foundation
import Testing
@testable import TidyShot

/// The recording commands and prompts on a built coordinator (R4 design, `stop-recording` and
/// `record-screen` in each phase; R3 design, Asking from Settings; R1 design, Quit; harness design 3.4).
/// A recording runs on the world's `RecordingController` over `FakeRecordingDriver`; nothing records.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorRecordingTests {
    let world: CoordinatorWorld
    let display = RecordingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2)

    init() throws {
        world = try CoordinatorWorld()
    }

    func areaRequest() -> RecordingRequest {
        let id = UUID()
        let options = RecordingOptions(framesPerSecond: 30, retina: true, systemAudio: false, showsCursor: true)
        return RecordingRequest(id: id,
                                configuration: .make(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display),
                                                     options: options),
                                displayID: display.id,
                                outputURL: URL(filePath: "/private/tmp/CoordinatorRecordingTests/Recording/\(id.uuidString).mp4"),
                                muteLogURL: URL(filePath: "/private/tmp/CoordinatorRecordingTests/Mute/\(id.uuidString).json"),
                                lag: RecordingMute.defaultLag)
    }

    /// A recording on the coordinator's recorder, past its first frame.
    func beginRecording(on coordinator: AppCoordinator) async -> Task<RecordingOutcome, Never> {
        let request = areaRequest()
        let recorder = coordinator.recorder
        let chrome = world.chrome
        let run = Task { await recorder.run(request, chrome: chrome, onStarted: {}) }
        await world.recording.advance(by: .zero)
        world.driver.send(.recordingStarted)
        await world.recording.advance(by: .seconds(3))
        return run
    }

    /// A countdown on the coordinator's self-timer, shown.
    func beginCountdown(on coordinator: AppCoordinator) async throws -> Task<SelfTimerOutcome, Never> {
        let stage = FakeSelfTimerStage()
        let selfTimer = coordinator.selfTimer
        let countdown = Task { await selfTimer.run(seconds: 3, stage: stage, capture: {}) }
        try await eventually { stage.events.contains("show 3") }
        return countdown
    }

    /// 48 (harness design 3.4). R4 checklist, U1: `stop-recording` with nothing recording, or during a save, posts nothing,
    /// cancels no count-in, leaves the phase as it was, and stops no recorder. The recorder drops a stop with no run
    /// itself, so this does not tell the `.nothing` branch from a stray `recorder.stop()` (D24).
    @Test func stopRecordingWhileIdleOrSavingChangesNothing() {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()

        coordinator.stopRecordingCommand(sender: "Raycast")
        coordinator.recordingSavesInFlight = 1
        #expect(coordinator.recordingPhase == .saving)
        coordinator.stopRecordingCommand(sender: "Raycast")

        #expect(!coordinator.recordingStartCancelled)
        #expect(world.driver.stopCount == 0)
        #expect(world.notifier.calls.isEmpty)
        #expect(coordinator.recordingPhase == .saving)
    }

    /// 49 (harness design 3.4). R4 checklist, U1: during the count-in it is cancelled, and the flag holds the cancel for the
    /// settle delay and the content read.
    @Test func stopRecordingDuringACountInCancelsIt() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        coordinator.recordingCountIn = true
        let countdown = try await beginCountdown(on: coordinator)

        coordinator.stopRecordingCommand(sender: "Raycast")

        #expect(coordinator.recordingStartCancelled)
        // Gated with `eventually`: a countdown the command did not cancel sleeps on the world's clock,
        // which nothing moves, so awaiting it would hang.
        let ended = TaskWatch(countdown)
        try await eventually { ended.hasReturned }
        #expect(await countdown.value == .cancelled)
        #expect(world.notifier.calls.isEmpty)
    }

    /// 50 (harness design 3.4). R4 checklist, U1: during the recording it stops it, and with a second one during the stop
    /// wait (plan Gap 5 of R4) the recorder still stops once and nothing posts. The recorder drops a repeated stop
    /// itself, so this does not see the coordinator's `isEnding` check; its log line is Tim's (D24).
    @Test func stopRecordingDuringARecordingStopsItOnce() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let run = await beginRecording(on: coordinator)
        #expect(coordinator.recordingPhase == .recording)

        coordinator.stopRecordingCommand(sender: "Raycast")
        #expect(coordinator.recorder.isEnding)
        coordinator.stopRecordingCommand(sender: "Raycast")
        // Gated with `eventually`: a recording the command did not stop waits for its end for ever.
        let ended = TaskWatch(run)
        try await eventually { ended.hasReturned }

        #expect(!coordinator.recorder.isRunning)
        #expect(world.driver.stopCount == 1)
        #expect(world.notifier.calls.isEmpty)
    }

    /// 51 (harness design 3.4). R4 plan Gap 6: the start's cancel flag resets when a count-in begins, and only then.
    @Test func theStartCancelResetsOnlyWhenACountInBegins() {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()

        coordinator.recordingStartCancelled = true
        coordinator.recordingCountIn = true
        #expect(!coordinator.recordingStartCancelled)

        coordinator.recordingStartCancelled = true
        coordinator.recordingCountIn = true
        #expect(coordinator.recordingStartCancelled)
    }

    /// 52 (harness design 3.4). R4 checklist, Settings prompt section: the record shortcut or `stop-recording` in the settle
    /// delay records nothing and logs `not started, the count-in was cancelled`; a quit says nothing.
    @Test func recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled() {
        defer { world.removeAll() }
        #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: false, cancelled: false) == .start)
        #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: false, cancelled: true)
                == .stop(logsCancel: true))
        #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: true, cancelled: false)
                == .stop(logsCancel: false))
        #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: true, cancelled: true)
                == .stop(logsCancel: false))
        #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: false, cancelled: false)
                == .stop(logsCancel: false))
        #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: false, cancelled: true)
                == .stop(logsCancel: false))
        #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: true, cancelled: false)
                == .stop(logsCancel: false))
        #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: true, cancelled: true)
                == .stop(logsCancel: false))
    }

    /// 53 (harness design 3.4). R4 checklist, U1: `record-screen` during a count-in, a recording or a prompt starts nothing;
    /// a second one while the first is pending starts nothing; nor while quitting. (The successful
    /// start reaches ScreenCaptureKit and stays a hand check.)
    @Test func aURLStartIsRefusedInEveryPhaseThatDropsIt() async {
        defer { world.removeAll() }
        // A start that got past a refusal parks at its camera prompt (the bubble on, access not
        // determined), before the capture lock, so it never makes `tmp/Recording`, reads the content
        // or shows a selection; the last checks catch it. The parked prompt is never answered. Desktop
        // covers stay off whatever the defaults say.
        world.settings.recordingWebcamBubble = true
        world.settings.hideDesktopIconsWhileCapturing = false
        let cameras = HeldCameraDevices()
        world.cameras = cameras
        let coordinator = world.makeCoordinator()
        // `.standard` reads `AppSettings.shared`; this intent reads no settings.
        let intent = CaptureIntent(action: .save)

        coordinator.recordingCountIn = true
        coordinator.startRecording(intent: intent, preselect: nil)
        #expect(!coordinator.urlRecordingStartPending)
        coordinator.recordingCountIn = false

        coordinator.askingPermission = .camera
        coordinator.startRecording(intent: intent, preselect: nil)
        #expect(!coordinator.urlRecordingStartPending)
        coordinator.askingPermission = nil

        coordinator.urlRecordingStartPending = true
        coordinator.startRecording(intent: intent, preselect: nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(coordinator.urlRecordingStartPending)
        #expect(!coordinator.isCapturing)
        #expect(coordinator.askingPermission == nil)
        coordinator.urlRecordingStartPending = false

        let run = await beginRecording(on: coordinator)
        coordinator.startRecording(intent: intent, preselect: nil)
        #expect(!coordinator.urlRecordingStartPending)
        coordinator.recorder.stop()
        _ = await run.value

        await coordinator.finishRecordingForQuit()
        coordinator.startRecording(intent: intent, preselect: nil)
        #expect(!coordinator.urlRecordingStartPending)
        for _ in 0..<20 { await Task.yield() }
        // No start reached the camera prompt, and only the quit's wait posted.
        #expect(cameras.requestCount == 0)
        #expect(coordinator.askingPermission == nil)
        #expect(world.notifier.calls == [.waited(.seconds(1))])
    }

    /// 54 (harness design 3.4). R3 design, Asking from Settings: Settings asks while nothing else runs, with the prompt held
    /// as `askingPermission`; not while a capture holds the lock, nor while another prompt is open.
    @Test func aSettingsPromptAsksOnlyWhenNothingElseRuns() async throws {
        defer { world.removeAll() }
        let cameras = HeldCameraDevices()
        world.cameras = cameras
        let coordinator = world.makeCoordinator()

        let ask = Task { await coordinator.requestAccessFromSettings(.camera) }
        try await eventually { cameras.isAsking }
        #expect(coordinator.askingPermission == .camera)
        #expect(cameras.requestCount == 1)
        cameras.answer(true)
        await ask.value
        #expect(coordinator.askingPermission == nil)

        // The two asks that must not prompt run as their own tasks, gated with `eventually`: one that
        // prompted after all would wait for an answer that never comes, so the test fails in two
        // seconds instead of hanging.
        let gate = TestGate()
        let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
        try await eventually { gate.isWaiting }
        let duringLock = TaskWatch(Task { await coordinator.requestAccessFromSettings(.camera) })
        try await eventually { duringLock.hasReturned }
        #expect(cameras.requestCount == 1)
        #expect(coordinator.askingPermission == nil)
        gate.open()
        _ = await lock.value

        coordinator.askingPermission = .microphone
        let duringPrompt = TaskWatch(Task { await coordinator.requestAccessFromSettings(.camera) })
        try await eventually { duringPrompt.hasReturned }
        #expect(cameras.requestCount == 1)
        #expect(coordinator.askingPermission == .microphone)
    }

    /// 55 (harness design 3.4). R2 design, Decided 2026-10-24, 9: while a prompt is open every capture is refused, and the
    /// URL handler's reason names it; after the answer both clear.
    @Test func anOpenPromptRefusesCapturesUntilItIsAnswered() async throws {
        defer { world.removeAll() }
        let cameras = HeldCameraDevices()
        world.cameras = cameras
        let coordinator = world.makeCoordinator()

        let ask = Task { await coordinator.requestAccessFromSettings(.camera) }
        try await eventually { cameras.isAsking }
        #expect(coordinator.captureRefusal == .permissionPrompt(.camera))
        #expect(coordinator.capturesRefused)

        cameras.answer(false)
        await ask.value
        #expect(coordinator.captureRefusal == nil)
        #expect(!coordinator.capturesRefused)
    }

    /// 56 (harness design 3.4). R1 design, Quit: a quit cancels the count-in, stops the recording as Stop does (answering a
    /// Cancel's question with Save), and waits for the held notices once nothing records.
    @Test func aQuitCancelsTheCountInStopsTheRecordingAndWaitsForTheNotices() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let run = await beginRecording(on: coordinator)
        let countdown = try await beginCountdown(on: coordinator)
        // What the coordinator reads at the wait: the notices are waited for only once nothing records.
        var atWait: (phase: RecordingPhase, stops: Int)?
        let driver = world.driver
        world.notifier.onWait = { [weak coordinator] in
            if let coordinator { atWait = (coordinator.recordingPhase, driver.stopCount) }
        }

        let quit = Task { await coordinator.finishRecordingForQuit() }
        try await world.clock.run(until: { world.notifier.calls.contains(.waited(.seconds(1))) })
        await quit.value
        _ = await run.value

        #expect(coordinator.isQuitting)
        // Gated with `eventually`: a countdown the quit did not cancel sleeps on the world's clock past
        // what `run(until:)` moves it, so awaiting it would hang.
        let countdownEnded = TaskWatch(countdown)
        try await eventually { countdownEnded.hasReturned }
        #expect(await countdown.value == .cancelled)
        #expect(world.chrome.calls.contains("answer save"))
        #expect(world.driver.stopCount == 1)
        #expect(coordinator.recordingPhase == .idle)
        #expect(world.notifier.calls == [.waited(.seconds(1))])
        #expect(atWait?.phase == .idle)
        #expect(atWait?.stops == 1)
    }
}
