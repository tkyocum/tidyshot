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
    /// itself, so the state does not tell the `.nothing` branch from a stray `recorder.stop()` (D24); the line does
    /// (`stopRecordingLogsWhatItDidInEachPhase`).
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
    /// itself, so the state does not see the coordinator's `isEnding` check (D24); its log line does
    /// (`stopRecordingLogsWhatItDidInEachPhase`).
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

        // The count-in ending keeps the flag: `record()` clears the count-in right before it reads the cancel.
        coordinator.recordingCountIn = false
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

    /// recording-r2 :364, in part. With microphone access undecided and another capture holding the lock (an area
    /// selection, a self-timer countdown, a scrolling capture), a record press shows no prompt and starts
    /// nothing, and the capture goes on. By hand: the press once the capture is done, which prompts and then
    /// makes the live `tmp/Recording`, and that nothing is logged.
    @Test func aRecordPressDuringACaptureWithAccessUndecidedShowsNoPrompt() async throws {
        defer { world.removeAll() }
        world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
        let microphones = FakeMicrophoneDevices(access: .notDetermined)
        world.microphones = microphones
        let coordinator = world.makeCoordinator()
        let gate = TestGate()
        let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
        try await eventually { gate.isWaiting }

        let press = TaskWatch(Task { await coordinator.recordFullscreen() })
        try await eventually { press.hasReturned }

        #expect(microphones.requestCount == 0)
        #expect(coordinator.askingPermission == nil)
        #expect(coordinator.isCapturing)
        #expect(coordinator.recordingPhase == .idle)
        #expect(world.notifier.calls.isEmpty)
        gate.open()
        _ = await lock.value
    }

    /// recording-r3 :155. A GIF start asks for the camera (the bubble applies to GIF) and never for the microphone,
    /// though one is set. A quit while the camera prompt is up ends the start before the capture lock.
    @Test func aGIFStartAsksForTheCameraAndNotTheMicrophone() async throws {
        defer { world.removeAll() }
        world.settings.recordingFormat = .gif
        world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
        world.settings.recordingWebcamBubble = true
        world.settings.hideDesktopIconsWhileCapturing = false
        let microphones = FakeMicrophoneDevices(access: .notDetermined)
        world.microphones = microphones
        let cameras = HeldCameraDevices()
        world.cameras = cameras
        let coordinator = world.makeCoordinator()

        let start = TaskWatch(Task { await coordinator.recordFullscreen() })
        try await eventually { cameras.isAsking }
        #expect(coordinator.askingPermission == .camera)
        #expect(microphones.requestCount == 0)

        // The quit makes the start give up once the prompt is answered: no lock, no `tmp/Recording`. It returns
        // while the prompt is up only because nothing records yet; gated, so a start that locked or counted in
        // first fails here instead of hanging, and the deferred answer frees the start either way (D31).
        do {
            defer { cameras.answer(false) }
            let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
            try await eventually { quit.hasReturned }
        }
        try await eventually { start.hasReturned }
        #expect(cameras.requestCount == 1)
        #expect(microphones.requestCount == 0)
        #expect(!coordinator.isCapturing)
        #expect(world.notifier.calls == [.waited(.seconds(1))])
    }

    /// recording-r2 :351, the held prompt's part (a B line, left unmarked, D15). With the microphone prompt up, a
    /// second record press asks nothing, every capture is refused for the prompt, and a quit before the answer
    /// starts nothing. The disabled menu items, the dropped URL command's log line and the recording that
    /// starts after the answer stay with the line's seams.
    @Test func aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing() async throws {
        defer { world.removeAll() }
        world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
        let microphones = HeldMicrophoneDevices()
        world.microphones = microphones
        let coordinator = world.makeCoordinator()

        let first = TaskWatch(Task { await coordinator.recordFullscreen() })
        try await eventually { microphones.isAsking }
        #expect(coordinator.askingPermission == .microphone)
        #expect(coordinator.capturesRefused)
        #expect(coordinator.captureRefusal == .permissionPrompt(.microphone))

        let second = TaskWatch(Task { await coordinator.recordScreen() })
        try await eventually { second.hasReturned }
        #expect(microphones.requestCount == 1)

        // Gated as the GIF test's quit is (D31).
        do {
            defer { microphones.answer(false) }
            let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
            try await eventually { quit.hasReturned }
        }
        try await eventually { first.hasReturned }
        #expect(!coordinator.isCapturing)
        #expect(coordinator.askingPermission == nil)
        #expect(world.notifier.calls == [.waited(.seconds(1))])
    }

    // MARK: The `Recording:` lines (small seams design, LOG)
    // The `Recording:` lines the coordinator writes, read from `world.recordingLines`, the environment's
    // `recordingLog`. Nothing here records; starts end at their prompt.

    /// coordinator-harness:27 (:27), full; recording-r4:347 (:422), full. `stop-recording`'s line in each phase: nothing
    /// to stop while idle, during a selection (the capture lock held, the phase still idle) and while a recording is
    /// saved; the count-in cancelled; the recording stopped; and a second one during the stop wait finds the recording
    /// ending (`recorder.isEnding`) and does nothing. The `did nothing` lines are the coordinator's own two branches,
    /// which the state alone cannot tell from the recorder's (D24). Nothing stays by hand.
    @Test func stopRecordingLogsWhatItDidInEachPhase() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()

        coordinator.stopRecordingCommand(sender: "Raycast")

        // The lock held as during Record Screen's area selection: the phase is still idle.
        let gate = TestGate()
        let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
        defer { lock.cancel() }
        try await eventually { gate.isWaiting }
        coordinator.stopRecordingCommand(sender: "Keyboard Maestro")
        #expect(coordinator.isCapturing)
        gate.open()
        let lockEnded = TaskWatch(lock)
        try await eventually { lockEnded.hasReturned }

        coordinator.recordingSavesInFlight = 1
        coordinator.stopRecordingCommand(sender: nil)
        coordinator.recordingSavesInFlight = 0

        coordinator.recordingCountIn = true
        let countdown = try await beginCountdown(on: coordinator)
        defer { countdown.cancel() }
        coordinator.stopRecordingCommand(sender: "Raycast")
        let ended = TaskWatch(countdown)
        try await eventually { ended.hasReturned }
        #expect(coordinator.recordingStartCancelled)
        coordinator.recordingCountIn = false

        let run = await beginRecording(on: coordinator)
        defer { run.cancel() }
        coordinator.stopRecordingCommand(sender: "Raycast")
        #expect(coordinator.recorder.isEnding)
        coordinator.stopRecordingCommand(sender: "Raycast")
        let runEnded = TaskWatch(run)
        try await eventually { runEnded.hasReturned }

        #expect(world.recordingLines == [
            "Recording: stop-recording from Raycast did nothing, no recording is running",
            "Recording: stop-recording from Keyboard Maestro did nothing, no recording is running",
            "Recording: stop-recording from an unknown app did nothing, no recording is running",
            "Recording: stop-recording from Raycast cancelled the count-in",
            "Recording: stop-recording from Raycast stopped the recording",
            "Recording: stop-recording from Raycast did nothing, no recording is running",
        ])
        #expect(world.driver.stopCount == 1)
        #expect(!coordinator.recorder.isRunning)
        #expect(world.notifier.calls.isEmpty)
        #expect(world.logLines.isEmpty)
    }

    /// recording-r3:156 (:161), full; recording-r3:419 (:457), in part (a start's lines: the order, each answer's text,
    /// the ignored press). With the microphone and the camera both undecided, a start asks for the microphone, then the
    /// camera, and logs each answer; a second Record press while the camera prompt is up does nothing and logs why. A
    /// quit while it is up ends the start once it is answered, before the capture lock, so nothing makes
    /// `tmp/Recording`. Stays, of :457: the prompts on screen (by hand, Tim's) and the URL handler's own
    /// `URL command from … dropped, the camera prompt is open` line (URLCommandHandler.swift:155, `NSLog`; `URLLOG`'s).
    @Test func aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp() async throws {
        defer { world.removeAll() }
        world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
        world.settings.recordingWebcamBubble = true
        world.settings.hideDesktopIconsWhileCapturing = false
        let microphones = HeldMicrophoneDevices()
        let cameras = HeldCameraDevices()
        world.microphones = microphones
        world.cameras = cameras
        let coordinator = world.makeCoordinator()

        let start = Task { await coordinator.recordFullscreen() }
        defer { start.cancel() }
        let started = TaskWatch(start)
        try await eventually { microphones.isAsking }
        #expect(cameras.requestCount == 0)
        microphones.answer(true)
        try await eventually { cameras.isAsking }
        #expect(coordinator.askingPermission == .camera)

        let second = TaskWatch(Task { await coordinator.recordScreen() })
        try await eventually { second.hasReturned }
        #expect(microphones.requestCount == 1)
        #expect(cameras.requestCount == 1)

        // Gated as the GIF test's quit is (D31): the deferred answer frees the start either way.
        do {
            defer { cameras.answer(false) }
            let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
            try await eventually { quit.hasReturned }
        }
        try await eventually { started.hasReturned }

        #expect(world.recordingLines == [
            "Recording: microphone access allowed at the prompt",
            "Recording: start ignored, the camera prompt is open",
            "Recording: camera access refused at the prompt",
        ])
        #expect(!coordinator.isCapturing)
        #expect(coordinator.askingPermission == nil)
        #expect(world.notifier.calls == [.waited(.seconds(1))])
        #expect(world.logLines.isEmpty)
    }

    /// recording-r3:162 (:167), in part; recording-r4:214 (:218), in part; recording-r3:419 (:457), in part (the Settings
    /// prompt's lines: both answers, and `deferred` with its reason). Settings' prompt logs its answer when it asks, and
    /// why it waits when it does not: a recording being saved (a GIF converting), a capture holding the lock, a
    /// recording running inside the lock as the app runs one, or another prompt open. Only the first two asks prompt.
    /// Stays: of :167, the microphone pick in Settings reaching the coordinator, and of :218, the `Show webcam bubble`
    /// toggle reaching it, each a view's call on `AppCoordinator.shared` (CaptureSettingsView.swift:222, :253), by
    /// hand (Tim's), no seam; :218's GIF conversion is set up as `.saving`. Of :457, as the start test says: the prompts
    /// on screen (by hand) and the handler's `dropped` line (`URLLOG`'s).
    @Test func aSettingsPromptLogsItsAnswerOrWhyItWaits() async throws {
        defer { world.removeAll() }
        let cameras = HeldCameraDevices()
        world.cameras = cameras
        let microphones = FakeMicrophoneDevices(access: .notDetermined)
        world.microphones = microphones
        let coordinator = world.makeCoordinator()
        // An ask that must not prompt runs as its own task, gated: one that prompted after all would wait for an
        // answer that never comes (or is a second entry, an issue), so the test fails in two seconds.
        func askWithoutAPrompt(_ prompt: PermissionPrompt) async throws {
            let ask = TaskWatch(Task { await coordinator.requestAccessFromSettings(prompt) })
            try await eventually { ask.hasReturned }
        }

        let refusedAsk = Task { await coordinator.requestAccessFromSettings(.camera) }
        defer { refusedAsk.cancel() }
        let refused = TaskWatch(refusedAsk)
        try await eventually { cameras.isAsking }
        #expect(coordinator.askingPermission == .camera)
        cameras.answer(false)
        try await eventually { refused.hasReturned }

        let allowedAsk = Task { await coordinator.requestAccessFromSettings(.camera) }
        defer { allowedAsk.cancel() }
        let allowed = TaskWatch(allowedAsk)
        try await eventually { cameras.isAsking }
        #expect(coordinator.askingPermission == .camera)
        cameras.answer(true)
        try await eventually { allowed.hasReturned }

        coordinator.recordingSavesInFlight = 1
        #expect(coordinator.recordingPhase == .saving)
        try await askWithoutAPrompt(.camera)
        coordinator.recordingSavesInFlight = 0

        // The lock held, as a selection holds it, and still held through the recording below, as the app holds it
        // for the whole of one.
        let gate = TestGate()
        let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
        defer { lock.cancel() }
        let lockEnded = TaskWatch(lock)
        try await eventually { gate.isWaiting }
        try await askWithoutAPrompt(.camera)

        let run = await beginRecording(on: coordinator)
        defer { run.cancel() }
        #expect(coordinator.recordingPhase == .recording)
        #expect(coordinator.isCapturing)
        try await askWithoutAPrompt(.microphone)
        try await askWithoutAPrompt(.camera)
        coordinator.recorder.stop()
        let runEnded = TaskWatch(run)
        try await eventually { runEnded.hasReturned }
        gate.open()
        try await eventually { lockEnded.hasReturned }

        coordinator.askingPermission = .microphone
        try await askWithoutAPrompt(.camera)
        coordinator.askingPermission = nil

        #expect(world.recordingLines == [
            "Recording: camera access refused at the Settings prompt",
            "Recording: camera access allowed at the Settings prompt",
            "Recording: camera prompt from Settings deferred, a recording is being saved",
            "Recording: camera prompt from Settings deferred, a capture is running",
            "Recording: microphone prompt from Settings deferred, a capture is running",
            "Recording: camera prompt from Settings deferred, a capture is running",
            "Recording: camera prompt from Settings deferred, the microphone prompt is open",
        ])
        #expect(cameras.requestCount == 2)
        #expect(microphones.requestCount == 0)
        #expect(coordinator.askingPermission == nil)
        #expect(world.logLines.isEmpty)
    }

    /// recording-r4:366 (:456), full; recording-r4:192 (:193), in part (the coordinator's text, which the line accepts).
    /// Two `record-screen` URLs back to back through the handler: the first starts and parks at the camera prompt,
    /// before the lock; the second comes before that start runs, finds `urlRecordingStartPending` and is logged;
    /// nothing posts. One sent once the app quits is logged too. Stays, of :193: the one selection on screen, the
    /// drawn UI, by hand (Tim's), no seam.
    @Test func aSecondURLStartBeforeTheFirstTakesTheLockIsLogged() async throws {
        defer { world.removeAll() }
        world.settings.recordingWebcamBubble = true
        world.settings.hideDesktopIconsWhileCapturing = false
        let cameras = HeldCameraDevices()
        world.cameras = cameras
        let coordinator = world.makeCoordinator()
        let handler = URLCommandHandler(settings: world.settings, target: coordinator,
                                        screens: { URLCommandHandler.Screens(displays: [], pointerIndex: nil) },
                                        post: { notice in Issue.record("The URL handler posted \(notice.body)") })
        await handler.ready()
        let url = try #require(URL(string: "tidyshot://record-screen"))

        // One task, so nothing runs between the two: a `record-screen` reaches `startRecording` with no
        // suspension, and the first one's start task runs only after both.
        let sends = Task {
            await handler.handle(url, sender: "Keyboard Maestro")
            await handler.handle(url, sender: "Keyboard Maestro")
        }
        defer { sends.cancel() }
        let sent = TaskWatch(sends)
        try await eventually { sent.hasReturned }
        try await eventually { cameras.isAsking }
        #expect(coordinator.urlRecordingStartPending)
        #expect(cameras.requestCount == 1)
        #expect(world.notifier.calls.isEmpty)

        // Gated as the GIF test's quit is (D31).
        do {
            defer { cameras.answer(false) }
            let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
            try await eventually { quit.hasReturned }
        }
        try await eventually { !coordinator.urlRecordingStartPending }
        coordinator.startRecording(intent: CaptureIntent(action: .save), preselect: nil)

        #expect(world.recordingLines == [
            "Recording: URL start ignored, a recording is starting",
            "Recording: camera access refused at the prompt",
            "Recording: URL start ignored, the app is quitting",
        ])
        #expect(cameras.requestCount == 1)
        #expect(!coordinator.isCapturing)
        #expect(world.notifier.calls == [.waited(.seconds(1))])
        #expect(world.logLines.isEmpty)
    }
}
