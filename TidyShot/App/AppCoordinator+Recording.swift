import AppKit
import ScreenCaptureKit

// Record Screen and Record Fullscreen (recording design): start, hand-off, recovery, end, GIF conversion and the recording save funnel. Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// Where Record Screen and Record Fullscreen stand: the count-in (the whole hand-off), the
    /// recording (from `recorder.run`'s call to its return, the stop wait included), the save up to
    /// `history.add`, or nothing.
    var recordingPhase: RecordingPhase {
        if recordingCountIn { return .countIn }
        if recorder.isRunning { return .recording }
        if recordingSavesInFlight > 0 { return .saving }
        return .idle
    }

    /// The count-in's seconds: the self-timer badge counts 3, 2, 1.
    private static let recordingCountInSeconds = 3

    /// What a record shortcut does in each phase: it cancels a count-in and stops a recording,
    /// and otherwise starts one, also while an earlier recording is being saved. While a start
    /// waits on the microphone prompt, another start is ignored.
    nonisolated static func recordingShortcutAction(for phase: RecordingPhase,
                                                    isAskingMicrophone: Bool = false) -> RecordingShortcutAction {
        switch phase {
        case .countIn: .cancelCountIn
        case .recording: .stop
        case .idle, .saving: isAskingMicrophone ? .ignore : .start
        }
    }

    /// The input a recording takes, resolved under the capture lock, and its mute lag.
    private typealias MicrophoneStart = (resolution: MicrophoneChoice.Resolution, lag: TimeInterval)
    /// What `recorder.run` gave, with the microphone note to post after Stop.
    private typealias RecordingEnded = (outcome: RecordingOutcome, microphoneNote: RecordingNotice?)

    /// Record Screen (recording design, Starting): select an area or click a window, then the
    /// hand-off and the recording. The lock is held from the selection to the end of the recording,
    /// and the file is saved after it. An area under 32×32 pt is refused, and no area becomes the
    /// previous area: that is for image captures. The microphone prompt, when it shows, comes
    /// before the lock, and the input is resolved under it before the selection (R2 design, At the
    /// start).
    func recordScreen() async {
        guard recordShortcutStarts(), let choice = await recordingMicrophoneChoice() else { return }
        let intent = CaptureIntent.standard
        var ended: RecordingEnded?
        await withCaptureLock(coversDesktop: true) {
            guard let microphone = recordingCanStart(microphone: choice) else { return }
            guard let content = await loadContent(failureTitle: RecordingEnd.failedTitle) else { return }
            guard let selection = await selector.select(mode: .recording, content: content) else { return }
            let target: CaptureTarget
            switch selection {
            case .area(let rect, let display):
                guard RecordingConfiguration.isLargeEnough(rect.intersection(display.frame)) else {
                    selector.dismiss()
                    notifier.notifyError("Select a larger area to record.", title: RecordingEnd.refusalTitle)
                    return
                }
                target = .area(rect: rect, display: display)
            case .window(let window):
                // The stream shows only the window, so the covers add nothing. The lock's own hide
                // is then a no-op, and a persistent Hide Desktop Icons keeps its covers.
                covers.hide(for: .capture)
                target = .window(window)
            }
            ended = await record(target, microphone: microphone)
        }
        await endRecording(ended, intent: intent)
    }

    /// Record Fullscreen: the display under the pointer, with the same re-entry, lock, checks and
    /// microphone as Record Screen. There is no selection overlay to dismiss and no activation to
    /// give up; the count-in is centred on the display with no frame.
    func recordFullscreen() async {
        guard recordShortcutStarts(), let choice = await recordingMicrophoneChoice() else { return }
        let intent = CaptureIntent.standard
        var ended: RecordingEnded?
        await withCaptureLock(coversDesktop: true) {
            guard let microphone = recordingCanStart(microphone: choice) else { return }
            recordingCountIn = true
            guard let content = await loadContent(failureTitle: RecordingEnd.failedTitle),
                  let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else {
                recordingCountIn = false
                return
            }
            ended = await record(.display(display), microphone: microphone)
        }
        await endRecording(ended, intent: intent)
    }

    /// The status menu's Stop Recording, as the panel's Stop. Nothing happens when no recording runs.
    func stopRecording() {
        recorder.stop()
    }

    /// Both record functions start here, before the capture lock, as Capture Scrolling's shortcut
    /// reaches `advance()`: a count-in is cancelled and a recording stopped, whichever of the two
    /// started it. True when a new recording may start, never once the app is quitting nor while
    /// another start waits on the microphone prompt.
    private func recordShortcutStarts() -> Bool {
        switch Self.recordingShortcutAction(for: recordingPhase, isAskingMicrophone: isAskingMicrophone) {
        case .start:
            return !isQuitting
        case .ignore:
            RecordingLog.note("Recording: start ignored, the microphone prompt is open")
        case .cancelCountIn:
            selfTimer.cancel()
        case .stop:
            recorder.stop()
        }
        return false
    }

    /// The stored microphone a recording starts with, read once (R2 design, At the start): Off for
    /// a GIF, which never prompts. While access is not yet decided, the system prompt shows here,
    /// before the capture lock, so it never shows during a count-in or a recording. Meanwhile
    /// another start is ignored (`isAskingMicrophone`), and nothing else is held. Whatever the
    /// answer, the start goes on: the access is read again under the lock. Nil when the app began
    /// quitting while the prompt was up, so nothing starts.
    private func recordingMicrophoneChoice() async -> MicrophoneChoice.Stored? {
        let format = settings.recordingFormat
        let stored = MicrophoneChoice.Stored(value: settings.recordingMicrophone, name: settings.recordingMicrophoneName)
        let choice = MicrophoneChoice.forRecording(stored, format: format)
        // Off, and so every GIF, reads no access.
        guard choice != .off, MicrophoneChoice.asksForAccess(stored, format: format, access: microphones.access()) else {
            return choice
        }
        isAskingMicrophone = true
        let granted = await microphones.requestAccess()
        isAskingMicrophone = false
        RecordingLog.note("Recording: microphone access \(granted ? "allowed" : "refused") at the prompt")
        return isQuitting ? nil : choice
    }

    /// Makes `tmp/Recording`, then reads its free space. A folder that cannot be made fails the
    /// start with `Recording failed`; under 2 GB refuses it. An unreadable value counts as enough.
    /// Beside that check, before the selection overlay or the count-in, the input the recording
    /// takes (R2 design, At the start; Lag): for a microphone, the access is read again and the
    /// input resolved, with its mute lag; Off, and so every GIF, reads nothing and takes the lag
    /// with no microphone. Nothing here awaits. Nil when the start is refused.
    private func recordingCanStart(microphone choice: MicrophoneChoice.Stored) -> MicrophoneStart? {
        do {
            try Recording.makeDirectory()
        } catch {
            RecordingLog.note("Recording: tmp/Recording could not be made: \(error.localizedDescription)")
            let notice = RecordingEnd.startFailure(error.localizedDescription)
            notifier.notifyError(notice.body, title: notice.title)
            return nil
        }
        let freeBytes = RecordingLimits.freeBytes(at: Recording.directory)
        if freeBytes == nil {
            RecordingLog.note("Recording: the free space of tmp/Recording could not be read, recording anyway")
        }
        guard !RecordingLimits.refusesStart(freeBytes: freeBytes) else {
            notifier.notifyError(RecordingLimits.diskFullText, title: RecordingEnd.refusalTitle)
            return nil
        }
        let resolution = MicrophoneChoice.resolveAtStart(choice, access: { microphones.access() },
                                                         devices: { microphones.list() },
                                                         defaultDevice: { microphones.defaultDevice() })
        return (resolution, muteLag(for: resolution.device))
    }

    /// The hand-off and the recording, with the capture lock held. `recordingCountIn` is true
    /// until `recorder.run` is called or the start gives up. A kept file counts in
    /// `recordingSavesInFlight` before `recorder.close()`, so the phase goes from `.recording` to
    /// `.saving` with nothing between. Nil when nothing started, also when a quit came during the
    /// hand-off: `isQuitting` is read just before `recorder.run`, with no suspension between.
    /// Otherwise the outcome comes back with the microphone note, which posts after Stop.
    private func record(_ target: CaptureTarget, microphone: MicrophoneStart) async -> RecordingEnded? {
        recordingCountIn = true
        let start = await recordingHandOff(target, microphone: microphone)
        recordingCountIn = false
        guard let start, !isQuitting else { return nil }
        let outcome = await recorder.run(start.request, chrome: start.chrome) { [weak self] in
            self?.isRecording = true
        }
        if case .keep = outcome {
            recordingSavesInFlight += 1
        }
        recorder.close()
        return (outcome, start.microphoneNote)
    }

    /// The hand-off (recording design, Starting), in order, with the count-in on or off:
    /// 1. the selection overlay goes, and 2. TidyShot gives up activation, so the user's app is
    /// frontmost and its keys work (neither for fullscreen); 3. the count-in, when it is on;
    /// 4. the settle delay; 5. the display or window is found by id in fresh shareable content, as
    /// `captureAfterCountdown` does, and a window is sized from its fresh frame. A cancelled
    /// count-in, a quit, or a display or window that went (`Screen recording`), gives nil: nothing
    /// started. The input resolved under the lock goes into `RecordingOptions.microphoneID`, with
    /// its lag in the request, and its note comes back for after Stop; a GIF takes neither.
    private func recordingHandOff(_ target: CaptureTarget, microphone: MicrophoneStart)
        async -> (request: RecordingRequest, chrome: any RecordingChrome, microphoneNote: RecordingNotice?)? {
        let isFullscreen: Bool
        if case .display = target { isFullscreen = true } else { isFullscreen = false }
        if !isFullscreen {
            selector.dismiss()
            NSApplication.shared.deactivate()
        }
        // A quit's `selfTimer.cancel()` cannot reach a count-in that has not begun, as when it came
        // during Record Fullscreen's display read.
        guard !isQuitting else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        if settings.recordingCountdown {
            guard let screenFrame = CaptureEngine.screen(forDisplayID: target.displayID)?.frame ?? NSScreen.main?.frame
            else { return nil }
            let stage = SelfTimerScreenStage(subject: Geometry.appKitRect(fromCG: target.cgFrame, primaryHeight: primaryHeight),
                                             screenFrame: screenFrame, showsFrame: !isFullscreen)
            // The recording starts after `run` returns, never inside its capture closure, so
            // `selfTimer.isRunning` is false while it records. `run` supplies the settle delay.
            guard await selfTimer.run(seconds: Self.recordingCountInSeconds, stage: stage, capture: {}) == .finished
            else { return nil }
        } else {
            try? await Task.sleep(for: SelfTimerController.settleDelay)
        }

        guard let content = await loadContent(failureTitle: RecordingEnd.failedTitle) else { return nil }
        let source: RecordingSource
        let placement: RecordingChromePlacement
        let displayID: CGDirectDisplayID
        switch target {
        case .area(let rect, let display):
            guard let current = connectedDisplay(display.displayID, in: content) else { return nil }
            let area = rect.intersection(current.frame)
            displayID = current.displayID
            source = .area(area, on: Self.recordingDisplay(current))
            placement = .area(Geometry.appKitRect(fromCG: area, primaryHeight: primaryHeight),
                              visibleFrame: Self.visibleFrame(forDisplayID: displayID, cgFrame: current.frame))
        case .display(let display):
            guard let current = connectedDisplay(display.displayID, in: content) else { return nil }
            displayID = current.displayID
            source = .display(Self.recordingDisplay(current))
            placement = .fullscreen(visibleFrame: Self.visibleFrame(forDisplayID: displayID, cgFrame: current.frame))
        case .window(let window):
            guard let current = content.windows.first(where: { $0.windowID == window.windowID }) else {
                notifier.notifyError("The window is no longer on screen.", title: RecordingEnd.refusalTitle)
                return nil
            }
            // Sized from the fresh frame at its display's scale, as a window capture without its shadow.
            displayID = CaptureEngine.displayID(containing: current.frame)
            source = .window(id: current.windowID, frame: current.frame, scale: CaptureEngine.scale(forDisplayID: displayID))
            placement = .window(Geometry.appKitRect(fromCG: current.frame, primaryHeight: primaryHeight),
                                visibleFrame: Self.visibleFrame(forDisplayID: displayID, cgFrame: current.frame))
        }
        let id = UUID()
        // Read once: a change in Settings during the recording or its conversion does not reach it.
        var options = settings.recordingOptions
        // `Format` is read again here, so a start that became a GIF drops the input and its note.
        let input = MicrophoneChoice.forRecording(microphone.resolution, format: options.format)
        options.microphoneID = input.device?.uniqueID
        let request = RecordingRequest(id: id, configuration: RecordingConfiguration.make(source, options: options),
                                       displayID: displayID, outputURL: Recording.fileURL(for: id),
                                       muteLogURL: MuteLog.url(for: id), lag: microphone.lag,
                                       gif: options.format == .gif ? options.gif : nil)
        return (request, RecordingScreenChrome(placement: placement), input.note)
    }

    /// The recording's mute lag (design, Lag), read beside `resolve`: for the resolved input, from
    /// the latency CoreAudio reports for it; with none, as for every GIF and `Off` start,
    /// `noMicrophone`, reading no CoreAudio property. Logged at the start.
    private func muteLag(for device: MicrophoneDevice?) -> TimeInterval {
        let lag = MicrophoneLatency.lag(forDeviceUID: device?.uniqueID)
        RecordingLog.note("Recording: mute lag \(String(format: "%.3f", lag)) s (\(device?.name ?? "no microphone"))")
        return lag
    }

    /// The display with `id` in fresh shareable content. When it is gone, `The display is no
    /// longer connected.` posts as a refusal and the result is nil.
    private func connectedDisplay(_ id: CGDirectDisplayID, in content: SCShareableContent) -> SCDisplay? {
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            notifier.notifyError("The display is no longer connected.", title: RecordingEnd.refusalTitle)
            return nil
        }
        return display
    }

    private static func recordingDisplay(_ display: SCDisplay) -> RecordingDisplay {
        RecordingDisplay(id: display.displayID, frame: display.frame, scale: CaptureEngine.scale(forDisplayID: display.displayID))
    }

    /// The visible frame of the display's screen (AppKit points), for the control panel; the
    /// display's whole frame when no screen matches.
    private static func visibleFrame(forDisplayID id: CGDirectDisplayID, cgFrame: CGRect) -> CGRect {
        if let screen = CaptureEngine.screen(forDisplayID: id) {
            return screen.visibleFrame
        }
        return Geometry.appKitRect(fromCG: cgFrame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
    }

    /// The launch check (design, Relaunch after a crash), after `history.load()`. Each playable file
    /// in `tmp/Recording` moves to `pending/<id>.mp4` and gets a record kept until it is deleted
    /// (`fileIsTemporary`, `.none`), timestamped with the file's creation date, sized from the moved
    /// file's attributes, with its poster as the thumbnail; `Recovered a recording` posts and no
    /// card shows. The id is the name's UUID unless a record has it. A file whose move fails stays
    /// for the next launch. An MP4 whose GIF was saved already (`isSavedAsGIF`) is removed instead.
    /// Before its move, a file with a mute log goes through the mute ladder with the same live steps
    /// as the end of a recording (`RecordingRecovery.prepare`): its record is marked when the
    /// muting failed, the body says how it went, and the log goes once the record exists. After
    /// the loop, of what `tmp/Mute` held before it, only what belongs to a file still in
    /// `tmp/Recording` is kept; what was written since is not touched (Decided 2026-10-24, 6).
    func recoverRecordings() async {
        let ext = MediaKind.video.fileExtension
        // Listed before the loop, which can run long after launch: the sweep never removes the log
        // of a recording made since, even one muted before its first frame.
        let muteFiles = RecordingRecovery.listMuteFolder(MuteLog.directory)
        for found in await RecordingRecovery.scan(Recording.directory) {
            let (source, pending) = (found.url, pendingFiles)
            let prepared = await RecordingRecovery.prepare(found, records: history.records,
                                                           muteDirectory: MuteLog.directory) { file, duration, intervals, lag in
                // `prepare` runs the ladder only for a file named by its UUID, which has a log.
                await RecordingMute.resolve(file: file, output: RecordingMute.rewriteURL(for: found.id ?? UUID()),
                                            duration: duration, intervals: intervals, lag: lag, steps: .live)
            }
            guard case .recover(let unmutedIntervals, let bodySuffix, let removesLog) = prepared else {
                let removed = await Task.detached(priority: .utility) { try FileManager.default.removeItem(at: source) }.result
                if case .failure(let error) = removed {
                    RecordingLog.note("Recording: \(source.lastPathComponent) was saved as a GIF and could not be removed: \(error.localizedDescription)")
                } else {
                    RecordingLog.note("Recording: \(source.lastPathComponent) was saved as a GIF, removed")
                }
                continue
            }
            // Read before the move, so only the rename comes between the move and the record.
            let poster = await PosterFrame.image(of: source)
            let id = found.id.flatMap { history.record(id: $0) == nil ? $0 : nil } ?? UUID()
            // The size is the moved file's: after a mute step, the rewritten one's.
            let moved = await Task.detached(priority: .utility) { () throws -> (url: URL, byteCount: Int?) in
                let url = try pending.moveIn(source, id: id, ext: ext)
                return (url, FileSizes.byteCount(of: url))
            }.result
            guard case .success(let (fileURL, byteCount)) = moved else {
                if case .failure(let error) = moved {
                    RecordingLog.note("Recording: \(source.lastPathComponent) could not be recovered, kept for the next launch: \(error.localizedDescription)")
                }
                continue
            }
            let size = found.facts.naturalSize ?? .zero
            let record = CaptureRecord(id: id, timestamp: found.created, fileURL: fileURL, fileIsTemporary: true,
                                       pixelWidth: Int(size.width.rounded()), pixelHeight: Int(size.height.rounded()),
                                       appName: nil, uploadState: .none,
                                       mediaKind: .video, durationSeconds: found.facts.duration, byteCount: byteCount,
                                       unmutedIntervals: unmutedIntervals)
            history.add(record)
            // By the file name's UUID, not the record's id, which can be a fresh one.
            if removesLog, let logID = found.id {
                Recording.removeFile(at: MuteLog.url(for: logID))
            }
            if let poster {
                makeThumbnail(from: poster, for: id)
            }
            RecordingLog.note("Recording: \(source.lastPathComponent) recovered as \(fileURL.lastPathComponent)")
            let body = "\(fileURL.lastPathComponent), \(RecordingClock.format(found.facts.duration)). Find it in Recent Captures."
            notifier.notifyError(bodySuffix.map { "\(body) \($0)" } ?? body, title: "Recovered a recording")
        }
        let recordings = Recording.directory
        await Task.detached(priority: .utility) {
            RecordingRecovery.sweepMuteFolder(muteFiles, recordingDirectory: recordings)
        }.value
    }

    /// After the capture lock: a kept file is handed to `saveRecording`, with `Recording stopped`
    /// when something other than the user's Stop ended it, through a GIF conversion for a GIF
    /// recording and through the mute ladder for a muted one; otherwise the recorder's notice, if
    /// any, posts, in `RecordingNoticeOrder`'s order. The microphone note posts last either way,
    /// as `recorder.run` ran (R2 design, The note posts after Stop). `record.circle` goes as the
    /// file is handed on, or once it was removed.
    private func endRecording(_ ended: RecordingEnded?, intent: CaptureIntent) async {
        guard let ended else { return }
        isRecording = false
        let microphoneNote = ended.microphoneNote
        switch ended.outcome {
        case .keep(let recording, let notice):
            if let gif = recording.gif {
                // A GIF takes no microphone, so it has no note.
                await makeGIF(from: recording, settings: gif, intent: intent, stopNotice: notice)
            } else if !recording.muteIntervals.isEmpty {
                await muteAndSave(recording, intent: intent, stopNotice: notice, microphoneNote: microphoneNote)
            } else {
                await saveRecording(recording, intent: intent, stopNotice: notice, microphoneNote: microphoneNote)
            }
        case .nothing(let notice):
            postAfterStop(save: nil, stop: notice, microphone: microphoneNote, quitMode: isQuitting, revealing: nil)
        }
    }

    // MARK: Muting

    /// Silences a kept MP4's muted stretches before its save (design, After the end, Privacy rule),
    /// in quit mode too: the recording already counts in `recordingSavesInFlight`, so a quit waits
    /// for it. The ladder runs off the main actor with the live steps, which `-MuteFailure` makes
    /// fail in Debug builds. `.muted` and `.soundRemoved` remove the log and save, the second with
    /// `Sound removed` (nothing posts in quit mode; the ladder's log line is the trace). `.notMuted`
    /// saves the file marked with the segments, and the log goes once the record exists; with none
    /// (`.leftInTmp`) it stays for the next launch. The microphone note goes to the save either way.
    private func muteAndSave(_ recording: Recording, intent: CaptureIntent, stopNotice: RecordingNotice?,
                             microphoneNote: RecordingNotice?) async {
        let log = MuteLog.url(for: recording.id)
        let resolution = await RecordingMute.resolve(file: recording.fileURL,
                                                     output: RecordingMute.rewriteURL(for: recording.id),
                                                     duration: recording.duration, intervals: recording.muteIntervals,
                                                     lag: recording.lag, steps: .live)
        switch resolution.outcome {
        case .muted:
            Recording.removeFile(at: log)
            await saveRecording(recording, intent: intent, stopNotice: stopNotice, microphoneNote: microphoneNote)
        case .soundRemoved:
            Recording.removeFile(at: log)
            await saveRecording(recording, intent: intent, stopNotice: stopNotice,
                                saveNotice: RecordingMute.soundRemovedNotice, microphoneNote: microphoneNote)
        case .notMuted:
            if await saveRecording(recording, intent: intent, stopNotice: stopNotice, microphoneNote: microphoneNote,
                                   unmutedIntervals: resolution.segments) != nil {
                Recording.removeFile(at: log)
            }
        }
    }

    // MARK: GIF conversion

    /// The status menu's GIF items, read as the menu opens; nil while nothing converts.
    var gifProgressItems: (progress: String, stop: String)? {
        GIFProgressMenu.items(gifConversions.values.map(\.progress))
    }

    /// `Stop Making GIF(s)` and a quit: every conversion stops, and each saves its MP4 as on
    /// failure, or in quit mode.
    func stopMakingGIFs() {
        for conversion in gifConversions.values {
            conversion.task.cancel()
        }
    }

    /// Converts a kept GIF recording's MP4 and saves the result (design, Conversion). The recording
    /// already counts in `recordingSavesInFlight`, so the phase stays `.saving` and a new recording
    /// may start; the conversion's task is kept in `gifConversions` until it has saved.
    private func makeGIF(from recording: Recording, settings gif: GIFSettings, intent: CaptureIntent,
                         stopNotice: RecordingNotice?) async {
        let conversion = GIFConversion(
            freeBytes: { RecordingLimits.freeBytes(at: Recording.directory) },
            make: { mp4, gifURL, settings, progress in
                try await GIFMaker.make(from: mp4, to: gifURL, fps: settings.fps, maxSide: settings.effectiveMaxSide,
                                        freeBytes: { RecordingLimits.freeBytes(at: Recording.directory) },
                                        progress: progress)
            },
            save: { recording, saveNotice, mode in
                // A task of its own, so `Stop Making GIF`'s cancel never reaches the save.
                await Task {
                    await self.saveRecording(recording, intent: intent, stopNotice: stopNotice, mode: mode,
                                             saveNotice: saveNotice)
                }.value
            },
            removeFile: { Recording.removeFile(at: $0) },
            isQuitting: { self.isQuitting })
        let id = recording.id
        let task = Task {
            await conversion.run(recording, settings: gif) { progress in
                self.gifConversions[id]?.progress = progress
            }
        }
        gifConversions[id] = (task, GIFProgress(fraction: 0, frameCount: GIFMaker.outputFrameCount(duration: recording.duration,
                                                                                                    fps: gif.fps)))
        await task.value
        gifConversions[id] = nil
    }

    /// The recording funnel beside `save(_:intent:)` (design, After stopping). The finished file
    /// is moved, never read: into the save folder under the recording template (asking for a
    /// folder when none is set), or for `.uploadOnly` to `pending/<id>.mp4`. Any failure to reach
    /// the save folder falls back to `pending/`; only a failed rename there leaves the file in
    /// `tmp/Recording`, with no record, for the launch check. `RecordingSavePlan` then decides the
    /// upload, the clipboard and the notification, and the tail `persist` shares does the rest,
    /// with the poster as the thumbnail and the card's image. The record's kind and the file's
    /// extension are `recording.mediaKind`'s. `saveNotice` (`GIF not made`) and `stopNotice`
    /// (`Recording stopped`) post last, in `RecordingNoticeOrder`'s order, `Recording stopped`
    /// revealing the file, in place of `Recording saved`; `microphoneNote` posts after them both,
    /// after `Recording saved` too, and replaces neither. Quit mode (`mode`, or `isQuitting` once
    /// set) never asks for a folder and has no Clop, upload, card or notification; it returns once
    /// the thumbnail is written. `intent.then` and `intent.copyOnly` are ignored. `unmutedIntervals`
    /// (the mute ladder's `.notMuted` segments) keep the file in `pending/` with no folder asked for,
    /// no upload and nothing on the clipboard, mark the record, and post `Sound not muted` (design,
    /// Privacy rule). Returns the record, or nil when the file stayed in `tmp/Recording`, where the
    /// notice names `recording.recoveryURL`, the file the launch check recovers.
    @discardableResult
    func saveRecording(_ recording: Recording, intent: CaptureIntent = .standard, stopNotice: RecordingNotice? = nil,
                       mode: RecordingSaveMode = .normal, saveNotice: RecordingNotice? = nil,
                       microphoneNote: RecordingNotice? = nil,
                       unmutedIntervals: [MuteInterval] = []) async -> CaptureRecord? {
        // Its only callers, the record functions and their GIF conversions, counted the recording in
        // when the recorder kept it.
        // It leaves the count once, on whichever return: right after `history.add` (nothing below it
        // suspends, outside quit mode), in quit mode once the thumbnail is written, or with the file
        // left in `tmp/Recording` before any record.
        defer { recordingSavesInFlight -= 1 }
        // Read again after each await: a save already under way when the app starts quitting
        // finishes in quit mode.
        var quitMode = mode == .quit || isQuitting
        // The next capture: the newest card's image is no longer kept.
        latestCapture = nil
        latestCaptureArea = nil
        let action = intent.action
        // One keychain read per recording, as for a screenshot; none for a marked one, which never uploads.
        let destination = action.uploads && unmutedIntervals.isEmpty ? makeDestination() : nil

        var folder: (url: URL, baseName: String)?
        var noFolderReason: String?
        if RecordingSavePlan.target(for: action, unmutedIntervals: unmutedIntervals) == .saveFolder {
            // A quit closes an open folder panel (`cancelFolderChoice`), which then gives nil.
            let chosen = quitMode ? saveLocation.currentURL : await saveLocation.ensureFolder()
            quitMode = mode == .quit || isQuitting
            if let chosen {
                folder = (chosen, recordingBaseName(startedAt: recording.startedAt))
            } else {
                noFolderReason = RecordingSavePlan.noFolderReason
            }
        }
        let (source, id, pending, target) = (recording.fileURL, recording.id, pendingFiles, folder)
        let (kind, recoveryURL) = (recording.mediaKind, recording.recoveryURL)
        // The size is the file's after its move, read from its attributes under the save folder's
        // scope when it went there: a GIF's own, or the MP4's after a failed conversion.
        let (result, fileURL, byteCount) = await Task.detached(priority: .userInitiated) {
            let (result, url) = Self.placeRecording(source, kind: kind, id: id, folder: target,
                                                    noFolderReason: noFolderReason, pending: pending,
                                                    recoveryURL: recoveryURL)
            let scope = if case .saveFolder = result { target?.url } else { URL?.none }
            return (result, url, FileSizes.byteCount(of: url, scope: scope))
        }.value
        quitMode = mode == .quit || isQuitting

        let plan = RecordingSavePlan.make(action: action, hasDestination: destination != nil, result: result,
                                          copyImage: settings.copyImageToClipboard,
                                          alsoCopyImage: settings.alsoCopyImageWhenUploading, quitMode: quitMode,
                                          unmutedIntervals: unmutedIntervals)
        guard plan.makesRecord else {
            if case .notice(let notice) = plan.notification {
                notifier.notifyError(notice.body, title: notice.title)
            }
            postAfterStop(save: saveNotice, stop: stopNotice, microphone: microphoneNote, quitMode: quitMode,
                          revealing: recoveryURL)
            return nil
        }
        if plan.setsLastCaptureURL {
            lastCaptureURL = fileURL
        }
        // Decides whether the URL replaces the clipboard when the upload finishes.
        videoClipboardCounts[id] = plan.copiesFileReference
            ? Pasteboard.copy(fileURL: fileURL) : NSPasteboard.general.changeCount

        let record = CaptureRecord(id: id, timestamp: recording.startedAt, fileURL: fileURL,
                                   fileIsTemporary: plan.fileIsTemporary,
                                   pixelWidth: recording.pixelWidth, pixelHeight: recording.pixelHeight,
                                   appName: nil, uploadState: plan.uploadState,
                                   mediaKind: kind, durationSeconds: recording.duration, byteCount: byteCount,
                                   unmutedIntervals: unmutedIntervals)
        let notification: SaveNotification
        switch plan.notification {
        case .none: notification = .none
        // `GIF not made` or `Recording stopped`, below, replaces it.
        case .saved: notification = saveNotice == nil && stopNotice == nil ? .saved(title: "Recording saved") : .none
        case .notice(let notice): notification = .notice(notice)
        }
        // The poster is fitted into the card's well and the drag image, so its point size does not matter.
        await finishSave(record, image: recording.poster, scale: 1, captureDisplayID: recording.displayID,
                         notConfiguredWarning: plan.notConfiguredWarning, showsCard: plan.showsCard,
                         upload: plan.uploads ? destination : nil, payload: { try uploadPayload(for: record) },
                         notification: notification, awaitsThumbnail: quitMode)
        postAfterStop(save: saveNotice, stop: stopNotice, microphone: microphoneNote, quitMode: quitMode,
                      revealing: fileURL)
        return record
    }

    /// The notices after Stop (plan Gap 2) in `RecordingNoticeOrder`'s order, none in quit mode.
    /// `stop` reveals `file`, the recording's final file.
    private func postAfterStop(save: RecordingNotice?, stop: RecordingNotice?, microphone: RecordingNotice?,
                               quitMode: Bool, revealing file: URL?) {
        for notice in RecordingNoticeOrder.afterStop(save: save, stop: stop, microphone: microphone, quitMode: quitMode) {
            notifier.notifyError(notice.body, title: notice.title, revealing: notice == stop ? file : nil)
        }
    }

    /// A recording's file name in the save folder: `Recording file name` at the time the recording
    /// started, or `Recording` when that expands to nothing, with `{counter}` drawn as for screenshots.
    func recordingBaseName(startedAt: Date) -> String {
        let template = settings.recordingFileNameTemplate
        let counter = template.contains("{counter}") ? settings.nextCounter() : 0
        return FileNamer(template: template, fallbackName: FileNamer.recordingFallbackName, now: { startedAt })
            .name(counter: counter)
    }

    /// Moves a finished recording out of `tmp/Recording` (design, Where the file lands), in a
    /// detached task, with `kind`'s extension. With `folder` it goes into the save folder. When
    /// that move fails, or there is no folder (`noFolderReason`), it is renamed to
    /// `pending/<id>.<ext>` as a fallback; with neither, it goes there as `.uploadOnly`'s target.
    /// Only when that rename fails does it stay where it is (`.leftInTmp`, with the rename's error
    /// and the path of `recoveryURL`, the file the launch check recovers). Never reads the file.
    nonisolated private static func placeRecording(_ source: URL, kind: MediaKind, id: UUID,
                                                   folder: (url: URL, baseName: String)?, noFolderReason: String?,
                                                   pending: PendingFileStore,
                                                   recoveryURL: URL) -> (result: RecordingFileResult, url: URL) {
        let ext = kind.fileExtension
        var reason = noFolderReason
        if let folder {
            do {
                return (.saveFolder, try SaveLocation.moveInScoped(source, baseName: folder.baseName, ext: ext,
                                                                   folder: folder.url))
            } catch {
                RecordingLog.note("Recording: \(source.lastPathComponent) could not be moved into the save folder: \(error.localizedDescription)")
                reason = error.localizedDescription
            }
        }
        do {
            let url = try pending.moveIn(source, id: id, ext: ext)
            return (reason.map { .fallback(reason: $0) } ?? .pending, url)
        } catch {
            RecordingLog.note("Recording: \(source.lastPathComponent) could not be moved to pending: \(error.localizedDescription)")
            return (.leftInTmp(reason: error.localizedDescription, path: recoveryURL.path(percentEncoded: false)), source)
        }
    }
}

/// How `saveRecording` runs: `quit` while the app quits, logs out or restarts, with no folder
/// prompt, Clop, upload, card or notification, and the thumbnail written before it returns.
nonisolated enum RecordingSaveMode: Equatable, Sendable {
    case normal
    case quit
}

/// Where Record Screen and Record Fullscreen stand (`AppCoordinator.recordingPhase`).
nonisolated enum RecordingPhase: Equatable, Sendable {
    case idle
    /// The whole hand-off, from the selection to `recorder.run`, with the count-in on or off.
    case countIn
    /// From `recorder.run`'s call to its return, the stop wait included.
    case recording
    /// A kept recording on its way to `history.add`.
    case saving
}

/// What a record shortcut does (`AppCoordinator.recordingShortcutAction(for:isAskingMicrophone:)`).
nonisolated enum RecordingShortcutAction: Equatable, Sendable {
    case start
    /// A start while another waits on the microphone prompt.
    case ignore
    case cancelCountIn
    case stop
}
