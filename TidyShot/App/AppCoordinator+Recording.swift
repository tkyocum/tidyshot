import AppKit
import ScreenCaptureKit

// Record Screen and Record Fullscreen (recording design): start, hand-off, recovery, end and the recording save funnel. Its state is declared in AppCoordinator.swift.
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
    /// and otherwise starts one, also while an earlier recording is being saved.
    nonisolated static func recordingShortcutAction(for phase: RecordingPhase) -> RecordingShortcutAction {
        switch phase {
        case .countIn: .cancelCountIn
        case .recording: .stop
        case .idle, .saving: .start
        }
    }

    /// Record Screen (recording design, Starting): select an area or click a window, then the
    /// hand-off and the recording. The lock is held from the selection to the end of the recording,
    /// and the file is saved after it. An area under 32×32 pt is refused, and no area becomes the
    /// previous area: that is for image captures.
    func recordScreen() async {
        guard recordShortcutStarts() else { return }
        let intent = CaptureIntent.standard
        var outcome: RecordingOutcome?
        await withCaptureLock(coversDesktop: true) {
            guard recordingCanStart() else { return }
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
            outcome = await record(target)
        }
        await endRecording(outcome, intent: intent)
    }

    /// Record Fullscreen: the display under the pointer, with the same re-entry, lock and checks as
    /// Record Screen. There is no selection overlay to dismiss and no activation to give up; the
    /// count-in is centred on the display with no frame.
    func recordFullscreen() async {
        guard recordShortcutStarts() else { return }
        let intent = CaptureIntent.standard
        var outcome: RecordingOutcome?
        await withCaptureLock(coversDesktop: true) {
            guard recordingCanStart() else { return }
            recordingCountIn = true
            guard let content = await loadContent(failureTitle: RecordingEnd.failedTitle),
                  let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else {
                recordingCountIn = false
                return
            }
            outcome = await record(.display(display))
        }
        await endRecording(outcome, intent: intent)
    }

    /// The status menu's Stop Recording, as the panel's Stop. Nothing happens when no recording runs.
    func stopRecording() {
        recorder.stop()
    }

    /// Both record functions start here, before the capture lock, as Capture Scrolling's shortcut
    /// reaches `advance()`: a count-in is cancelled and a recording stopped, whichever of the two
    /// started it. True when a new recording may start, never once the app is quitting.
    private func recordShortcutStarts() -> Bool {
        switch Self.recordingShortcutAction(for: recordingPhase) {
        case .start:
            return !isQuitting
        case .cancelCountIn:
            selfTimer.cancel()
        case .stop:
            recorder.stop()
        }
        return false
    }

    /// Makes `tmp/Recording`, then reads its free space. A folder that cannot be made fails the
    /// start with `Recording failed`; under 2 GB refuses it. An unreadable value counts as enough.
    private func recordingCanStart() -> Bool {
        do {
            try Recording.makeDirectory()
        } catch {
            RecordingLog.note("Recording: tmp/Recording could not be made: \(error.localizedDescription)")
            let notice = RecordingEnd.startFailure(error.localizedDescription)
            notifier.notifyError(notice.body, title: notice.title)
            return false
        }
        let freeBytes = RecordingLimits.freeBytes(at: Recording.directory)
        if freeBytes == nil {
            RecordingLog.note("Recording: the free space of tmp/Recording could not be read, recording anyway")
        }
        guard !RecordingLimits.refusesStart(freeBytes: freeBytes) else {
            notifier.notifyError(RecordingLimits.diskFullText, title: RecordingEnd.refusalTitle)
            return false
        }
        return true
    }

    /// The hand-off and the recording, with the capture lock held. `recordingCountIn` is true
    /// until `recorder.run` is called or the start gives up. A kept file counts in
    /// `recordingSavesInFlight` before `recorder.close()`, so the phase goes from `.recording` to
    /// `.saving` with nothing between. Nil when nothing started, also when a quit came during the
    /// hand-off: `isQuitting` is read just before `recorder.run`, with no suspension between.
    private func record(_ target: CaptureTarget) async -> RecordingOutcome? {
        recordingCountIn = true
        let start = await recordingHandOff(target)
        recordingCountIn = false
        guard let start, !isQuitting else { return nil }
        let outcome = await recorder.run(start.request, chrome: start.chrome) { [weak self] in
            self?.isRecording = true
        }
        if case .keep = outcome {
            recordingSavesInFlight += 1
        }
        recorder.close()
        return outcome
    }

    /// The hand-off (recording design, Starting), in order, with the count-in on or off:
    /// 1. the selection overlay goes, and 2. TidyShot gives up activation, so the user's app is
    /// frontmost and its keys work (neither for fullscreen); 3. the count-in, when it is on;
    /// 4. the settle delay; 5. the display or window is found by id in fresh shareable content, as
    /// `captureAfterCountdown` does, and a window is sized from its fresh frame. A cancelled
    /// count-in, a quit, or a display or window that went (`Screen recording`), gives nil: nothing
    /// started.
    private func recordingHandOff(_ target: CaptureTarget) async -> (request: RecordingRequest, chrome: any RecordingChrome)? {
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
        let request = RecordingRequest(id: id, configuration: RecordingConfiguration.make(source, options: settings.recordingOptions),
                                       displayID: displayID, outputURL: Recording.fileURL(for: id))
        return (request, RecordingScreenChrome(placement: placement))
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
    /// for the next launch.
    func recoverRecordings() async {
        let ext = MediaKind.video.fileExtension
        for found in await RecordingRecovery.scan(Recording.directory) {
            let (source, pending) = (found.url, pendingFiles)
            // Read before the move, so only the rename comes between the move and the record.
            let poster = await PosterFrame.image(of: source)
            let id = found.id.flatMap { history.record(id: $0) == nil ? $0 : nil } ?? UUID()
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
                                       mediaKind: .video, durationSeconds: found.facts.duration, byteCount: byteCount)
            history.add(record)
            if let poster {
                makeThumbnail(from: poster, for: id)
            }
            RecordingLog.note("Recording: \(source.lastPathComponent) recovered as \(fileURL.lastPathComponent)")
            notifier.notifyError("\(fileURL.lastPathComponent), \(RecordingClock.format(found.facts.duration)). Find it in Recent Captures.",
                                 title: "Recovered a recording")
        }
    }

    /// After the capture lock: a kept file is handed to `saveRecording`, with `Recording stopped`
    /// when something other than the user's Stop ended it; otherwise the recorder's notice, if any,
    /// posts. `record.circle` goes as the file is handed on, or once it was removed.
    private func endRecording(_ outcome: RecordingOutcome?, intent: CaptureIntent) async {
        guard let outcome else { return }
        isRecording = false
        switch outcome {
        case .keep(let recording, let notice):
            await saveRecording(recording, intent: intent, stopNotice: notice)
        case .nothing(let notice):
            if let notice {
                notifier.notifyError(notice.body, title: notice.title)
            }
        }
    }

    /// The recording funnel beside `save(_:intent:)` (design, After stopping). The finished file
    /// is moved, never read: into the save folder under the recording template (asking for a
    /// folder when none is set), or for `.uploadOnly` to `pending/<id>.mp4`. Any failure to reach
    /// the save folder falls back to `pending/`; only a failed rename there leaves the file in
    /// `tmp/Recording`, with no record, for the launch check. `RecordingSavePlan` then decides the
    /// upload, the clipboard and the notification, and the tail `persist` shares does the rest,
    /// with the poster as the thumbnail and the card's image. `stopNotice` (`Recording stopped`)
    /// posts last, revealing the file, in place of `Recording saved`. Quit mode (`mode`, or
    /// `isQuitting` once set) never asks for a folder and has no Clop, upload, card or
    /// notification; it returns once the thumbnail is written. `intent.then` and
    /// `intent.copyOnly` are ignored. Returns the record, or nil when the file stayed in
    /// `tmp/Recording`.
    @discardableResult
    func saveRecording(_ recording: Recording, intent: CaptureIntent = .standard, stopNotice: RecordingNotice? = nil,
                       mode: RecordingSaveMode = .normal) async -> CaptureRecord? {
        // Its only callers, the record functions, counted the recording in when the recorder kept it.
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
        // One keychain read per recording, as for a screenshot.
        let destination = action.uploads ? makeDestination() : nil

        var folder: (url: URL, baseName: String)?
        var noFolderReason: String?
        if RecordingSavePlan.target(for: action) == .saveFolder {
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
        // The size is the file's after its move, read from its attributes under the save folder's
        // scope when it went there.
        let (result, fileURL, byteCount) = await Task.detached(priority: .userInitiated) {
            let (result, url) = Self.placeRecording(source, id: id, folder: target, noFolderReason: noFolderReason,
                                                    pending: pending)
            let scope = if case .saveFolder = result { target?.url } else { URL?.none }
            return (result, url, FileSizes.byteCount(of: url, scope: scope))
        }.value
        quitMode = mode == .quit || isQuitting

        let plan = RecordingSavePlan.make(action: action, hasDestination: destination != nil, result: result,
                                          copyImage: settings.copyImageToClipboard,
                                          alsoCopyImage: settings.alsoCopyImageWhenUploading, quitMode: quitMode)
        guard plan.makesRecord else {
            if case .notice(let notice) = plan.notification {
                notifier.notifyError(notice.body, title: notice.title)
            }
            if !quitMode, let stopNotice {
                notifier.notifyError(stopNotice.body, title: stopNotice.title, revealing: fileURL)
            }
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
                                   mediaKind: .video, durationSeconds: recording.duration, byteCount: byteCount)
        let notification: SaveNotification
        switch plan.notification {
        case .none: notification = .none
        // `Recording stopped`, below, replaces it.
        case .saved: notification = stopNotice == nil ? .saved(title: "Recording saved") : .none
        case .notice(let notice): notification = .notice(notice)
        }
        // The poster is fitted into the card's well and the drag image, so its point size does not matter.
        await finishSave(record, image: recording.poster, scale: 1, captureDisplayID: recording.displayID,
                         notConfiguredWarning: plan.notConfiguredWarning, showsCard: plan.showsCard,
                         upload: plan.uploads ? destination : nil, payload: { try uploadPayload(for: record) },
                         notification: notification, awaitsThumbnail: quitMode)
        if !quitMode, let stopNotice {
            notifier.notifyError(stopNotice.body, title: stopNotice.title, revealing: fileURL)
        }
        return record
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
    /// detached task. With `folder` it goes into the save folder. When that move fails, or there is
    /// no folder (`noFolderReason`), it is renamed to `pending/<id>.mp4` as a fallback; with
    /// neither, it goes there as `.uploadOnly`'s target. Only when that rename fails does it stay
    /// where it is (`.leftInTmp`, with the rename's error). Never reads the file.
    nonisolated private static func placeRecording(_ source: URL, id: UUID, folder: (url: URL, baseName: String)?,
                                                   noFolderReason: String?, pending: PendingFileStore)
        -> (result: RecordingFileResult, url: URL) {
        let ext = MediaKind.video.fileExtension
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
            return (.leftInTmp(reason: error.localizedDescription, path: source.path(percentEncoded: false)), source)
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

/// What a record shortcut does (`AppCoordinator.recordingShortcutAction(for:)`).
nonisolated enum RecordingShortcutAction: Equatable, Sendable {
    case start
    case cancelCountIn
    case stop
}
