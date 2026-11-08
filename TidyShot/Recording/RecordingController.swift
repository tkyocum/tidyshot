import AppKit
import CoreGraphics
import Foundation

/// One recording to run: the id that names the file, the stream's configuration, the display it
/// is on, `tmp/Recording/<id>.mp4`, whose folder already exists, its mute log and lag, and for a
/// GIF recording the GIF settings read at the start (plan Gap 1).
struct RecordingRequest {
    let id: UUID
    let configuration: RecordingConfiguration
    let displayID: CGDirectDisplayID
    let outputURL: URL
    /// `tmp/Mute/<id>.json`, written from the first mute toggle (design, Mute log).
    let muteLogURL: URL
    /// How far the sound sits behind the recording's clock, read at the start (design, Lag).
    let lag: TimeInterval
    /// Nil for an MP4 recording. A kept file carries it to the save, which makes the GIF.
    var gif: GIFSettings? = nil
    /// The R3 features at the start; nil for a window recording, which has neither.
    var extras: RecordingExtrasStart? = nil
}

/// The R3 features at a recording's start: the two toggles, and the bubble button's state from the
/// camera's resolve.
nonisolated struct RecordingExtrasStart: Equatable, Sendable {
    var highlights: Bool
    var bubbleToggle: Bool
    var bubble: BubbleButtonState
}

/// What the notes after Stop need from a run (plan Gap 6): whether the bubble was wanted, whether
/// highlights were on at the start or at any point, and the features the filter could not film.
nonisolated struct RecordingExtrasSummary: Equatable, Sendable {
    var bubbleWanted = false
    var highlightsAtStart = false
    var highlightsUsed = false
    var missed: Set<FilmedFeature> = []
}

/// How a recording ended: a file to save, or nothing (the file is gone), each with the notice to
/// post, if any.
enum RecordingOutcome {
    case keep(Recording, notice: RecordingNotice?)
    case nothing(notice: RecordingNotice?)
}

/// What the controller needs from the world, so its tests run on a clock they move, a date they
/// set and a notification centre of their own, with no screen and no file.
struct RecordingEnvironment {
    /// The elapsed time and the ticks.
    var clock: any ScrollClock
    /// The stop wait's timeout. In the app it stops while the Mac sleeps, so a stop that spans a
    /// sleep is not timed out on wake for the time asleep.
    var awakeClock: any ScrollClock
    var now: () -> Date
    /// The free space of a folder; nil when it cannot be read.
    var freeBytes: (URL) -> Int64?
    /// Whether the window server still lists the window, on screen or not.
    var windowIsListed: (CGWindowID) -> Bool
    var cardWindowNumbers: () -> Set<CGWindowID>
    /// The desktop covers on a display.
    var coverWindowNumbers: (CGDirectDisplayID) -> Set<CGWindowID>
    var beginActivity: () -> any NSObjectProtocol
    var endActivity: (any NSObjectProtocol) -> Void
    var inspect: (URL) async -> VideoFacts
    var poster: (URL) async -> CGImage?
    /// Removes the files in the order given, each only once the one before it is gone.
    var removeFiles: ([URL]) -> Void
    /// Where sleep and the user switch are posted.
    var workspaceCenter: NotificationCenter
    /// For the recorded input's `uniqueID`, after a stream or output error: the `Recording stopped`
    /// body when the input is gone or access is off, or nil (plan Gap 7).
    var microphoneLossReason: (String) -> String?
    /// The recording's mute log writer for its log's URL, made at the first toggle (plan Gap 8).
    var makeMuteLogWriter: (URL) -> MuteLogWriter

    static func live(cardWindowNumbers: @escaping () -> Set<CGWindowID>,
                     coverWindowNumbers: @escaping (CGDirectDisplayID) -> Set<CGWindowID>,
                     microphones: any MicrophoneDevices) -> RecordingEnvironment {
        RecordingEnvironment(
            clock: SystemScrollClock(),
            awakeClock: SuspendingScrollClock(),
            now: { Date() },
            freeBytes: { RecordingLimits.freeBytes(at: $0) },
            windowIsListed: { id in
                let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
                return info.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == id }
            },
            cardWindowNumbers: cardWindowNumbers,
            coverWindowNumbers: coverWindowNumbers,
            beginActivity: {
                ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled],
                                                      reason: "Recording the screen")
            },
            endActivity: { ProcessInfo.processInfo.endActivity($0) },
            inspect: { await VideoValidation.inspect($0) },
            poster: { await PosterFrame.image(of: $0) },
            removeFiles: { Recording.removeFiles(at: $0) },
            workspaceCenter: NSWorkspace.shared.notificationCenter,
            microphoneLossReason: { id in
                if !microphones.list().contains(where: { $0.uniqueID == id }) {
                    return MicrophoneChoice.disconnectedText
                }
                return microphones.access() == .authorized ? nil : MicrophoneChoice.accessOffText
            },
            makeMuteLogWriter: { MuteLogWriter(url: $0) })
    }
}

