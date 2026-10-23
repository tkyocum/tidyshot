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
    @ObservationIgnored private lazy var scrollCapture = ScrollCaptureController(engine: engine, settings: settings)
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

    /// A `tidyshot://` URL from `AppDelegate`'s Apple-event handler, with the sending app's name
    /// when it is known. The handler holds it until `start()` has run.
    func handleURL(_ url: URL, sender: String?) {
        Task { await urlCommands.handle(url, sender: sender) }
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

    func captureFullscreen(intent: CaptureIntent = .standard) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display), excludingWindows: await cardWindows()) else { return }
            await save(result, intent: intent)
        }
    }

    func captureArea(intent: CaptureIntent = .standard) async {
        await runSelection(mode: .area, intent: intent)
    }

    func captureWindow(intent: CaptureIntent = .standard) async {
        await runSelection(mode: .window, intent: intent)
    }

    /// All-in-One (spec 2.9): one adjustable selection whose toolbar picks the capture. Opens on
    /// `preselect` (CoreGraphics global points; a URL command's rect, Task 5) or else the last
    /// area, when it is on a connected display. Capture and Window are taken while the overlay is
    /// up, with the overlay and the cards excluded, so the pointer is never in them; Fullscreen
    /// dismisses the overlay first and follows Show cursor, as Capture Fullscreen does. Each ends
    /// in `save(_:intent:)`.
    func captureAllInOne(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil,
                         fromURLCommand: Bool = false) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            // Freeze applies to Capture; the snapshots follow the cursor setting, as in area mode.
            let freeze = settings.freezeScreen ? CaptureOptions(settings: settings, duringSelection: false) : nil
            // A URL command's start rect (its own or the previous area) opens disarmed: the
            // overlay takes the key, and a Return typed meanwhile must not capture it for the sender.
            guard let choice = await selector.selectAllInOne(content: content, freeze: freeze,
                                                             preselect: preselect?.rect ?? settings.lastAreaRect?.cgRect,
                                                             armed: !fromURLCommand)
            else { return }

            let result: CaptureResult?
            switch choice {
            case .area(let rect, let display):
                result = await areaResult(rect: rect, display: display)
            case .window(let window):
                result = await capture(.window(window), duringSelection: true)
            case .fullscreen(let display):
                // As Capture Fullscreen: the overlay goes first and the pointer follows Show cursor.
                // Its windows stay excluded in case the window server has not dropped them yet; the
                // arrow replaces the crosshair the overlay set, which is not the user's pointer.
                let overlays = await selector.overlayWindows()
                selector.dismiss()
                NSCursor.arrow.set()
                result = await capture(.display(display), excludingWindows: overlays)
            case .scrolling(let rect, let display):
                // As Capture Scrolling: the covers would stay up for the whole session.
                covers.hide(for: .capture)
                await runScrolling(rect: rect, display: display, intent: intent)
                return
            case .timer(let rect, let display):
                // Every All-in-One area kind stores the previous area (spec 2.9). `runSelfTimer`
                // dismisses the overlay; the countdown ends in its own `save(_:intent:)`.
                settings.lastAreaRect = StoredRect(rect)
                await runSelfTimer(.area(rect: rect, display: display), intent: intent)
                return
            }
            selector.dismiss()
            if let result {
                await save(result, intent: intent)
            }
        }
    }

    /// Capture Scrolling: select an area or a window's frame, run the scrolling session, and save
    /// the stitched image like any capture. During a session the shortcut is Start, then Done. A URL
    /// command's rect (`preselect`) skips the selection: the session opens on it and waits for a
    /// click on Start. A URL command never reaches this during a session: the handler drops it
    /// while a capture runs.
    func captureScrolling(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil) async {
        // During a session the shortcut is Start, then Done (the lock is held meanwhile).
        if scrollCapture.isRunning {
            scrollCapture.advance()
            return
        }
        await withCaptureLock(coversDesktop: false) {
            guard let content = await loadContent() else { return }
            if let preselect {
                guard let display = content.displays.first(where: { $0.displayID == preselect.displayID }) else {
                    NSLog("%@", "Capture Scrolling: display \(preselect.displayID) is gone")
                    return
                }
                // The app is not activated and the panel is not made key: Start and Done are default
                // actions, so a Return typed in the frontmost app must not start a capture of the
                // sender's rect. Start needs a click (or the hotkey). Unstarted for
                // `ScrollCaptureSession.readyTimeout`, the session cancels itself, so a planted one
                // does not hold the capture lock and the global Escape.
                // `runScrolling` refuses a rect under 100 pt; its `dismiss()` is a no-op here.
                await runScrolling(rect: preselect.rect, display: display, intent: intent, preselected: true)
                return
            }
            guard let selection = await selector.select(mode: .scrolling, content: content) else { return }
            guard case .area(let rect, let display) = selection else {
                selector.dismiss()
                return
            }
            await runScrolling(rect: rect, display: display, intent: intent)
        }
    }

    /// A scrolling capture of an area chosen in the overlay, which is still up: refuses one under
    /// 100 pt with the Phase 5 message, stores the previous area, dismisses the overlay, runs the
    /// session and saves the stitched image like any capture. A URL command's rect (`preselected`)
    /// opens the panel without making it key, cancels itself when not started within
    /// `ScrollCaptureSession.readyTimeout`, and is stored as the previous area only when the
    /// stitched image is saved, so a cancelled session leaves Previous Area as it was.
    private func runScrolling(rect: CGRect, display: SCDisplay, intent: CaptureIntent,
                              preselected: Bool = false) async {
        guard rect.height >= CGFloat(ScrollCaptureLimits.minimumAreaHeightPoints) else {
            selector.dismiss()
            notifier.notifyError("Select an area at least 100 points tall.", title: "Scrolling capture")
            return
        }
        if !preselected {
            settings.lastAreaRect = StoredRect(rect)
        }
        selector.dismiss()
        let outcome = await scrollCapture.run(rect: rect, display: display, makesPanelKey: !preselected,
                                              readyTimeout: preselected ? ScrollCaptureSession.readyTimeout : nil)
        if let notice = outcome.failureNotice {
            notifier.notifyError(notice.body, title: notice.title)
        }
        if let image = outcome.imageToSave {
            if preselected {
                settings.lastAreaRect = StoredRect(rect)
            }
            await save(CaptureResult(image: image.image, scale: image.scale,
                                     target: .area(rect: rect, display: display)), intent: intent)
        }
    }

    /// Capture Previous Area: the last area capture's rect again, live, with no selection overlay.
    /// `PreviousArea.resolve` clips the stored rect to the display under its centre. The cards are
    /// excluded and the pointer follows Show cursor, as for a fullscreen capture. It does not
    /// write `lastAreaRect`: a clipped rect would shrink the memory.
    func capturePreviousArea(intent: CaptureIntent = .standard) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            let displays = content.displays.map { PreviousArea.Display(id: $0.displayID, frame: $0.frame) }
            switch PreviousArea.resolve(rect: settings.lastAreaRect?.cgRect, displays: displays) {
            case .none:
                notifier.notifyError("Capture an area first.", title: "No previous area")
            case .offScreen:
                notifier.notifyError("The previous area is not on a connected display.", title: "No previous area")
            case .area(let rect, let displayID):
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let cards = await cardWindows()
                guard let result = await capture(.area(rect: rect, display: display), excludingWindows: cards) else { return }
                await save(result, intent: intent)
            }
        }
    }

    /// A URL command's `capture-area` with x, y, width and height (the gate has allowed it): that
    /// rect at once, live, with no selection overlay, as Capture Previous Area captures (the cards
    /// excluded, the pointer from Show cursor). It is stored as the previous area.
    func captureArea(at area: ScreenRect, intent: CaptureIntent) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
                NSLog("%@", "URL capture-area: display \(area.displayID) is gone")
                return
            }
            let cards = await cardWindows()
            guard let result = await capture(.area(rect: area.rect, display: display), excludingWindows: cards) else { return }
            // Only a rect that was captured becomes the previous area.
            settings.lastAreaRect = StoredRect(area.rect)
            await save(result, intent: intent)
        }
    }

    /// Self-Timer: select an area or click a window, then count down and capture it live. The
    /// lock is held for the selection, the countdown and the capture.
    func captureSelfTimer(intent: CaptureIntent = .standard) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: .selfTimer, content: content) else { return }
            switch selection {
            case .area(let rect, let display):
                settings.lastAreaRect = StoredRect(rect)
                await runSelfTimer(.area(rect: rect, display: display), intent: intent)
            case .window(let window):
                await runSelfTimer(.window(window), intent: intent)
            }
        }
    }

    /// Show the overlay, capture with the overlay excluded (or cut the frozen snapshot), dismiss, then save.
    private func runSelection(mode: SelectionMode, intent: CaptureIntent) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            // Freeze applies to area mode only. The snapshots follow the cursor setting: they are
            // taken before the overlay, so the pointer in them is the real one.
            let freeze = mode == .area && settings.freezeScreen
                ? CaptureOptions(settings: settings, duringSelection: false) : nil
            guard let selection = await selector.select(mode: mode, content: content, freeze: freeze) else { return }

            let result: CaptureResult?
            switch selection {
            case .area(let rect, let display):
                result = await areaResult(rect: rect, display: display)
            case .window(let window):
                result = await capture(.window(window), duringSelection: true)
            }
            selector.dismiss()

            if let result {
                await save(result, intent: intent)
            }
        }
    }

    /// Capture Text (spec 2.10): Capture Area's overlay, with Freeze screen as there, and the image
    /// Capture Area would have taken. The lock is held for the selection and the capture only, so
    /// recognition (about 24 s the first time after a restart) never blocks another capture. It
    /// does not write `lastAreaRect`: the previous area is for image captures.
    func captureText() async {
        var captured: CaptureResult?
        await withCaptureLock(coversDesktop: false) {
            guard let content = await loadContent() else { return }
            let freeze = settings.freezeScreen ? CaptureOptions(settings: settings, duringSelection: false) : nil
            guard let selection = await selector.select(mode: .area, content: content, freeze: freeze) else { return }
            switch selection {
            case .area(let rect, let display):
                captured = await selectedAreaResult(rect: rect, display: display)
            case .window(let window):
                // Area mode never returns a window; a click without a drag cancels.
                captured = await capture(.window(window), duringSelection: true)
            }
            selector.dismiss()
        }
        if let captured {
            await copyText(in: captured.image)
        }
    }

    /// A URL command's `capture-text` with a rect (the gate has allowed it): that rect at once,
    /// live, with the cards excluded and no pointer. It does not write `lastAreaRect`.
    func captureText(at area: ScreenRect) async {
        var captured: CaptureResult?
        await withCaptureLock(coversDesktop: false) {
            guard let content = await loadContent() else { return }
            guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
                NSLog("%@", "URL capture-text: display \(area.displayID) is gone")
                return
            }
            let cards = await cardWindows()
            captured = await capture(.area(rect: area.rect, display: display), excludingWindows: cards,
                                     duringSelection: true)
        }
        if let captured {
            await copyText(in: captured.image)
        }
    }

    /// Reads the text or codes in `image` off the main actor, then puts the result on the
    /// clipboard with the capture sound and a notification, as Play sound and Show notification
    /// say. Nothing found and a Vision error are always posted, and leave the clipboard alone.
    /// No file, record, card or upload; `clipboardOwner` stays, since the change count moved.
    private func copyText(in image: CGImage) async {
        let scan: TextScan
        do {
            scan = try await TextRecognizer().recognize(image)
        } catch {
            NSLog("%@", "Text recognition failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Text not recognized")
            return
        }
        let outcome = TextCaptureOutcome.decide(scan)
        guard let text = outcome.clipboard else {
            notifier.notifyError(outcome.body, title: outcome.title)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if settings.playSound {
            SoundPlayer.playShutter()
        }
        if settings.showNotification {
            notifier.notify(title: outcome.title, body: outcome.body, openURL: outcome.openURL)
        }
    }

    /// The countdown and the capture behind Self-Timer and All-in-One's Timer button. Call it with
    /// the capture lock held. The selection overlay goes first, then TidyShot gives up activation
    /// so the user's app is frontmost while the badge counts: its menus open and its keys work.
    /// A countdown that is cancelled leaves nothing behind.
    private func runSelfTimer(_ target: CaptureTarget, intent: CaptureIntent) async {
        selector.dismiss()
        NSApplication.shared.deactivate()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let screenFrame = CaptureEngine.screen(forDisplayID: target.displayID)?.frame ?? NSScreen.main?.frame else { return }
        let stage = SelfTimerScreenStage(subject: Geometry.appKitRect(fromCG: target.cgFrame, primaryHeight: primaryHeight),
                                         screenFrame: screenFrame)
        _ = await selfTimer.run(seconds: settings.selfTimerSeconds, stage: stage) { [self] in
            await captureAfterCountdown(target, intent: intent)
        }
    }

    /// The live capture once the panels are gone. The shareable content is read again, and the
    /// display or window is found in it by id: a window may have moved or closed during the
    /// countdown, and an `SCWindow` from before would size the image from its old frame. The
    /// pointer follows Show cursor and the cards are left out, as for a fullscreen capture.
    private func captureAfterCountdown(_ target: CaptureTarget, intent: CaptureIntent) async {
        guard let content = await loadContent() else { return }
        let fresh: CaptureTarget
        switch target {
        case .display(let display):
            guard let current = content.displays.first(where: { $0.displayID == display.displayID }) else {
                notifier.notifyError("The display is no longer connected.", title: "Self-timer")
                return
            }
            fresh = .display(current)
        case .area(let rect, let display):
            guard let current = content.displays.first(where: { $0.displayID == display.displayID }) else {
                notifier.notifyError("The display is no longer connected.", title: "Self-timer")
                return
            }
            fresh = .area(rect: rect, display: current)
        case .window(let window):
            guard let current = content.windows.first(where: { $0.windowID == window.windowID }) else {
                notifier.notifyError("The window is no longer on screen.", title: "Self-timer")
                return
            }
            fresh = .window(current)
        }
        guard let result = await capture(fresh, excludingWindows: await cardWindows()) else { return }
        await save(result, intent: intent)
    }

    /// An area chosen in the overlay, which is still up: stores it as the previous area, then cuts
    /// it from the frozen snapshot or captures it live with the overlay and the cards excluded.
    private func areaResult(rect: CGRect, display: SCDisplay) async -> CaptureResult? {
        settings.lastAreaRect = StoredRect(rect)
        return await selectedAreaResult(rect: rect, display: display)
    }

    /// An area chosen in the overlay, which is still up, cut from the frozen snapshot or captured
    /// live with the overlay and the cards excluded. Stores nothing.
    private func selectedAreaResult(rect: CGRect, display: SCDisplay) async -> CaptureResult? {
        if let frozen = frozenResult(for: rect, display: display) {
            return frozen
        }
        let overlays = await selector.overlayWindows()
        return await capture(.area(rect: rect, display: display), excludingWindows: overlays, duringSelection: true)
    }

    /// The selection cut from the display's frozen snapshot, or nil when there is none (freeze off,
    /// or that display's snapshot failed) or the crop failed; the caller then captures live.
    private func frozenResult(for rect: CGRect, display: SCDisplay) -> CaptureResult? {
        guard let frozen = selector.frozenCapture(for: display.displayID) else { return nil }
        guard let image = FreezeCrop.cropped(frozen.image, selection: rect, displayFrame: display.frame,
                                             scale: frozen.scale) else {
            NSLog("Freeze crop failed for \(rect) on display \(display.displayID); capturing live")
            return nil
        }
        return CaptureResult(image: image, scale: frozen.scale, target: .area(rect: rect, display: display))
    }

    func revealLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    /// Runs the engine. On failure posts a notification and returns nil. `duringSelection` is
    /// true for the live captures taken while the selection overlay is still up; the pointer is
    /// then never captured (`CaptureOptions.init(settings:duringSelection:)`).
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = [],
                 duringSelection: Bool = false) async -> CaptureResult? {
        do {
            let options = CaptureOptions(settings: settings, duringSelection: duringSelection)
            return try await engine.capture(target, options: options, excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return nil
        }
    }

    /// The upload's activity, held while `fileUploadIDs` is not empty.
    private func updateUploadActivity() {
        if fileUploadIDs.isEmpty, let activity = uploadActivity {
            ProcessInfo.processInfo.endActivity(activity)
            uploadActivity = nil
        } else if !fileUploadIDs.isEmpty, uploadActivity == nil {
            uploadActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Uploading a recording")
        }
    }

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

    // MARK: Helpers

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

    /// The Quick Access cards as ScreenCaptureKit sees them, for a capture taken without the
    /// selection overlay; no lookup when no card shows.
    private func cardWindows() async -> [SCWindow] {
        let numbers = overlay.windowNumbers
        guard !numbers.isEmpty else { return [] }
        return await OverlayWindowLookup.windows(numbers: numbers, engine: engine)
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

    /// The SCDisplay under an AppKit-global point, falling back to the first display.
    static func display(under appKitPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = Geometry.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
        return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
    }
}

/// The URL scheme's routes are the capture functions above, with their own signatures.
extension AppCoordinator: URLCommandTarget {}
