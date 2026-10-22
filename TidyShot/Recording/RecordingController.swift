import AppKit
import CoreGraphics
import Foundation

/// One recording to run: the id that names the file, the stream's configuration, the display it
/// is on, and `tmp/Recording/<id>.mp4`, whose folder already exists.
struct RecordingRequest {
    let id: UUID
    let configuration: RecordingConfiguration
    let displayID: CGDirectDisplayID
    let outputURL: URL
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
    var clock: any ScrollClock
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
    var removeFile: (URL) -> Void
    /// Where sleep and the user switch are posted.
    var workspaceCenter: NotificationCenter

    static func live(cardWindowNumbers: @escaping () -> Set<CGWindowID>,
                     coverWindowNumbers: @escaping (CGDirectDisplayID) -> Set<CGWindowID>) -> RecordingEnvironment {
        RecordingEnvironment(
            clock: SystemScrollClock(),
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
            removeFile: { url in
                Task.detached {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch CocoaError.fileNoSuchFile {
                        // A start that failed early wrote nothing.
                    } catch {
                        RecordingLog.note("Recording: \(url.lastPathComponent) could not be removed: \(error.localizedDescription)")
                    }
                }
            },
            workspaceCenter: NSWorkspace.shared.notificationCenter)
    }
}

/// Runs one recording (design, While recording, Stopping and End rule): the chrome, the stream,
/// the elapsed time, the window poll, the disk check, sleep and the user switch, the stop wait
/// and the end rule. The first end wins. The caller holds the capture lock around `run` and
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

    private var chrome: (any RecordingChrome)?
    private var request: RecordingRequest?
    private var onStarted: () -> Void = {}
    /// The first end, and the elapsed time when it came.
    private var cause: EndCause?
    private var elapsedAtEnd: TimeInterval = 0
    /// Set at `recordingStarted`; nil before the first frame.
    private var firstFrame: ContinuousClock.Instant?
    private var startedAt: Date?
    /// The output finished or failed: it writes nothing more.
    private var outputEnded = false
    /// The stop wait's one-shot waiter, armed at the end, has fired: a finish or a fail since
    /// then, or an output that had already ended.
    private var waitIsOver = false
    /// The driver's stop has returned or thrown.
    private var stopReturned = false
    private var stopWaiter: CheckedContinuation<Bool, Never>?
    /// `run` waits here for the first end.
    private var endWaiter: CheckedContinuation<Void, Never>?
    private var ticking: Task<Void, Never>?
    private var activity: (any NSObjectProtocol)?
    private var observers: [any NSObjectProtocol] = []

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
        reset(for: request, chrome: chrome, onStarted: onStarted)
        observeWorkspace()
        // The chrome is on screen before the driver reads the shareable content, so the
        // fallback exclusion can find it.
        chrome.show(onStop: { [weak self] in self?.stop() }, onCancel: { [weak self] in self?.cancel() })
        let exclusions = RecordingExclusions(chromeWindows: chrome.windowNumbers,
                                             cardWindows: environment.cardWindowNumbers(),
                                             coverWindows: environment.coverWindowNumbers(request.displayID))
        let driver = makeDriver()
        do {
            try await driver.start(request.configuration, outputURL: request.outputURL, exclusions: exclusions) { [weak self] event in
                self?.handle(event)
            }
        } catch {
            // Nothing is recording, so there is nothing to wait for. Later callbacks are ignored.
            RecordingLog.note("Recording: the stream did not start: \(error.localizedDescription)")
            end(.end(.failed(error.localizedDescription)))
            environment.removeFile(request.outputURL)
            return .nothing(notice: RecordingEnd.startFailure(error.localizedDescription))
        }
        if cause == nil {
            await withCheckedContinuation { endWaiter = $0 }
        }
        return await finish(driver)
    }

    /// The panel's Stop, the shortcuts, the menu and a quit.
    func stop() {
        end(.end(.stop))
    }

    /// The panel's Cancel.
    func cancel() {
        end(.cancel)
    }

    /// Closes the chrome, ends the activity and stops observing sleep and the user switch. Call
    /// it once `run` has returned, where the capture lock is released.
    func close() {
        ticking?.cancel()
        ticking = nil
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
        elapsedAtEnd = 0
        firstFrame = nil
        startedAt = nil
        outputEnded = false
        waitIsOver = false
        stopReturned = false
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
            onStarted()
        case .recordingFinished:
            outputEnded = true
            stopWaitEnded()
            end(.end(.failed(Self.streamStoppedReason)))
        case .outputFailed(let description):
            outputEnded = true
            stopWaitEnded()
            end(.end(.failed(description)))
        case .streamStopped(let description):
            // It never ends the stop wait: the output may still be finishing the file, which
            // cannot be opened until the finish (290 ms after the stop, in the 5K probe). The
            // wait takes the output's finish or fail, or the timeout.
            end(.end(.failed(description)))
        case .streamInactive, .streamActive:
            // The driver's log lines are their only trace: window loss is polled.
            break
        }
    }

    /// The elapsed time, the window poll and, every 5 s, the disk check, on whole seconds from
    /// the first frame.
    private func startTicking() {
        guard let firstFrame else { return }
        let clock = environment.clock
        let diskCheckTicks = max(1, Int(RecordingLimits.diskCheckInterval / .seconds(1)))
        ticking = Task { [weak self] in
            var ticks = 0
            while true {
                ticks += 1
                do {
                    try await clock.sleep(for: max(.zero, firstFrame + .seconds(ticks) - clock.now))
                } catch {
                    return
                }
                self?.tick(checksDisk: ticks % diskCheckTicks == 0)
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

    private var elapsed: TimeInterval {
        guard let firstFrame else { return 0 }
        return (environment.clock.now - firstFrame) / .seconds(1)
    }

    // MARK: Ending

    /// The first end wins; any later one is ignored. Stop is disabled and the stop wait's waiter
    /// is armed here, before `run` calls the driver's stop.
    private func end(_ cause: EndCause) {
        guard isRunning, self.cause == nil else { return }
        self.cause = cause
        elapsedAtEnd = elapsed
        waitIsOver = outputEnded
        ticking?.cancel()
        ticking = nil
        chrome?.setStopEnabled(false)
        endWaiter?.resume()
        endWaiter = nil
    }

    /// The output's finish or fail. Once the end has armed the waiter, it fires it.
    private func stopWaitEnded() {
        guard cause != nil else { return }
        waitIsOver = true
        resumeStopWaiter()
    }

    /// Stops the stream, waits, then applies the end rule. Nothing touches the file before the
    /// wait ends. An end before the first frame removes the file whatever it holds.
    private func finish(_ driver: any RecordingStreamDriver) async -> RecordingOutcome {
        guard let cause, let request else { return .nothing(notice: nil) }
        let url = request.outputURL
        let timedOut = await stopAndWait(driver)

        guard let startedAt else {
            environment.removeFile(url)
            guard case .end(let kind) = cause else { return .nothing(notice: nil) }
            return .nothing(notice: kind.reason.map(RecordingEnd.startFailure))
        }

        let kind: RecordingEndKind
        switch cause {
        case .cancel:
            if RecordingLimits.asksBeforeDiscarding(elapsed: elapsedAtEnd),
               let chrome, !(await chrome.askToDiscard(elapsed: elapsedAtEnd)) {
                // Save carries on as Stop.
                kind = .stop
            } else {
                kind = .discardingCancel
            }
        case .end(let endKind):
            kind = endKind
        }

        let facts = await environment.inspect(url)
        switch RecordingEnd.decide(kind, facts: facts, waitTimedOut: timedOut) {
        case .keep(let notice):
            let poster = await environment.poster(url)
            let recording = Recording(id: request.id, fileURL: url, startedAt: startedAt,
                                      pixelWidth: facts.naturalSize.map { Int($0.width.rounded()) } ?? request.configuration.pixelWidth,
                                      pixelHeight: facts.naturalSize.map { Int($0.height.rounded()) } ?? request.configuration.pixelHeight,
                                      duration: facts.duration, poster: poster, displayID: request.displayID)
            return .keep(recording, notice: notice)
        case .remove(let notice):
            environment.removeFile(url)
            return .nothing(notice: notice)
        }
    }

    /// Calls the driver's stop, then waits until it has returned and the output's finish or fail
    /// has come since the end (the finish can come first), or until `stopTimeout` after the stop
    /// call, so a stop that never returns cannot hold the recording. A stream stop does not end
    /// the wait. True when it timed out.
    private func stopAndWait(_ driver: any RecordingStreamDriver) async -> Bool {
        stopReturned = false
        let clock = environment.clock
        let timeout = Task { [weak self] in
            do { try await clock.sleep(for: RecordingLimits.stopTimeout) } catch { return }
            RecordingLog.note("Recording: the stop wait timed out after \(RecordingLimits.stopTimeout)")
            self?.resumeStopWaiter(timedOut: true)
        }
        defer { timeout.cancel() }
        Task { [weak self] in
            do {
                try await driver.stop()
            } catch {
                RecordingLog.note("Recording: stopCapture threw: \(error.localizedDescription)")
            }
            self?.stopReturned = true
            self?.resumeStopWaiter()
        }
        return await withCheckedContinuation { stopWaiter = $0 }
    }

    /// Ends the stop wait once the driver's stop has returned and the waiter has fired, or at
    /// the timeout.
    private func resumeStopWaiter(timedOut: Bool = false) {
        guard timedOut || (stopReturned && waitIsOver), let waiter = stopWaiter else { return }
        stopWaiter = nil
        waiter.resume(returning: timedOut)
    }
}