/// Runs one recording (design, While recording, Stopping and End rule): the chrome, the stream,
/// the elapsed time, the window poll, the disk check, sleep and the user switch, the mute state and
/// its log, the stop wait and the end rule. The first end wins. The caller holds the capture lock around `run` and
/// `close`, and saves a kept file.
final class RecordingController {
    /// The reason when the output finishes the file without a stop.
    static let streamStoppedReason = "The screen recording stream stopped."

    /// What ended the recording, before the end rule.
    private enum EndCause: Equatable {
        /// The panel's Cancel: it discards under 5 s, and asks from 5 s.
        case cancel
        case end(RecordingEndKind)
    }

    private let environment: RecordingEnvironment
    private let makeDriver: () -> any RecordingStreamDriver
    /// From `run`'s call to its return.
    private(set) var isRunning = false
    /// While running, an end has come (Stop, Cancel or another end) and the stop wait runs: a
    /// later Stop does nothing (plan Gap 5).
    var isEnding: Bool { isRunning && cause != nil }
    /// Counts the runs. A driver's events, its stop's return and the timers carry their run's
    /// number, and anything from an earlier run is dropped: a stop that outlived its wait still
    /// holds that run's driver, whose late finish must not end the next run's wait.
    private var runNumber = 0

    private var chrome: (any RecordingChrome)?
    private var request: RecordingRequest?
    private var onStarted: () -> Void = {}
    /// The first end, and the elapsed time when it came.
    private var cause: EndCause?
    /// A quit has come: a Cancel's question is answered Save.
    private var quitting = false
    private var elapsedAtEnd: TimeInterval = 0
    /// Set at `recordingStarted`; nil before the first frame.
    private var firstFrame: ContinuousClock.Instant?
    private var startedAt: Date?
    /// The output finished or failed: it writes nothing more. With the driver's stop returned, it
    /// ends the stop wait, whether it came before the end or after.
    private var outputEnded = false
    /// The driver's stop has returned or thrown.
    private var stopReturned = false
    private var stopWaiter: CheckedContinuation<Bool, Never>?
    /// `run` waits here for the first end.
    private var endWaiter: CheckedContinuation<Void, Never>?
    private var ticking: Task<Void, Never>?
    private var activity: (any NSObjectProtocol)?
    private var observers: [any NSObjectProtocol] = []

    /// Whether the sound is muted now; the chrome shows it (design, Mute, State).
    private(set) var isMuted = false
    /// The muted stretches so far, on the clock `elapsed` reads; the last is open while muted.
    private var muteIntervals: [MuteInterval] = []
    /// The last toggle's number, so a log write never replaces a later one.
    private var muteSequence = 0
    /// Made at the first toggle, so a recording never muted has no log.
    private var muteLogWriter: MuteLogWriter?

    /// The R3 features' run, for the notes after Stop; reset at each run.
    private(set) var extrasSummary = RecordingExtrasSummary()
    /// Whether clicks are highlighted, and whether the bubble shows, now; the bar's two buttons show
    /// them (R3 design, Bar, State). Both false without R3's extras, and for a missed feature.
    private(set) var highlightsClicks = false
    private(set) var showsBubble = false

    init(environment: RecordingEnvironment, makeDriver: @escaping () -> any RecordingStreamDriver) {
        self.environment = environment
        self.makeDriver = makeDriver
    }

