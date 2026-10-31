import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, output, upload, and history together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    // MARK: Collaborators
    /// What the coordinator was built over (harness design 2.1): `.live()` in the app, a test's world
    /// in the suite. The collaborators below come from it, and the extension files read its closures.
    let environment: AppEnvironment
    let engine = CaptureEngine()
    let saveLocation: SaveLocation
    let settings: AppSettings
    let history: HistoryStore
    /// `thumbnails` and `pending` folders next to `history.json`.
    let thumbnails: ThumbnailStore
    let pendingFiles: PendingFileStore
    /// `multipart` next to `history.json`: each multipart upload's part list and kept Clop copy.
    let multipartFiles: MultipartStore
    /// Drag-out copies, `<container tmp>/Drag/<id>/` (spec 2.9).
    let dragFiles: DragFileStore
    let credentialStore: any CredentialStore
    let notifier: any Notifying
    private let permissionWindow = PermissionWindowController()
    let overlay: any QuickAccessCards
    /// The general pasteboard, through `Clipboard`.
    let clipboard: any Clipboard
    @ObservationIgnored lazy var selector = SelectionController(engine: engine, settings: settings, cardWindowNumbers: { [weak self] in self?.overlay.windowNumbers ?? [] })
    @ObservationIgnored lazy var scrollCapture = ScrollCaptureController(engine: engine, settings: settings)
    /// `tidyshot://` commands (spec 2.9): held until `start()` has run, then parsed, gated and
    /// routed to the capture functions. It holds this coordinator weakly.
    @ObservationIgnored private lazy var urlCommands = URLCommandHandler(
        settings: settings, target: self, screens: { AppCoordinator.urlCommandScreens() },
        post: { [weak self] notice in
            self?.notifier.notifyError(notice.body, title: notice.title, subtitle: notice.subtitle)
        })
    @ObservationIgnored lazy var selfTimer = SelfTimerController()
    /// Record Screen and Record Fullscreen (recording design): one recording at a time, run inside
    /// the capture lock. The stream leaves out the cards and, for area and fullscreen recordings,
    /// keeps the display's desktop cover in the picture.
    @ObservationIgnored lazy var recorder = RecordingController(
        environment: .live(cardWindowNumbers: { [weak self] in self?.overlay.windowNumbers ?? [] },
                           coverWindowNumbers: { [weak self] displayID in
                               self?.covers.windowNumbers[displayID].map { [$0] } ?? []
                           },
                           microphones: microphones),
        makeDriver: { [engine] in ScreenRecordingDriver(engine: engine) })
    /// The audio inputs and the microphone access, for a recording's start (the prompt, then the
    /// input under the capture lock) and its loss reason. Capture → Recording → `Microphone` reads its own.
    @ObservationIgnored lazy var microphones: any MicrophoneDevices = LiveMicrophoneDevices()
    /// The cameras and the camera access, for a recording's start (the prompt, then the camera under
    /// the capture lock) and Settings' prompt. Capture → Recording → `Camera` reads its own.
    @ObservationIgnored lazy var cameras: any CameraDevices = LiveCameraDevices()
    /// Hide desktop icons (spec 2.10): the wallpaper over the desktop's icons and widgets, while a
    /// capture runs or until turned off. A display it cannot cover is reported once per session;
    /// without Screen Recording, which is why nothing could be read, the permission window shows instead.
    @ObservationIgnored lazy var covers = DesktopCoverController(source: WallpaperSource(), reportFailure: { [weak self] in
        guard let self else { return }
        if !ScreenCapturePermission.isGranted {
            self.showPermissionWindow()
        } else {
            self.notifier.notifyError("TidyShot could not read the desktop picture.", title: "Desktop icons still showing")
        }
    })
    /// Thumbnails and previews for Recent Captures.
    @ObservationIgnored private(set) lazy var thumbnailProvider = ThumbnailProvider(
        store: thumbnails, history: history, saveFolder: { [unowned self] in self.saveLocation.currentURL },
        readFile: { fileURL, folder in
            // Runs in a detached task. A temporary file in `pending` needs no scope.
            guard let folder else { return try Data(contentsOf: fileURL) }
            return try SaveLocation.readScoped(fileURL, folder: folder)
        })

    // MARK: Capture state (AppCoordinator+Capture.swift; the lock is withCaptureLock, below)
    private(set) var isCapturing = false
    /// The last capture written to the save folder (upload-only captures do not count).
    var lastCaptureURL: URL?

    // MARK: Recording state (AppCoordinator+Recording.swift)
    /// From a recording's first frame until its file is handed on to its save (a GIF's conversion
    /// first) or removed: the status item shows `record.circle` and the menu offers Stop Recording.
    var isRecording = false
    /// A recording's count-in flag: true from the selection's return (Record Fullscreen: from the
    /// free-space check) until `recorder.run` is called or the start gives up. It covers the
    /// count-in, the settle delay and the fresh content read, with the count-in on or off.
    /// `selfTimer.isRunning` cannot serve: it stays true until `run`'s capture closure returns.
    @ObservationIgnored var recordingCountIn = false {
        didSet { if recordingCountIn, !oldValue { recordingStartCancelled = false } }
    }
    /// Set by `stop-recording` or the record shortcut during a count-in (R4 design, What
    /// `stop-recording` does in each phase): `selfTimer.cancel()` reaches only the countdown, so a
    /// cancel during the settle delay or the fresh content read would be lost. `record()` reads it
    /// with `isQuitting` just before `recorder.run` and starts nothing when it is set. Reset when
    /// `recordingCountIn` turns from false to true (plan Gap 6).
    @ObservationIgnored var recordingStartCancelled = false
    /// Set by `startRecording` (a `record-screen` URL) before its `Task` runs, and cleared once that
    /// start's capture lock is held or refused (plan Gap 18). In between the phase reads idle with
    /// no lock and no prompt, so a second `record-screen` would not be dropped by the handler; while
    /// it is set, `startRecording` ignores it and logs why.
    @ObservationIgnored var urlRecordingStartPending = false
    /// The system prompt a record function waits on, before the capture lock, or Settings asked
    /// for (`requestAccessFromSettings`): another start is ignored, and every other capture is
    /// refused as while one runs (`capturesRefused`). The lock itself is free and `recordingPhase`
    /// does not change.
    @ObservationIgnored var askingPermission: PermissionPrompt?
    /// Recordings between the recorder's `.keep` and `history.add` (in quit mode, until the
    /// thumbnail is written), a GIF's conversion included, so the phase never reads `.idle` in
    /// between.
    @ObservationIgnored var recordingSavesInFlight = 0
    /// Set by `finishRecordingForQuit` once the editors let the quit go ahead; never cleared, as the
    /// app then quits. A recording's hand-off gives up before `recorder.run`, and `saveRecording`
    /// switches to quit mode.
    @ObservationIgnored private(set) var isQuitting = false
    /// Per recording, the clipboard's change count TidyShot left after the save: the count after its
    /// file reference, or the count it found when it put nothing there. The URL replaces the
    /// clipboard after the upload only while the count still matches. In memory only, so after a
    /// relaunch the clipboard counts as changed.
    @ObservationIgnored var videoClipboardCounts: [UUID: Int] = [:]
    /// GIF conversions under way, by recording id: each one's task and its latest progress, for
    /// the status menu and `stopMakingGIFs()`. An entry goes when its conversion has saved.
    @ObservationIgnored var gifConversions: [UUID: (task: Task<Void, Never>, progress: GIFProgress)] = [:]

    // MARK: Retained capture and pins (AppCoordinator+Pins.swift)
    /// The capture just taken and its pixels, kept while its card shows, so Annotate opens the
    /// editor at once: also while the upload runs, and after an upload-only capture's pending file
    /// is gone. The card's NSImage wraps the same CGImage, so this costs no memory. Cleared when
    /// its card closes, by the next capture and by `removeRecord`. Older cards in the stack load
    /// from the file or the bucket.
    @ObservationIgnored var latestCapture: (id: UUID, image: ScaledImage)?
    /// The area the newest capture was taken from (CoreGraphics global points), so its pin opens
    /// over the spot. Kept with `latestCapture`: cleared by `save(_:intent:)`, by `forgetLatestCapture`.
    @ObservationIgnored var latestCaptureArea: (id: UUID, rect: CGRect)?
    /// Pin to screen's windows. Records whose image is loading for a pin are in `pinningIDs`.
    @ObservationIgnored lazy var pins = PinController()
    @ObservationIgnored var pinningIDs: Set<UUID> = []

    // MARK: Overlay state (AppCoordinator+Overlay.swift)
    /// Recently closed cards for Restore Closed Overlay. In memory only.
    @ObservationIgnored var closedOverlays = ClosedOverlays()
    /// True while `restoreClosedOverlay` shows its card, so the card that push-out closes goes to
    /// the back of the restore list.
    @ObservationIgnored var isRestoring = false

    // MARK: Upload state (AppCoordinator+Upload.swift)
    // +Delete's teardown clears optimizingVideoIDs, fileUploadIDs and linkNotCopiedIDs; +Overlay reads
    // the two flag sets; +Editor reads queue?.location.
    /// The queue new uploads go to, built from the destination of the first upload after launch
    /// or after the Upload tab was saved.
    @ObservationIgnored var queue: UploadLane?
    /// Queues replaced by `destinationDidChange()`, kept until they report idle. Their jobs
    /// finish against the destination they started with (their records store that location),
    /// and Delete can still cancel them.
    @ObservationIgnored var drainingQueues: [UploadLane] = []
    /// Optimize images and videos with Clop (spec 2.7): one optimiser, sending to whichever Clop
    /// build runs.
    let clopOptimiser = ClopApp.makeOptimiser()
    /// Records whose upload waits for Clop, or a recording's for its size check, each with the
    /// token of the attempt that waits. Delete's cancel takes the record out, and the upload is
    /// then never enqueued; a retry started after that gets a new token, so the first attempt's
    /// task cannot enqueue its stale bytes.
    @ObservationIgnored var optimisingIDs: [UUID: UUID] = [:]
    /// Per lane (by queue identity), the uploads still waiting for Clop or being enqueued, so a lane
    /// the Upload tab replaced is not dropped from `drainingQueues` before their jobs reach it.
    @ObservationIgnored var clopWaitsPerLane: [ObjectIdentifier: Int] = [:]
    /// Recordings whose upload waits for Clop, for the card's and the row's `Optimizing…`. Left
    /// when Clop answers, and at once on Delete, removal from history and pruning.
    var optimizingVideoIDs: Set<UUID> = []
    /// Clop's accepted movie per record, in `tmp/Clop`. The coordinator owns it: the job uploads it
    /// (the queue's own retries re-send it), and it is removed when the upload ends.
    @ObservationIgnored var clopResults: [UUID: URL] = [:]
    /// Per record, the size of what its enqueued job sends (Clop's result when it was accepted),
    /// set at the enqueue and taken when the upload ends; `.uploaded` stores it on the record
    /// (spec 2.13). No entry when the size could not be read.
    @ObservationIgnored var sentByteCounts: [UUID: Int] = [:]
    /// Records with a `.file` upload waiting for Clop, queued or in flight. The `Uploading a
    /// recording` activity is held while there is one, so idle sleep and App Nap do not stop it.
    @ObservationIgnored var fileUploadIDs: Set<UUID> = [] {
        didSet { updateUploadActivity() }
    }
    @ObservationIgnored private var uploadActivity: (any NSObjectProtocol)?
    /// Set after the first "Upload not configured" notification so later captures stay quiet.
    @ObservationIgnored var warnedUploadNotConfigured = false
    /// Set when the first same-key replace of this launch posts `EditorUploadPlan.cacheNote`.
    @ObservationIgnored var postedCacheNote = false
    /// Set when the first GIF upload of this launch, with Clop on, logs that GIFs are not sent to Clop.
    @ObservationIgnored var loggedGIFNotSentToClop = false
    /// Records with an upload in flight; drives the menu bar icon.
    var uploadingIDs: Set<UUID> = []
    /// Recordings whose URL did not replace the clipboard when the upload finished, because the
    /// clipboard had changed since the save. Their card says `Uploaded`, not `URL copied`.
    var linkNotCopiedIDs: Set<UUID> = []

    // MARK: Delete state (AppCoordinator+Delete.swift)
    /// Records whose delete is in progress (alert showing or requests running): a second click
    /// shows no second alert, and a retry does not re-enqueue them.
    @ObservationIgnored var deletingIDs: Set<UUID> = []

    // MARK: Trim state (AppCoordinator+Trim.swift)
    // +Upload and +Delete read trimmingIDs; +Delete closes trimWindows.
    /// Open Trim windows, one per record.
    @ObservationIgnored var trimWindows: [UUID: TrimWindowController] = [:]
    /// Records whose recording is downloading for a Trim window, so a second `Trim…` does not
    /// download it again.
    @ObservationIgnored var openingTrimIDs: Set<UUID> = []
    /// Each record's Trim pass, from the export through the put and its bookkeeping. `Stop` and
    /// closing the Trim window cancel it before the put, and the window's clean-up waits for it.
    @ObservationIgnored var trimPasses: [UUID: Task<Void, Never>] = [:]
    /// Records whose Trim pass runs (design, Write-time checks): from Save or Save and Upload through
    /// the put and its bookkeeping. While a record is here, Retry, `Upload Trimmed`, `startUpload` and
    /// Delete refuse it, and Retry Failed Uploads skips it.
    @ObservationIgnored var trimmingIDs: Set<UUID> = []

    // MARK: Drag-out state (AppCoordinator+DragOut.swift)
    // +RecordActions' Copy File writes dragCleanups and copyFileCounts; +Delete's prune clears copyFileCounts.
    // +Overlay's overlayDidClose and +Delete's removeRecord (through removeDragFolder) cancel downloadingDragIDs.
    /// Bumped when a record's drag folder is removed or its pending file adopted. A stage or
    /// download that started before compares it at its end and drops what it made.
    @ObservationIgnored var dragGenerations: [UUID: Int] = [:]
    /// Bumped by every `prepareDragFile` for a record. A stage hands its file to the card only
    /// while it is still the newest, so an older stage never sets a file a newer one replaced.
    @ObservationIgnored var dragStageSeqs: [UUID: Int] = [:]
    /// Drag folders waiting `dragCleanupDelay` after their card closed, or after a Copy File with
    /// no card.
    @ObservationIgnored var dragCleanups: [UUID: Task<Void, Never>] = [:]
    /// Restored cards whose drag file is downloading, so a press does not start a second GET.
    @ObservationIgnored var prefetchingDragIDs: Set<UUID> = []
    /// Recordings whose drag copy is being staged, each with its stage (design, Drag-out with a
    /// local file). One stage per record runs at a time: a press or a Copy File during it waits
    /// for it, so a large file is copied across volumes once.
    @ObservationIgnored var stagingVideoIDs: [UUID: Task<URL?, Never>] = [:]
    /// Uploaded recordings with no local file whose drag file is downloading, each with its
    /// download (design, Drag-out download). One per record: a second drag, a press and Save As…
    /// during it wait for it. Its result is the drag file, or nil.
    @ObservationIgnored var downloadingDragIDs: [UUID: Task<URL?, Never>] = [:]
    /// A failed drag-out download's resume data, with the time its request was signed. The next
    /// download takes it, and uses it while `DragDownloadRule.usesResumeData` holds. Dropped on
    /// Delete and when the card closes.
    @ObservationIgnored var dragDownloadResume: [UUID: (data: Data, signedAt: Date)] = [:]
    /// Recordings downloading for a drag-out, for the row's `Downloading`.
    var downloadingVideoIDs: Set<UUID> = []
    /// Per recording, the clipboard's change count after Copy File put a staged drag copy there.
    /// While the clipboard still has that count, the drag folder's clean-up leaves the copy and
    /// waits again; it removes the copy once the count has moved on (Gap 7).
    @ObservationIgnored var copyFileCounts: [UUID: Int] = [:]

    // MARK: Editor state (AppCoordinator+Editor.swift)
    // +Save also sets clipboardOwner when a capture goes on the clipboard; the quit, below, reads editors.
    /// Records whose editor image is loading, so a second Annotate does not open a second editor.
    @ObservationIgnored var openingEditorIDs: Set<UUID> = []
    /// What TidyShot last put on the clipboard for a capture: set when `save(_:intent:)` copies the
    /// image, by the editor's Copy, and after an edit replaced the clipboard. An edit of that
    /// capture replaces the clipboard only while the count still matches.
    @ObservationIgnored var clipboardOwner: EditorClipboard.Owner?
    /// Open annotation editors, one per record: the window in the app, a fake in the suite.
    @ObservationIgnored var editors: [UUID: any EditorPresenting] = [:]
    /// True while a save-folder observation is registered (`observeSaveFolderForEditors`).
    @ObservationIgnored var isObservingSaveFolder = false

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    // MARK: Lifecycle

    init(environment: AppEnvironment = .live()) {
        self.environment = environment
        saveLocation = environment.saveLocation
        settings = environment.settings
        credentialStore = environment.credentialStore
        notifier = environment.notifier
        overlay = environment.overlay
        clipboard = environment.clipboard
        let url = environment.historyFileURL
        // The shared settings in the app, read on each prune as before.
        let retentionSettings = environment.settings
        history = HistoryStore(fileURL: url, retentionDays: { retentionSettings.historyRetentionDays })
        thumbnails = ThumbnailStore(nextTo: url)
        pendingFiles = PendingFileStore(nextTo: url)
        multipartFiles = MultipartStore(nextTo: url)
        dragFiles = DragFileStore(temporaryDirectory: environment.temporaryDirectory)
        history.didPrune = { [weak self] records in self?.removeFiles(ofPruned: records) }
        overlay.onDidClose = { [weak self] id, reason in self?.overlayDidClose(id, reason: reason) }
        // The shown cards' Trim items follow a save folder chosen at any panel.
        saveLocation.didStoreFolder = { [weak self] in self?.refreshCardTrimStates() }
    }

    /// A coordinator log line, through the environment (`NSLog("%@", …)` in the app).
    func log(_ message: String) {
        environment.log(message)
    }

    func start() {
        // Drag copies from the last run, also after a crash.
        dragFiles.sweep()
        // A quit or crash mid-request leaves a full-size capture in tmp/Clop.
        try? FileManager.default.removeItem(at: ClopApp.workDirectory)
        // Trim's downloads and working copies: a quit does not wait for a pass, and a crash can leave one.
        try? FileManager.default.removeItem(at: RecordingTrim.directory)
        notifier.setUp()
        history.load()
        // Listed now, before any task starts, so a file written from here on is never adopted (harness
        // design 4.2): a capture, a recovery and a URL command all write after this.
        let pendingListed = pendingFiles.list()
        // Part lists and kept Clop copies with no state, or older than the lifecycle rule. No network.
        let multipartStates = Dictionary(history.records.compactMap { record in
            record.multipart.map { (record.id, $0.startedAt) }
        }, uniquingKeysWith: { first, _ in first })
        let multipartFiles = multipartFiles
        let now = environment.now
        Task.detached(priority: .utility) { multipartFiles.sweep(states: multipartStates, now: now()) }
        // Records from before 2.13 have no size; those with a local file get it from the file.
        Task { await backfillByteCounts() }
        // A recording a crash, a kill or a failed rename left in tmp/Recording is checked, not swept,
        // and a capture in pending/ that no record names is adopted, never deleted. One task, so the
        // two never interleave. tmp/Mute is listed and tmp/Recording scanned first, long before a
        // recording started now could write there, and adopting can take seconds; then pending/ is
        // adopted before any scanned file moves into it or is checked against the records.
        Task {
            let leftRecordings = await RecordingRecovery.begin(recordingDirectory: Recording.directory,
                                                               muteDirectory: MuteLog.directory)
            await adoptPendingFiles(pendingListed)
            await recoverRecordings(leftRecordings)
        }
        registerShortcuts()
        // Hide Desktop Icons stays on across launches.
        if settings.desktopIconsHidden {
            Task { await covers.show(for: .persistent) }
        }
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
        // A URL that launched the app arrived before this point and waits in the handler.
        Task { await urlCommands.ready() }
    }

    /// Spec 2.13, Old records: each record with no `byteCount` and a local file TidyShot can reach
    /// gets the file's size, `pending/` directly and the save folder under its scope, in one pass
    /// off the main actor that never reads a file. The records are written once, after the pass; a
    /// size set meanwhile by a save, an edit or an upload is kept (`FileSizes.fill`).
    private func backfillByteCounts() async {
        let items = FileSizes.backfillItems(for: history.records, pendingFolder: pendingFiles.directory,
                                            saveFolder: saveLocation.currentURL)
        guard !items.isEmpty else { return }
        let measured = await Task.detached(priority: .utility) { FileSizes.measure(items) }.value
        guard !measured.isEmpty else { return }
        history.updateAll { FileSizes.fill(&$0, from: measured) }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    // MARK: URL commands and desktop icons

    /// A `tidyshot://` URL from `AppDelegate`'s Apple-event handler, with the sending app's name
    /// when it is known. The handler holds it until `start()` has run.
    func handleURL(_ url: URL, sender: String?) {
        Task { await urlCommands.handle(url, sender: sender) }
    }

    /// The displays in `NSScreen.screens` order with CoreGraphics frames, and the one under the
    /// pointer, for a URL command's rect.
    private static func urlCommandScreens() -> URLCommandHandler.Screens {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let displays = screens.map {
            URLCommandGeometry.Display(id: $0.displayID ?? 0,
                                       frame: Geometry.cgRect(fromAppKit: $0.frame, primaryHeight: primaryHeight))
        }
        return URLCommandHandler.Screens(displays: displays,
                                         pointerIndex: screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) })
    }

    /// The status menu's Hide Desktop Icons and the `hide-desktop-icons` and `show-desktop-icons`
    /// URL commands: stores the state, then covers the desktop until turned off, or takes the
    /// persistent covers away. A capture that is covering the desktop keeps its covers until it ends.
    func setDesktopIconsHidden(_ hidden: Bool) async {
        settings.desktopIconsHidden = hidden
        if hidden {
            await covers.show(for: .persistent)
        } else {
            covers.hide(for: .persistent)
        }
    }

    /// The status menu item and `toggle-desktop-icons`.
    func toggleDesktopIconsHidden() async {
        await setDesktopIconsHidden(!settings.desktopIconsHidden)
    }

    // MARK: Shortcuts

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .allInOne) { [weak self] in
            Task { await self?.captureAllInOne() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureFullscreen) { [weak self] in
            Task { await self?.captureFullscreen() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in
            Task { await self?.captureArea() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in
            Task { await self?.captureWindow() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureScrolling) { [weak self] in
            Task { await self?.captureScrolling() }
        }
        KeyboardShortcuts.onKeyUp(for: .capturePreviousArea) { [weak self] in
            Task { await self?.capturePreviousArea() }
        }
        KeyboardShortcuts.onKeyUp(for: .selfTimer) { [weak self] in
            Task { await self?.captureSelfTimer() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureText) { [weak self] in
            Task { await self?.captureText() }
        }
        // Either record shortcut also cancels a count-in and stops a recording, whichever of the
        // two started it: each function checks the phase first.
        KeyboardShortcuts.onKeyUp(for: .recordScreen) { [weak self] in
            Task { await self?.recordScreen() }
        }
        KeyboardShortcuts.onKeyUp(for: .recordFullscreen) { [weak self] in
            Task { await self?.recordFullscreen() }
        }
        KeyboardShortcuts.onKeyUp(for: .restoreOverlay) { [weak self] in
            Task { await self?.restoreClosedOverlay() }
        }
        // Escape must never be swallowed outside a scrolling capture or a self-timer countdown
        // (a recording's count-in is one); each enables it while it runs. A recording never does.
        KeyboardShortcuts.disable(.cancelCapture)
        KeyboardShortcuts.onKeyUp(for: .cancelCapture) { [weak self] in
            // Both are no-ops unless theirs is the one running; the capture lock allows one.
            self?.selfTimer.cancel()
            self?.scrollCapture.cancel()
        }
    }

    // MARK: Upload activity (fileUploadIDs.didSet)

    /// The upload's activity, held while `fileUploadIDs` is not empty.
    private func updateUploadActivity() {
        if fileUploadIDs.isEmpty, let activity = uploadActivity {
            ProcessInfo.processInfo.endActivity(activity)
            uploadActivity = nil
        } else if !fileUploadIDs.isEmpty, uploadActivity == nil {
            uploadActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Uploading a recording")
        }
    }

    // MARK: Quit

    /// True when a quit, a log out or a restart must wait (`.terminateLater`): an editor has unsaved
    /// changes, or a count-in, a recording or a recording's save is under way.
    nonisolated static func holdsQuit(hasUnsavedEditors: Bool, recording: RecordingPhase) -> Bool {
        hasUnsavedEditors || recording != .idle
    }

    /// `holdsQuit` for the app's editors and recording, read by `applicationShouldTerminate`.
    var quitNeedsHold: Bool {
        Self.holdsQuit(hasUnsavedEditors: hasUnsavedEditors, recording: recordingPhase)
    }

    /// Quitting does not call `windowShouldClose`, so AppDelegate calls this while it holds the
    /// quit (`.terminateLater`). Each editor with unsaved changes comes forward and shows the
    /// close sheet in turn. False (Cancel, or a Save that failed) stops the quit; editors already
    /// answered stay as they are.
    func reviewEditorsBeforeQuit() async -> Bool {
        for controller in Array(editors.values) where controller.model.hasUnsavedChanges {
            guard editors[controller.model.recordID] === controller else { continue }
            controller.present()
            guard await controller.askToSaveBeforeClosing() else { return false }
        }
        return true
    }

    /// A quit, a log out or a restart, after `reviewEditorsBeforeQuit` let it go ahead (design,
    /// Quit, log out and restart): a count-in is cancelled and records nothing, a recording stops
    /// as Stop does, with the stop wait and the end rule, and its save runs in quit mode, with an
    /// open folder panel closed so the file goes to `pending/`. A GIF conversion under way stops
    /// and one not yet begun is skipped, each saving its MP4 in quit mode, so a quit never waits
    /// for a conversion. A Cancel's question is answered Save (`recorder.quit()`), as it cannot
    /// show while the quit is held. Returns once nothing is left (`recordingPhase` is `.idle`), the
    /// thumbnail of a save written, and the notices held during the count-in or the recording have
    /// reached the notification centre, so the app does not end before them; a centre that does not
    /// answer holds the quit for `quitNoticeWait` at most (R2 design, Decided 2026-10-24, 8).
    func finishRecordingForQuit() async {
        isQuitting = true
        stopMakingGIFs()
        selfTimer.cancel()
        recorder.quit()
        saveLocation.cancelFolderChoice()
        while recordingPhase != .idle {
            try? await environment.clock.sleep(for: Self.quitPollInterval)
        }
        await notifier.waitForReleasedNotices(upTo: Self.quitNoticeWait)
    }

    /// How often `finishRecordingForQuit` checks the recording phase.
    private static let quitPollInterval = Duration.milliseconds(50)
    /// The longest a quit waits for the released notices to reach the notification centre.
    private static let quitNoticeWait = Duration.seconds(1)

    // MARK: Shared by +Capture and +Recording

    /// Fetches shareable content, or shows the permission window and returns nil. With the
    /// permission granted, the failure posts under `failureTitle`: a recording's never says
    /// `Capture failed`.
    func loadContent(failureTitle: String = "Capture failed") async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            log("Shareable content failed: \(error.localizedDescription)")
            if ScreenCapturePermission.isGranted {
                notifier.notifyError("Could not list screens and windows: \(error.localizedDescription)", title: failureTitle)
            } else {
                permissionWindow.show()
            }
            return nil
        }
    }

    /// One rule for every capture (R2 design, Decided 2026-10-24, 9; R3 design, Permission): refused
    /// while another holds the capture lock, and while a record start or Settings waits on the
    /// microphone or the camera prompt, so no capture can contain the prompt and the start that asked
    /// finds the lock free once it is answered. The lock, the status menu's capture items and the URL
    /// commands read it, through `capturesRefused`.
    nonisolated static func refusesCapture(isCapturing: Bool, askingPermission: PermissionPrompt?) -> Bool {
        isCapturing || askingPermission != nil
    }

    /// `refusesCapture` for the capture lock and the open prompt now.
    var capturesRefused: Bool {
        Self.refusesCapture(isCapturing: isCapturing, askingPermission: askingPermission)
    }

    /// Why a capture is refused, for the URL handler's log (R4 design, What `record-screen` does in
    /// each phase): a recording's count-in, then the recording, then a capture holding the lock (also
    /// while idle or saving), or else the open prompt. Nil when captures run.
    nonisolated static func captureRefusal(isCapturing: Bool, askingPermission: PermissionPrompt?,
                                           recordingPhase: RecordingPhase) -> CaptureRefusal? {
        switch recordingPhase {
        case .countIn: return .recordingStarting
        case .recording: return .recordingRunning
        case .idle, .saving: break
        }
        if isCapturing { return .captureRunning }
        return askingPermission.map { .permissionPrompt($0) }
    }

    /// `captureRefusal` for the recording's phase, the capture lock and the open prompt now.
    var captureRefusal: CaptureRefusal? {
        Self.captureRefusal(isCapturing: isCapturing, askingPermission: askingPermission, recordingPhase: recordingPhase)
    }

    /// Runs `body` unless captures are refused (`capturesRefused`): a capture already runs, or the
    /// microphone or the camera prompt is open. With `coversDesktop` and Hide desktop icons while capturing on,
    /// the desktop is covered before `body` reads the shareable content, so freeze snapshots and
    /// window lists see the covers, and uncovered when it ends (spec 2.10). Capture Scrolling and
    /// Capture Text pass false. Returns whether `body` ran.
    @discardableResult
    func withCaptureLock(coversDesktop: Bool, _ body: () async -> Void) async -> Bool {
        guard !capturesRefused else { return false }
        isCapturing = true
        defer { isCapturing = false }
        guard coversDesktop, settings.hideDesktopIconsWhileCapturing else {
            await body()
            return true
        }
        await covers.show(for: .capture)
        await body()
        covers.hide(for: .capture)
        return true
    }
}

/// The URL scheme's routes are AppCoordinator's capture, overlay and desktop-icon functions (in +Capture, +Overlay and this file) and its recording entry points (in +Recording), with their own signatures.
extension AppCoordinator: URLCommandTarget {}

/// The system prompt a record start or Settings waits on (`AppCoordinator.askingPermission`), while
/// every capture is refused (`AppCoordinator.refusesCapture`).
nonisolated enum PermissionPrompt: Equatable, Sendable {
    case microphone
    case camera

    /// The prompt as log lines name it: `the <name> prompt is open`.
    var name: String {
        switch self {
        case .microphone: "microphone"
        case .camera: "camera"
        }
    }
}
