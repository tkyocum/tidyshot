import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, output, upload, and history together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    // MARK: Collaborators
    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    let history: HistoryStore
    /// `thumbnails` and `pending` folders next to `history.json`.
    let thumbnails: ThumbnailStore
    let pendingFiles: PendingFileStore
    /// Drag-out copies, `<container tmp>/Drag/<id>/` (spec 2.9).
    let dragFiles: DragFileStore
    let credentialStore: any CredentialStore = KeychainCredentialStore()
    let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    let overlay = QuickAccessController(settings: AppSettings.shared)
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
                           }),
        makeDriver: { [engine] in ScreenRecordingDriver(engine: engine) })
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
    /// From a recording's first frame until its file is handed to `saveRecording` or removed: the
    /// status item shows `record.circle` and the menu offers Stop Recording.
    var isRecording = false
    /// A recording's count-in flag: true from the selection's return (Record Fullscreen: from the
    /// free-space check) until `recorder.run` is called or the start gives up. It covers the
    /// count-in, the settle delay and the fresh content read, with the count-in on or off.
    /// `selfTimer.isRunning` cannot serve: it stays true until `run`'s capture closure returns.
    @ObservationIgnored var recordingCountIn = false
    /// Recordings between the recorder's `.keep` and `history.add` (in quit mode, until the
    /// thumbnail is written), so the phase never reads `.idle` in between.
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
    /// Records with an upload in flight; drives the menu bar icon.
    var uploadingIDs: Set<UUID> = []
    /// Recordings whose URL did not replace the clipboard when the upload finished, because the
    /// clipboard had changed since the save. Their card says `Uploaded`, not `URL copied`.
    var linkNotCopiedIDs: Set<UUID> = []

    // MARK: Delete state (AppCoordinator+Delete.swift)
    /// Records whose delete is in progress (alert showing or requests running): a second click
    /// shows no second alert, and a retry does not re-enqueue them.
    @ObservationIgnored var deletingIDs: Set<UUID> = []

    // MARK: Drag-out state (AppCoordinator+DragOut.swift)
    // +RecordActions' Copy File writes dragCleanups and copyFileCounts; +Delete's prune clears copyFileCounts.
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
    /// Open annotation editors, one per record.
    @ObservationIgnored var editors: [UUID: EditorWindowController] = [:]
    /// True while a save-folder observation is registered (`observeSaveFolderForEditors`).
    @ObservationIgnored var isObservingSaveFolder = false

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    // MARK: Lifecycle

    init() {
        let url = (try? HistoryStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: HistoryStore.fileName)
        history = HistoryStore(fileURL: url, retentionDays: { AppSettings.shared.historyRetentionDays })
        thumbnails = ThumbnailStore(nextTo: url)
        pendingFiles = PendingFileStore(nextTo: url)
        dragFiles = DragFileStore(temporaryDirectory: FileManager.default.temporaryDirectory)
        history.didPrune = { [weak self] records in self?.removeFiles(ofPruned: records) }
        overlay.onDidClose = { [weak self] id, reason in self?.overlayDidClose(id, reason: reason) }
    }

    func start() {
        // Drag copies from the last run, also after a crash.
        dragFiles.sweep()
        // A quit or crash mid-request leaves a full-size capture in tmp/Clop.
        try? FileManager.default.removeItem(at: ClopApp.workDirectory)
        notifier.setUp()
        history.load()
        // A recording a crash, a kill or a failed rename left in tmp/Recording is checked, not swept.
        // The scan lists the folder first, long before a recording started now could write there.
        Task { await recoverRecordings() }
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
    /// open folder panel closed so the file goes to `pending/`. A Cancel's question is answered
    /// Save (`recorder.quit()`), as it cannot show while the quit is held. Returns once nothing is
    /// left (`recordingPhase` is `.idle`), the thumbnail of a save written.
    func finishRecordingForQuit() async {
        isQuitting = true
        selfTimer.cancel()
        recorder.quit()
        saveLocation.cancelFolderChoice()
        while recordingPhase != .idle {
            try? await Task.sleep(for: Self.quitPollInterval)
        }
    }

    /// How often `finishRecordingForQuit` checks the recording phase.
    private static let quitPollInterval = Duration.milliseconds(50)

    // MARK: Shared by +Capture and +Recording

    /// Fetches shareable content, or shows the permission window and returns nil. With the
    /// permission granted, the failure posts under `failureTitle`: a recording's never says
    /// `Capture failed`.
    func loadContent(failureTitle: String = "Capture failed") async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            if ScreenCapturePermission.isGranted {
                notifier.notifyError("Could not list screens and windows: \(error.localizedDescription)", title: failureTitle)
            } else {
                permissionWindow.show()
            }
            return nil
        }
    }

    /// Runs `body` unless a capture already runs. With `coversDesktop` and Hide desktop icons while
    /// capturing on, the desktop is covered before `body` reads the shareable content, so freeze
    /// snapshots and window lists see the covers, and uncovered when it ends (spec 2.10). Capture
    /// Scrolling and Capture Text pass false.
    func withCaptureLock(coversDesktop: Bool, _ body: () async -> Void) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        guard coversDesktop, settings.hideDesktopIconsWhileCapturing else {
            await body()
            return
        }
        await covers.show(for: .capture)
        await body()
        covers.hide(for: .capture)
    }
}

/// The URL scheme's routes are AppCoordinator's capture, overlay and desktop-icon functions (in +Capture, +Overlay and this file), with their own signatures.
extension AppCoordinator: URLCommandTarget {}