    /// Shows `chrome`, starts the stream and returns when the recording has ended, after the stop
    /// wait and the end rule. `onStarted` runs once, at the first frame. A second call while one
    /// runs returns `.nothing` at once. The chrome, the activity and the observers stay until
    /// `close()`.
    func run(_ request: RecordingRequest, chrome: any RecordingChrome, onStarted: @escaping () -> Void) async -> RecordingOutcome {
        guard !isRunning else { return .nothing(notice: nil) }
        isRunning = true
        defer { isRunning = false }
        runNumber += 1
        let run = runNumber
        reset(for: request, chrome: chrome, onStarted: onStarted)
        observeWorkspace()
        // The chrome is on screen before the driver reads the shareable content, so the
        // fallback exclusion can find it. The mute button is live from here.
        chrome.show(actions: RecordingBarActions(stop: { [weak self] in self?.stop() },
                                                 cancel: { [weak self] in self?.cancel() },
                                                 mute: { [weak self] in self?.toggleMute() },
                                                 highlights: { [weak self] in self?.toggleHighlights() },
                                                 bubble: { [weak self] in self?.toggleBubble() }),
                    bar: RecordingPanelLayout.bar(showsMute: request.configuration.showsMuteButton,
                                                  isGIF: request.gif != nil,
                                                  showsOverlayButtons: request.extras != nil),
                    highlights: BarToggle(isOn: highlightsClicks, isEnabled: true, disabledToolTip: nil),
                    bubble: BarToggle(isOn: showsBubble, isEnabled: request.extras?.bubble.isEnabled ?? false,
                                      disabledToolTip: request.extras?.bubble.disabledToolTip))
        // The bubble and the ring overlay are filmed only with R3's extras.
        let filmedNumbers = request.extras == nil ? [:] : chrome.filmedWindowNumbers
        let exclusions = RecordingExclusions(chromeWindows: chrome.windowNumbers,
                                             cardWindows: environment.cardWindowNumbers(),
                                             coverWindows: environment.coverWindowNumbers(request.displayID),
                                             filmedWindows: Set(filmedNumbers.values))
        let driver = makeDriver()
        do {
            let filmedWindows = try await driver.start(request.configuration, outputURL: request.outputURL,
                                                       exclusions: exclusions) { [weak self] event in
                guard let self, runNumber == run else { return }
                handle(event)
            }
            if request.extras != nil {
                noteFilmed(filmedWindows, numbers: filmedNumbers, chrome: chrome)
            }
        } catch {
            // Nothing is recording, so there is nothing to wait for. Later callbacks are ignored.
            RecordingLog.note("Recording: the stream did not start: \(error.localizedDescription)")
            end(.end(.failed(error.localizedDescription)))
            await finishMuteLog()
            discard(request)
            return .nothing(notice: RecordingEnd.startFailure(error.localizedDescription))
        }
        if cause == nil {
            await withCheckedContinuation { endWaiter = $0 }
        }
        return await finish(driver)
    }

    /// The panel's Stop, the shortcuts and the menu. A quit calls `quit()`.
    func stop() {
        end(.end(.stop))
    }

    /// The panel's Cancel.
    func cancel() {
        end(.cancel)
    }

    /// The panel's mute button (design, Mute, State). A press before the first frame opens its
    /// interval at 0; one once the recording is ending is ignored. Each toggle hands the intervals so
    /// far, with the lag and a rising number, to the recording's writer, which the first toggle
    /// makes, then shows the new state.
    func toggleMute() {
        guard isRunning, cause == nil, let request else { return }
        if isMuted, let last = muteIntervals.indices.last {
            muteIntervals[last].end = elapsed
        } else {
            muteIntervals.append(MuteInterval(start: elapsed, end: nil))
        }
        isMuted.toggle()
        muteSequence += 1
        let writer = muteLogWriter ?? environment.makeMuteLogWriter(request.muteLogURL)
        muteLogWriter = writer
        writer.yield(MuteLog(intervals: muteIntervals, lag: request.lag, sequence: muteSequence))
        chrome?.setMuted(isMuted)
    }

    /// The bar's highlights button (R3 design, Bar, Presses). A press before the first frame shows
    /// at once and installs the monitors at it; one once the recording is ending, or for a missed
    /// feature, is ignored.
    func toggleHighlights() {
        guard isRunning, cause == nil, request?.extras != nil, !extrasSummary.missed.contains(.highlights) else { return }
        highlightsClicks.toggle()
        let monitoring = highlightsClicks && firstFrame != nil
        if monitoring {
            extrasSummary.highlightsUsed = true
        }
        chrome?.setHighlights(highlightsClicks, monitoring: monitoring)
        RecordingLog.note("Recording: click highlights \(highlightsClicks ? "on" : "off") at \(RecordingClock.format(elapsed))")
    }

    /// The bar's bubble button. The bubble has been on screen since the count-in, so a press before
    /// the first frame applies at once. Ignored once the recording is ending, without a usable
    /// camera, or for a missed feature.
    func toggleBubble() {
        guard isRunning, cause == nil, let extras = request?.extras, extras.bubble.isEnabled,
              !extrasSummary.missed.contains(.bubble) else { return }
        showsBubble.toggle()
        if showsBubble {
            extrasSummary.bubbleWanted = true
        }
        chrome?.setBubble(showsBubble)
        RecordingLog.note("Recording: webcam bubble \(showsBubble ? "on" : "off") at \(RecordingClock.format(elapsed))")
    }

    /// A quit (design, Quit, log out and restart) ends the recording as Stop does, and never waits
    /// for a Cancel's question: when a Cancel came first, the answer is Save, which carries on as
    /// Stop, whether the alert waits to show or is still to come. The real alert shows only in the
    /// run loop's default mode, which AppKit does not enter while it holds the quit.
    func quit() {
        guard isRunning else { return }
        quitting = true
        chrome?.answerDiscardWithSave()
        stop()
    }

    /// Closes the chrome, ends the activity and stops observing sleep and the user switch. Call
    /// it once `run` has returned, where the capture lock is released. The clock goes back to 0,
    /// so the next recording's camera, which starts before its `run`, never reads this one's age.
    func close() {
        ticking?.cancel()
        ticking = nil
        firstFrame = nil
        chrome?.close()
        chrome = nil
        if let activity {
            environment.endActivity(activity)
        }
        activity = nil
        for observer in observers {
            environment.workspaceCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    // MARK: The recording

    private func reset(for request: RecordingRequest, chrome: any RecordingChrome, onStarted: @escaping () -> Void) {
        close()
        self.request = request
        self.chrome = chrome
        self.onStarted = onStarted
        cause = nil
        quitting = false
        elapsedAtEnd = 0
        firstFrame = nil
        startedAt = nil
        outputEnded = false
        stopReturned = false
        isMuted = false
        muteIntervals = []
        muteSequence = 0
        muteLogWriter = nil
        let extras = request.extras
        highlightsClicks = extras?.highlights ?? false
        showsBubble = extras.map { $0.bubbleToggle && $0.bubble.isEnabled } ?? false
        extrasSummary = RecordingExtrasSummary(bubbleWanted: extras?.bubbleToggle ?? false,
                                               highlightsAtStart: extras?.highlights ?? false)
    }

    /// Tells the chrome which features the filter films (R3 design, Lookup misses): a feature is
    /// filmed when its window number is among `windows`, and missed otherwise, a feature with no
    /// window number among them.
    private func noteFilmed(_ windows: Set<CGWindowID>, numbers: [FilmedFeature: CGWindowID],
                            chrome: any RecordingChrome) {
        let filmed = FilmedFeature.allCases.filter { numbers[$0].map(windows.contains) ?? false }
        for feature in FilmedFeature.allCases where !filmed.contains(feature) {
            RecordingLog.note("Recording: \(feature.rawValue) window not in shareable content, not filmed")
        }
        RecordingLog.note("Recording: filming \(filmed.count) own windows (\(filmed.map(\.rawValue).joined(separator: ", ")))")
        chrome.setFilmed(Set(filmed))
        extrasSummary.missed = Set(FilmedFeature.allCases).subtracting(filmed)
        if extrasSummary.missed.contains(.highlights) {
            // The first frame may have come first and installed the monitors, but no ring is
            // filmed, so a GIF reserves no colours for them.
            highlightsClicks = false
            extrasSummary.highlightsUsed = false
        }
        if extrasSummary.missed.contains(.bubble) {
            showsBubble = false
        }
    }

    private func observeWorkspace() {
        let center = environment.workspaceCenter
        let ends: [(Notification.Name, RecordingEndKind)] = [
            (NSWorkspace.willSleepNotification, .sleep),
            (NSWorkspace.sessionDidResignActiveNotification, .userSwitch),
        ]
        for (name, kind) in ends {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end(.end(kind)) }
            })
        }
    }

    private func handle(_ event: RecordingStreamEvent) {
        switch event {
        case .recordingStarted:
            guard isRunning, cause == nil, firstFrame == nil else { return }
            firstFrame = environment.clock.now
            startedAt = environment.now()
            activity = environment.beginActivity()
            startTicking()
            // The monitors exist only from the first frame.
            if request?.extras != nil, highlightsClicks, !extrasSummary.missed.contains(.highlights) {
                extrasSummary.highlightsUsed = true
                chrome?.setHighlights(true, monitoring: true)
            }
            onStarted()
        case .recordingFinished:
            outputEnded = true
            resumeStopWaiter()
            end(.end(.failed(Self.streamStoppedReason)))
        case .outputFailed(let description):
            outputEnded = true
            resumeStopWaiter()
            end(.end(.failed(failureReason(description))))
        case .streamStopped(let description):
            // It never ends the stop wait: the output may still be finishing the file, which
            // cannot be opened until the finish (290 ms after the stop, in the 5K probe). The
            // wait takes the output's finish or fail, or the timeout.
            end(.end(.failed(failureReason(description))))
        }
    }

    /// A stream or output error's reason: the error's description, unless the recorded input
    /// went or its access was turned off, which the error does not say.
    private func failureReason(_ description: String) -> String {
        guard cause == nil, let id = request?.configuration.microphoneDeviceID,
              let reason = environment.microphoneLossReason(id) else { return description }
        RecordingLog.note("Recording: the microphone \(id) is lost: \(reason)")
        return reason
    }

    /// The elapsed time, the window poll and, every 5 s, the disk check, on whole seconds from
    /// the first frame.
    private func startTicking() {
        guard let firstFrame else { return }
        let clock = environment.clock
        let diskCheckTicks = max(1, Int(RecordingLimits.diskCheckInterval / .seconds(1)))
        let run = runNumber
        ticking = Task { [weak self] in
            var ticks = 0
            while true {
                ticks += 1
                do {
                    try await clock.sleep(for: max(.zero, firstFrame + .seconds(ticks) - clock.now))
                } catch {
                    return
                }
                guard let self, runNumber == run else { return }
                tick(checksDisk: ticks % diskCheckTicks == 0)
            }
        }
    }

    private func tick(checksDisk: Bool) {
        guard isRunning, cause == nil, let request else { return }
        chrome?.update(elapsed: elapsed)
        // A window that is minimised, hidden or on another Space is still listed.
        if case .window(let windowID) = request.configuration.filter, !environment.windowIsListed(windowID) {
            end(.end(.windowClosed))
            return
        }
        if checksDisk,
           RecordingLimits.stopsRecording(freeBytes: environment.freeBytes(request.outputURL.deletingLastPathComponent())) {
            end(.end(.diskFull))
        }
    }

    /// Seconds since the first frame, 0 before it and after `close()`; R3's log lines and the
    /// camera's loss note read it too (plan Gap 7).
    var elapsed: TimeInterval {
        guard let firstFrame else { return 0 }
        return (environment.clock.now - firstFrame) / .seconds(1)
    }

    // MARK: Ending

    /// The first end wins; any later one is ignored. Stop and the mute button are disabled, an open
    /// muted stretch closes, and the stop wait's waiter is armed here, before `run` calls the
    /// driver's stop.
    private func end(_ cause: EndCause) {
        guard isRunning, self.cause == nil else { return }
        self.cause = cause
        elapsedAtEnd = elapsed
        if isMuted, let last = muteIntervals.indices.last {
            muteIntervals[last].end = elapsedAtEnd
        }
        ticking?.cancel()
        ticking = nil
        chrome?.setStopEnabled(false)
        endWaiter?.resume()
        endWaiter = nil
    }

    /// Stops the stream, waits, then applies the end rule. Nothing touches the file before the
    /// wait ends, nor the file or the mute log before the log's last write has landed. An end before
    /// the first frame removes the file whatever it holds. A removed file takes its log with it; a
    /// kept one carries its closed muted stretches and the lag to the save, whose mute step removes
    /// the log.
    private func finish(_ driver: any RecordingStreamDriver) async -> RecordingOutcome {
        guard let cause, let request else { return .nothing(notice: nil) }
        let url = request.outputURL
        let timedOut = await stopAndWait(driver)
        await finishMuteLog()

        guard let startedAt else {
            discard(request)
            guard case .end(let kind) = cause else { return .nothing(notice: nil) }
            return .nothing(notice: kind.reason.map(RecordingEnd.startFailure))
        }

        let kind: RecordingEndKind
        switch cause {
        case .cancel:
            // Save carries on as Stop.
            kind = await cancelDiscards() ? .discardingCancel : .stop
        case .end(let endKind):
            kind = endKind
        }

        let facts = await environment.inspect(url)
        switch RecordingEnd.decide(kind, facts: facts, waitTimedOut: timedOut) {
        case .keep(let notice):
            let poster = await environment.poster(url)
            var recording = Recording(id: request.id, fileURL: url, startedAt: startedAt,
                                      pixelWidth: facts.naturalSize.map { Int($0.width.rounded()) } ?? request.configuration.pixelWidth,
                                      pixelHeight: facts.naturalSize.map { Int($0.height.rounded()) } ?? request.configuration.pixelHeight,
                                      duration: facts.duration, poster: poster, displayID: request.displayID,
                                      gif: request.gif)
            recording.muteIntervals = muteIntervals
            recording.lag = request.lag
            recording.highlightedClicks = extrasSummary.highlightsUsed
            return .keep(recording, notice: notice)
        case .remove(let notice):
            discard(request)
            return .nothing(notice: notice)
        }
    }

    /// Ends the mute log's stream and waits for its last write, once no toggle can come. Nothing
    /// to wait for when the recording was never muted.
    private func finishMuteLog() async {
        await muteLogWriter?.finish()
    }

    /// Removes the recording's file, then its mute log when it was muted, in one ordered removal, so
    /// the log never goes before the file (design, Mute log, Privacy rule). Call it once
    /// `finishMuteLog` has returned, so no write lands after the removal.
    private func discard(_ request: RecordingRequest) {
        environment.removeFiles(muteLogWriter == nil ? [request.outputURL] : [request.outputURL, request.muteLogURL])
    }

    /// A Cancel discards under 5 s, and from 5 s asks: true for Discard. After a quit the answer is
    /// Save, with no question.
    private func cancelDiscards() async -> Bool {
        guard RecordingLimits.asksBeforeDiscarding(elapsed: elapsedAtEnd), let chrome else { return true }
        guard !quitting else { return false }
        return await chrome.askToDiscard(elapsed: elapsedAtEnd)
    }

    /// Calls the driver's stop, then waits until it has returned and the output's finish or fail
    /// has come since the end (the finish can come first), or until `stopTimeout` after the stop
    /// call, so a stop that never returns cannot hold the recording. A stream stop does not end
    /// the wait. The timeout counts time awake only: a Mac that sleeps before the finish would
    /// otherwise time out on wake and read a file the output has not finished. True when it timed
    /// out.
    private func stopAndWait(_ driver: any RecordingStreamDriver) async -> Bool {
        stopReturned = false
        let clock = environment.awakeClock
        let run = runNumber
        let timeout = Task { [weak self] in
            do { try await clock.sleep(for: RecordingLimits.stopTimeout) } catch { return }
            guard let self, runNumber == run else { return }
            RecordingLog.note("Recording: the stop wait timed out after \(RecordingLimits.stopTimeout)")
            resumeStopWaiter(timedOut: true)
        }
        defer { timeout.cancel() }
        Task { [weak self] in
            do {
                try await driver.stop()
            } catch {
                RecordingLog.note("Recording: stopCapture threw: \(error.localizedDescription)")
            }
            // A stop from an earlier run, which outlived its wait, is dropped.
            guard let self, runNumber == run else { return }
            stopReturned = true
            resumeStopWaiter()
        }
        return await withCheckedContinuation { stopWaiter = $0 }
    }

    /// Ends the stop wait once the driver's stop has returned and the output has ended, or at the
    /// timeout. Before the end there is no waiter, so an output that ends early changes nothing here
    /// until `stopAndWait` arms one.
    private func resumeStopWaiter(timedOut: Bool = false) {
        guard timedOut || (stopReturned && outputEnded), let waiter = stopWaiter else { return }
        stopWaiter = nil
        waiter.resume(returning: timedOut)
    }
}
