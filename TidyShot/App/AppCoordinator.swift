import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, output, upload, and history together.
@Observable
final class AppCoordinator {
    /// An upload queue and where its destination writes. Upload events carry no destination, so
    /// the location travels with the queue and is stored on the records it uploads.
    private struct UploadLane {
        let queue: UploadQueue
        let location: ObjectLocation
        let keyTemplate: String
    }

    static let shared = AppCoordinator()

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
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    private let overlay = QuickAccessController(settings: AppSettings.shared)
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine, settings: settings, cardWindowNumbers: { [weak self] in self?.overlay.windowNumbers ?? [] })
    @ObservationIgnored private lazy var scrollCapture = ScrollCaptureController(engine: engine, settings: settings)
    /// `tidyshot://` commands (spec 2.9): held until `start()` has run, then parsed, gated and
    /// routed to the capture functions. It holds this coordinator weakly.
    @ObservationIgnored private lazy var urlCommands = URLCommandHandler(
        settings: settings, target: self, screens: { AppCoordinator.urlCommandScreens() },
        post: { [weak self] notice in
            self?.notifier.notifyError(notice.body, title: notice.title, subtitle: notice.subtitle)
        })
    @ObservationIgnored private lazy var selfTimer = SelfTimerController()
    /// Thumbnails and previews for Recent Captures.
    @ObservationIgnored private(set) lazy var thumbnailProvider = ThumbnailProvider(
        store: thumbnails, history: history, saveFolder: { [unowned self] in self.saveLocation.currentURL },
        readFile: { fileURL, folder in
            // Runs in a detached task. A temporary file in `pending` needs no scope.
            guard let folder else { return try Data(contentsOf: fileURL) }
            return try SaveLocation.readScoped(fileURL, folder: folder)
        })
    /// The queue new uploads go to, built from the destination of the first upload after launch
    /// or after the Upload tab was saved.
    @ObservationIgnored private var queue: UploadLane?
    /// Queues replaced by `destinationDidChange()`, kept until they report idle. Their jobs
    /// finish against the destination they started with (their records store that location),
    /// and Delete can still cancel them.
    @ObservationIgnored private var drainingQueues: [UploadLane] = []
    /// Optimize images with Clop (spec 2.7): one optimiser, sending to whichever Clop build runs.
    private let clopOptimiser = ClopApp.makeOptimiser()
    /// Records whose upload waits for Clop. Delete's cancel takes the id out, and the upload is
    /// then never enqueued.
    @ObservationIgnored private var optimisingIDs: Set<UUID> = []
    /// Per lane (by queue identity), the uploads still waiting for Clop or being enqueued, so a lane
    /// the Upload tab replaced is not dropped from `drainingQueues` before their jobs reach it.
    @ObservationIgnored private var clopWaitsPerLane: [ObjectIdentifier: Int] = [:]
    /// Records whose delete is in progress (alert showing or requests running): a second click
    /// shows no second alert, and a retry does not re-enqueue them.
    @ObservationIgnored private var deletingIDs: Set<UUID> = []
    /// Set after the first "Upload not configured" notification so later captures stay quiet.
    @ObservationIgnored private var warnedUploadNotConfigured = false
    /// The capture just taken and its pixels, kept while its card shows, so Annotate opens the
    /// editor at once: also while the upload runs, and after an upload-only capture's pending file
    /// is gone. The card's NSImage wraps the same CGImage, so this costs no memory. Cleared when
    /// its card closes, by the next capture and by `removeRecord`. Older cards in the stack load
    /// from the file or the bucket.
    @ObservationIgnored private var latestCapture: (id: UUID, image: ScaledImage)?
    /// The area the newest capture was taken from (CoreGraphics global points), so its pin opens
    /// over the spot. Kept with `latestCapture`: cleared by `save(_:intent:)`, by `forgetLatestCapture`.
    @ObservationIgnored private var latestCaptureArea: (id: UUID, rect: CGRect)?
    /// Pin to screen's windows. Records whose image is loading for a pin are in `pinningIDs`.
    @ObservationIgnored private lazy var pins = PinController()
    @ObservationIgnored private var pinningIDs: Set<UUID> = []
    /// Recently closed cards for Restore Closed Overlay. In memory only.
    @ObservationIgnored private var closedOverlays = ClosedOverlays()
    /// True while `restoreClosedOverlay` shows its card, so the card that push-out closes goes to
    /// the back of the restore list.
    @ObservationIgnored private var isRestoring = false
    /// Records whose editor image is loading, so a second Annotate does not open a second editor.
    @ObservationIgnored private var openingEditorIDs: Set<UUID> = []
    /// Set when the first same-key replace of this launch posts `EditorUploadPlan.cacheNote`.
    @ObservationIgnored private var postedCacheNote = false
    /// What TidyShot last put on the clipboard for a capture: set when `save(_:intent:)` copies the
    /// image, by the editor's Copy, and after an edit replaced the clipboard. An edit of that
    /// capture replaces the clipboard only while the count still matches.
    @ObservationIgnored private var clipboardOwner: EditorClipboard.Owner?
    /// Bumped when a record's drag folder is removed or its pending file adopted. A stage or
    /// download that started before compares it at its end and drops what it made.
    @ObservationIgnored private var dragGenerations: [UUID: Int] = [:]
    /// Bumped by every `prepareDragFile` for a record. A stage hands its file to the card only
    /// while it is still the newest, so an older stage never sets a file a newer one replaced.
    @ObservationIgnored private var dragStageSeqs: [UUID: Int] = [:]
    /// Drag folders waiting `dragCleanupDelay` after their card closed.
    @ObservationIgnored private var dragCleanups: [UUID: Task<Void, Never>] = [:]
    /// Restored cards whose drag file is downloading, so a press does not start a second GET.
    @ObservationIgnored private var prefetchingDragIDs: Set<UUID> = []

    private(set) var isCapturing = false
    /// The last capture written to the save folder (upload-only captures do not count).
    private(set) var lastCaptureURL: URL?
    /// Records with an upload in flight; drives the menu bar icon.
    private(set) var uploadingIDs: Set<UUID> = []

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }
    var isUploading: Bool { !uploadingIDs.isEmpty }
    /// The record whose image is retained, for the Annotate flag on Recent Captures rows.
    var retainedCaptureID: UUID? { latestCapture?.id }

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
        notifier.setUp()
        history.load()
        registerShortcuts()
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
        KeyboardShortcuts.onKeyUp(for: .restoreOverlay) { [weak self] in
            Task { await self?.restoreClosedOverlay() }
        }
        // Escape must never be swallowed outside a scrolling capture or a self-timer countdown;
        // each enables it while it runs.
        KeyboardShortcuts.disable(.cancelCapture)
        KeyboardShortcuts.onKeyUp(for: .cancelCapture) { [weak self] in
            // Both are no-ops unless theirs is the one running; the capture lock allows one.
            self?.selfTimer.cancel()
            self?.scrollCapture.cancel()
        }
    }

    func captureFullscreen(intent: CaptureIntent = .standard) async {
        await withCaptureLock {
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
        await withCaptureLock {
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
        await withCaptureLock {
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
        await withCaptureLock {
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
        await withCaptureLock {
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
        await withCaptureLock {
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
        await withCaptureLock {
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

    // MARK: Save and upload

    /// Encode, copy to clipboard (image now, or URL later), then `persist`: write the file, record
    /// in history, start the thumbnail, show the overlay, and start the upload. A file is always
    /// written before the upload starts; if it cannot be written the image stays on the clipboard,
    /// so a capture is never dropped. When the image goes on the clipboard, `clipboardOwner`
    /// records it for this capture, so an edit can replace it later. The PNG, and the TIFF when the
    /// image goes on the clipboard now, are made in a detached task, so a tall capture does not hold
    /// up the main actor. The intent's action replaces the General one; `copyOnly` leaves after
    /// `copyOnly(_:sender:)`; `then` opens the editor or a pin on the new record. Returns the
    /// record, or nil when nothing was recorded.
    @discardableResult
    func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord? {
        if intent.copyOnly {
            await copyOnly(result, sender: intent.sender)
            return nil
        }
        latestCapture = nil
        latestCaptureArea = nil
        let image = result.scaled
        let action = intent.action
        // One keychain read per capture; persist passes the result to startUpload.
        let destination = action.uploads ? makeDestination() : nil
        let copyImageNow: Bool
        if destination != nil {
            copyImageNow = settings.alsoCopyImageWhenUploading
        } else if action.uploads {
            // Upload wanted but not possible: the clipboard gets the image instead of a URL.
            copyImageNow = true
        } else {
            copyImageNow = settings.copyImageToClipboard
        }
        // A scrolling capture can be 65,536 px tall: encode it, and the clipboard's TIFF, off the
        // main actor. Every capture takes this path; for a normal one the cost is one hop. Above
        // 16,384 px the clipboard gets the PNG only (`Pasteboard.companionTIFF`).
        let encoded: (png: Data, tiff: Data?)
        do {
            encoded = try await Task.detached(priority: .userInitiated) { () throws -> (png: Data, tiff: Data?) in
                (try ImageEncoder.pngData(from: image.image, scale: image.scale),
                 copyImageNow ? Pasteboard.companionTIFF(of: image.image, scale: image.scale) : nil)
            }.value
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            // Never drop a capture: without PNG data the clipboard still gets the image as TIFF.
            let tiff = await Task.detached(priority: .userInitiated) {
                Pasteboard.tiffData(of: image.image, scale: image.scale)
            }.value
            Pasteboard.copy(tiffData: tiff)
            notifier.notifyError(error.localizedDescription)
            return nil
        }
        let png = encoded.png
        let copiedChangeCount: Int? = copyImageNow ? Pasteboard.copy(pngData: png, tiffData: encoded.tiff) : nil

        guard let record = await persist(png: png, image: image, action: action, destination: destination,
                                         alreadyOnClipboard: copyImageNow,
                                         captureDisplayID: result.target.displayID) else { return nil }
        // Before anything below, so a pin of this record opens over the spot it came from.
        latestCaptureArea = result.target.areaRect.map { (id: record.id, rect: $0) }
        if let copiedChangeCount {
            clipboardOwner = EditorClipboard.Owner(recordID: record.id, changeCount: copiedChangeCount)
        }
        switch intent.then {
        case .none: break
        case .annotate: openEditor(recordID: record.id)
        case .pin: await pin(recordID: record.id)
        }
        return record
    }

    /// `action=copy` (spec 2.9, URL scheme, Actions): the image goes on the clipboard and nothing
    /// else happens: no file, no record, no thumbnail, no card, no upload. The shutter sound follows
    /// Play sound, so no capture happens unheard, and `Image copied` is posted when notifications
    /// are on, naming the sending app. `latestCapture` and `clipboardOwner` stay: the newest card
    /// still owns its image, and an edit of an earlier capture compares the clipboard's change
    /// count, which this copy has moved on.
    private func copyOnly(_ result: CaptureResult, sender: String?) async {
        let image = result.scaled
        let encoded = await Task.detached(priority: .userInitiated) { () -> (png: Data?, tiff: Data?) in
            (try? ImageEncoder.pngData(from: image.image, scale: image.scale),
             Pasteboard.companionTIFF(of: image.image, scale: image.scale))
        }.value
        if let png = encoded.png {
            Pasteboard.copy(pngData: png, tiffData: encoded.tiff)
        } else {
            // As `save` does when the PNG fails: the TIFF alone, so the capture is not lost.
            let tiff = await Task.detached(priority: .userInitiated) {
                Pasteboard.tiffData(of: image.image, scale: image.scale)
            }.value
            Pasteboard.copy(tiffData: tiff)
        }
        if settings.playSound {
            SoundPlayer.playShutter()
        }
        if settings.showNotification {
            notifier.notify(title: "Image copied", body: "\(image.image.width) × \(image.image.height) px",
                            subtitle: sender.map { "From \($0)" })
        }
    }

    /// The capture save path behind `save(_:intent:)`. Writes the file (save folder, or the container's
    /// `pending` folder in upload-only mode), warns once when upload is not configured, plays the
    /// sound, records the capture, starts the thumbnail, shows the overlay, and starts the upload
    /// or posts "saved". Returns nil when the file could not be written; the writer has then
    /// notified and left the image on the clipboard (`alreadyOnClipboard` says it is there
    /// already). Any other clipboard write is the caller's.
    private func persist(png: Data, image: ScaledImage, action: AfterCaptureAction, destination: S3Destination?,
                         alreadyOnClipboard: Bool, captureDisplayID: CGDirectDisplayID) async -> CaptureRecord? {
        // The object key is not named here: `startUpload` names it when the upload starts.
        let id = UUID()
        let fileURL: URL
        if action == .uploadOnly {
            guard let url = writePendingFile(png, id: id, image: image,
                                             alreadyOnClipboard: alreadyOnClipboard) else { return nil }
            fileURL = url
        } else {
            guard let url = await writeFile(png, image: image, alreadyOnClipboard: alreadyOnClipboard) else { return nil }
            fileURL = url
            lastCaptureURL = url
        }
        if action.uploads, destination == nil {
            warnUploadNotConfiguredOnce(action == .uploadOnly
                ? "Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard."
                : "Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard.")
        }
        if settings.playSound {
            SoundPlayer.playShutter()
        }

        let state: CaptureRecord.UploadState
        if destination != nil {
            state = .uploading(fraction: 0)
        } else if action == .uploadOnly {
            // Nowhere to upload to yet; the pending file stays until a retry succeeds.
            state = .failed(message: UploadError.notConfigured.localizedDescription)
        } else {
            state = .none
        }
        // The source app is no longer recorded (Phase 3.1 removed its token); older records keep theirs.
        let record = CaptureRecord(id: id, fileURL: fileURL, fileIsTemporary: action == .uploadOnly,
                                   pixelWidth: image.image.width, pixelHeight: image.image.height,
                                   appName: nil, uploadState: state)
        history.add(record)
        makeThumbnail(from: image.image, for: id)
        showOverlay(for: record, image: image.image, scale: image.scale, captureDisplayID: captureDisplayID)

        if let destination {
            startUpload(recordID: record.id, data: png, destination: destination)
        } else if action != .uploadOnly, settings.showNotification {
            // Save mode, or upload mode with no destination (as in Phase 2): the file was saved.
            notifier.notifySaved(fileURL: fileURL)
        }
        return record
    }

    /// Posts "Upload not configured" the first time per launch only. With the default
    /// after-capture action set to upload, a user without a destination would otherwise get a
    /// notification for every capture.
    private func warnUploadNotConfiguredOnce(_ message: String) {
        guard !warnedUploadNotConfigured else { return }
        warnedUploadNotConfigured = true
        notifier.notifyError(message, title: "Upload not configured")
    }

    /// Writes the PNG into the save folder under a name from the file name template, with
    /// `{counter}` drawn as Phase 1 did. Returns nil after notifying, with the image left on the
    /// clipboard, when there is no folder or the write fails.
    private func writeFile(_ png: Data, image: ScaledImage, alreadyOnClipboard: Bool) async -> URL? {
        guard let folder = await saveLocation.ensureFolder() else {
            keepOnClipboard(image, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("No folder was chosen. The image is on the clipboard.", title: "Not saved")
            return nil
        }
        do {
            let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let name = FileNamer(template: settings.fileNameTemplate).name(counter: counter)
            return try saveLocation.write(png, baseName: name, ext: "png", in: folder)
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            keepOnClipboard(image, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    /// Upload-only mode: writes the PNG into the container's `pending` folder as `<id>.png`, no
    /// folder prompt.
    private func writePendingFile(_ png: Data, id: UUID, image: ScaledImage, alreadyOnClipboard: Bool) -> URL? {
        do {
            return try pendingFiles.write(png, id: id, ext: "png")
        } catch {
            NSLog("Pending write failed: \(error.localizedDescription)")
            keepOnClipboard(image, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    /// A failed write's fallback, so a capture or an edit is never dropped. It sets no
    /// `clipboardOwner`: no record was made for this image.
    private func keepOnClipboard(_ image: ScaledImage, png: Data, alreadyOnClipboard: Bool) {
        if !alreadyOnClipboard {
            Pasteboard.copy(image: image.image, pngData: png, scale: image.scale)
        }
    }

    /// Makes and writes the 320 px thumbnail on a detached task, off the main actor, and stores
    /// its file name on the record when that finishes. Until then `ThumbnailProvider` makes one
    /// from the file itself; a failure is logged and it falls back the same way. If the record was
    /// deleted in the meantime, or an edit was saved since, the new file is removed again.
    private func makeThumbnail(from image: CGImage, for id: UUID) {
        let store = thumbnails
        Task { [weak self] in
            let name = await Task.detached(priority: .utility) { () -> String? in
                do {
                    guard let small = ThumbnailMaker.thumbnail(from: image) else { return nil }
                    return try store.write(try ThumbnailMaker.pngData(small), id: id)
                } catch {
                    NSLog("Thumbnail failed: \(error.localizedDescription)")
                    return nil
                }
            }.value
            guard let name else { return }
            // Deleted meanwhile, or edited already: an edit names its own thumbnail
            // (`replaceThumbnail`), and this one shows the original.
            guard let self, let record = self.history.record(id: id), record.editedAt == nil else {
                store.remove(fileName: name)
                return
            }
            self.history.update(id: id) { $0.thumbnailFileName = name }
        }
    }

    private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat, captureDisplayID: CGDirectDisplayID) {
        guard settings.showOverlay, let screen = overlayScreen(captureDisplayID: captureDisplayID) else { return }
        // The well shows the top of a tall capture, as its thumbnail does. The crop shares the pixels.
        let shown = image.map { full in
            full.cropping(to: ThumbnailMaker.cropForThumbnail(CGSize(width: full.width, height: full.height))) ?? full
        }
        let thumbnail = shown.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
        overlay.show(record: record, thumbnail: thumbnail, screen: screen,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds, actions: overlayActions())
        // After `show`: a card it pushed out of the stack has already reported its capture.
        latestCapture = image.map { (id: record.id, image: ScaledImage(image: $0, scale: scale)) }
    }

    /// Every card's buttons. Shared by new captures' cards and restored ones (Task 4).
    private func overlayActions() -> QuickAccessController.Actions {
        QuickAccessController.Actions(
            copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
            retry: { [weak self] id in self?.retryUpload(recordID: id) },
            reveal: { [weak self] id in self?.reveal(recordID: id) },
            delete: { [weak self] id in self?.afterMenuTracking { Task { await self?.deleteCapture(recordID: id) } } },
            annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) },
            pin: { [weak self] id in self?.afterMenuTracking { Task { await self?.pin(recordID: id) } } },
            saveAs: { [weak self] id in self?.saveAs(recordID: id) },
            copyImage: { [weak self] id in self?.afterMenuTracking { Task { await self?.copyImage(recordID: id) } } },
            prepareDrag: { [weak self] id in self?.prepareDragFile(recordID: id) },
            dragEnded: { [weak self] id, accepted in self?.dragDidEnd(recordID: id, accepted: accepted) })
    }

    /// The screen for the card stack under `settings.overlayDisplay`; nil without screens.
    private func overlayScreen(captureDisplayID: CGDirectDisplayID?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let pointer = screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) }
        let index = OverlayScreenChoice.index(choice: settings.overlayDisplay, captureDisplayID: captureDisplayID,
                                              pointerIndex: pointer, screenDisplayIDs: screens.map { $0.displayID ?? 0 })
        return screens[index]
    }

    /// Every card close: the retained image goes with the newest card, a restorable close is
    /// remembered, and the card's drag folder is scheduled for removal.
    private func overlayDidClose(_ id: UUID, reason: QuickAccessCloseReason) {
        forgetLatestCapture(id)
        if isRestoring, reason == .pushedOut {
            closedOverlays.didCloseBehind(id)
        } else {
            closedOverlays.didClose(id, reason: reason)
        }
        scheduleDragCleanup(id)
    }

    /// Whether Restore Closed Overlay has a card to bring back (the menu item's state).
    var canRestoreClosedOverlay: Bool {
        closedOverlays.hasRestorable(exists: { history.record(id: $0) != nil }, shown: Set(overlay.shownIDs).union(deletingIDs))
    }

    /// Restore Closed Overlay: the newest closed card whose capture still exists and is not
    /// showing, again at the corner of the stack's screen, with the record as it is now and its
    /// stored thumbnail. Annotate on it loads from the file or the bucket. It does not check
    /// `settings.showOverlay`: it is an explicit request.
    func restoreClosedOverlay() async {
        guard let id = closedOverlays.popRestorable(exists: { history.record(id: $0) != nil },
                                                    shown: Set(overlay.shownIDs).union(deletingIDs)),
              let record = history.record(id: id) else { return }
        let thumbnail = await thumbnailProvider.thumbnail(for: record)
        // Deleted (or being deleted) during the read, or shown by a second restore meanwhile.
        guard let current = history.record(id: id), !deletingIDs.contains(id), !overlay.isShowing(recordID: id),
              let screen = overlay.screen ?? overlayScreen(captureDisplayID: nil) else { return }
        isRestoring = true
        defer { isRestoring = false }
        overlay.show(record: current, thumbnail: thumbnail, screen: screen,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds, actions: overlayActions())
        // A record without a local file starts its quiet download now.
        prepareDragFile(recordID: id)
    }

    /// The configured destination, or nil when the Upload tab is incomplete, no credentials are
    /// stored, or the keychain could not be read. "No item" is the normal not-configured case and
    /// stays silent here; any other keychain error is logged and reported once per launch.
    func makeDestination() -> S3Destination? {
        guard let config = settings.s3Config, config.isComplete, let credentials = loadCredentials() else { return nil }
        return S3Destination(config: config, credentials: credentials)
    }

    /// The stored credentials, or nil when there are none or the keychain could not be read
    /// (logged and reported once per launch).
    private func loadCredentials() -> AWSCredentials? {
        do {
            return try storedCredentials()
        } catch {
            NSLog("Keychain read failed: \(error.localizedDescription)")
            warnUploadNotConfiguredOnce(Self.keychainReadFailure(error))
            return nil
        }
    }

    /// The credentials in the Keychain, or nil when none (or only blank ones) are stored. Throws
    /// when the Keychain read itself fails, so a caller can tell that apart from "none saved".
    private func storedCredentials() throws -> AWSCredentials? {
        guard let credentials = try credentialStore.load(account: KeychainCredentialStore.defaultAccount),
              !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            return nil
        }
        return credentials
    }

    private static func keychainReadFailure(_ error: any Error) -> String {
        "Could not read S3 credentials from the keychain: \(error.localizedDescription)"
    }

    /// Called by the Upload settings tab after saving or forgetting credentials, so the next
    /// upload builds a queue from the new settings. The old queue is not dropped while it has
    /// work: it moves to `drainingQueues` until it reports idle, so its jobs still deliver their
    /// events (and finish against the destination they started with) and Delete can cancel them.
    func destinationDidChange() {
        guard let old = queue else { return }
        queue = nil
        drainingQueues.append(old)
        Task { [weak self] in
            // An upload still waiting for Clop has no job in the queue yet, so the queue can look
            // idle while one is coming. No new wait starts on a replaced lane.
            while true {
                if (self?.clopWaitsPerLane[ObjectIdentifier(old.queue)] ?? 0) == 0, await old.queue.isIdle { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            self?.drainingQueues.removeAll { $0.queue === old.queue }
        }
    }

    /// A queue for `destination` whose events are handled with the location they upload to.
    private func makeLane(for destination: S3Destination) -> UploadLane {
        let location = ObjectLocation(config: destination.config)
        let keyTemplate = destination.config.keyTemplate
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: keyTemplate),
                                events: { [weak self] event in self?.handle(event, at: location) })
        return UploadLane(queue: queue, location: location, keyTemplate: keyTemplate)
    }

    /// Enqueues `data` for `recordID`. `destination` is only used when the queue has to be
    /// created (first upload, or after the Upload tab was saved); callers read it once. With
    /// `fixedKey` the job PUTs that exact key with `Cache-Control: no-cache` and draws no counter
    /// (an editor replace, or a retry of one); otherwise the key is named from the template.
    private func startUpload(recordID: UUID, data: Data, destination: S3Destination, fixedKey: String? = nil) {
        // Look the record up before marking it uploading, so a missing record never leaves an
        // id in `uploadingIDs` (and the menu bar icon spinning) with no job to clear it.
        guard let record = history.record(id: recordID) else { return }
        let lane = queue ?? makeLane(for: destination)
        queue = lane
        uploadingIDs.insert(recordID)
        // `save` and `editorUpload` mark their records uploading and refresh the overlay
        // themselves, so only a retry (a record in another state) needs the write and the refresh.
        if !record.isUploading {
            history.update(id: recordID) { $0.uploadState = .uploading(fraction: 0) }
            refreshOverlay(for: recordID)
        }
        // The key is named now, not at capture time: a capture taken while no destination was
        // set up, and every retry, get a counter drawn when their upload starts. The date stays
        // the capture's own, so a retried upload lands in the capture's date folder. Drawn before
        // Clop runs, so counters follow the order uploads start.
        let makeJob: (Data) -> UploadJob
        if let fixedKey {
            makeJob = { UploadJob(id: recordID, data: $0, contentType: "image/png", fileExtension: "png",
                                  fixedKey: fixedKey, cacheControl: "no-cache") }
        } else {
            let counter = lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let naming = TemplateContext(date: record.timestamp, counter: counter)
            makeJob = { UploadJob(id: recordID, data: $0, contentType: "image/png", fileExtension: "png",
                                  naming: naming) }
        }
        guard settings.optimiseWithClop, clopIsRunning() else {
            Task { await lane.queue.enqueue(makeJob(data)) }
            return
        }
        // Clop rewrites a throwaway copy: the save-folder file, the pending file and the editor's
        // file stay as captured, so a Retry optimises the original again. The record stays
        // `.uploading(fraction: 0)` meanwhile.
        optimisingIDs.insert(recordID)
        let laneID = ObjectIdentifier(lane.queue)
        clopWaitsPerLane[laneID, default: 0] += 1
        Task {
            defer {
                clopWaitsPerLane[laneID, default: 1] -= 1
                if clopWaitsPerLane[laneID] == 0 { clopWaitsPerLane[laneID] = nil }
            }
            let bytes = await optimisedForUpload(data)
            // Delete cancelled the upload while Clop ran (`cancelUpload` did the bookkeeping).
            guard optimisingIDs.remove(recordID) != nil else { return }
            guard history.record(id: recordID) != nil else {
                // Removed from history meanwhile: nothing would point at the object.
                uploadingIDs.remove(recordID)
                return
            }
            await lane.queue.enqueue(makeJob(bytes))
        }
    }

    /// True when a Clop build is running. Otherwise logs why the original uploads (spec 2.7).
    private func clopIsRunning() -> Bool {
        guard ClopApp.runningBundleID() != nil else {
            NSLog("%@", "Clop: \(ClopSkipReason.notRunning.summary), uploading the original")
            return false
        }
        return true
    }

    /// Clop's smaller PNG, or `data` itself with one `Clop: ` log line saying why. Never fails and
    /// never posts an error: a capture is never lost to Clop (spec 2.7).
    private func optimisedForUpload(_ data: Data) async -> Data {
        switch await clopOptimiser.optimisedPNG(data) {
        case .optimised(let bytes, _, _):
            return bytes
        case .original(let reason):
            NSLog("%@", "Clop: \(reason.summary), uploading the original")
            return data
        }
    }

    /// Re-reads the file and uploads it again.
    func retryUpload(recordID: UUID) {
        // Ignore a second click while the record is already in flight; otherwise it would upload twice.
        guard history.record(id: recordID) != nil, !uploadingIDs.contains(recordID), !deletingIDs.contains(recordID) else { return }
        guard let destination = makeDestination() else {
            markFailed(recordID, message: UploadError.notConfigured.localizedDescription)
            return
        }
        retry(recordID: recordID, destination: destination)
    }

    /// Retries every failed upload with one keychain read. Without a destination, posts one
    /// notification instead of one per record.
    func retryFailedUploads() {
        let failed = history.failedRecords.filter { !deletingIDs.contains($0.id) }
        guard !failed.isEmpty else { return }
        guard let destination = makeDestination() else {
            notifier.notifyError("Set up a destination in Settings > Upload, then retry.", title: "Upload not configured")
            return
        }
        for record in failed {
            retry(recordID: record.id, destination: destination)
        }
    }

    /// Reads the record's file and starts its upload with `destination`. A record whose delete
    /// is in progress is never re-enqueued, so a retry cannot re-upload what Delete is removing.
    /// An interrupted or failed replace re-PUTs its own key, so its URL stays.
    private func retry(recordID: UUID, destination: S3Destination) {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        let data: Data
        do {
            data = try readLocalFile(of: record)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL?.lastPathComponent ?? "no local file").localizedDescription)
            return
        }
        // The location the lane writes to: the same expression `startUpload` uses for its lane.
        let location = queue?.location ?? ObjectLocation(config: destination.config)
        let policy = EditorUploadPlan.retryPolicy(record: record, currentLocation: location,
                                                  others: history.records.filter { $0.id != recordID })
        let started = EditorUploadPlan.startingRetry(record, policy: policy)
        if started != record {
            history.update(id: recordID) { $0 = started }
        }
        if case .fixed(let key) = policy {
            startUpload(recordID: recordID, data: data, destination: destination, fixedKey: key)
        } else {
            startUpload(recordID: recordID, data: data, destination: destination)
        }
    }

    /// The record's PNG: straight from the container for a temporary file, through the save
    /// folder's security scope otherwise. Throws when the record has no file any more.
    func readLocalFile(of record: CaptureRecord) throws -> Data {
        guard let fileURL = record.fileURL else { throw UploadError.fileUnreadable("no local file") }
        return record.fileIsTemporary ? try Data(contentsOf: fileURL) : try saveLocation.read(contentsOf: fileURL)
    }

    /// Copies the link (`linkURL`, which also covers an editor upload that is running or was
    /// interrupted), or the local file for a capture that has no link.
    func copyLinkOrFile(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let url = record.linkURL {
            Pasteboard.copy(url: url)
        } else if let fileURL = record.fileURL {
            Pasteboard.copy(fileURL: fileURL)
        }
    }

    /// Copy URL: the capture's link (`linkURL`). A capture that was never uploaded has none, and
    /// its row's button is disabled.
    func copyLink(recordID: UUID) {
        guard let url = history.record(id: recordID)?.linkURL else { return }
        Pasteboard.copy(url: url)
    }

    /// Copy Image: the PNG and TIFF (`Pasteboard.companionTIFF`) on the clipboard, from the local file when it can be read;
    /// otherwise (an upload-only capture, or a file that cannot be read) downloaded with a signed
    /// GET from the bucket the record says it went to, with "Copying image…" posted while that
    /// runs. The read, the pixel decode and the TIFF encode run in detached tasks, because a
    /// capture can be tens of megabytes; only the finished PNG and TIFF data are written to the
    /// clipboard here, on the main actor.
    func copyImage(recordID: UUID) async {
        guard let record = history.record(id: recordID) else { return }
        do {
            let png = try await imageData(of: record)
            let converted = await Task.detached(priority: .userInitiated) { () -> (decoded: Bool, tiff: Data?) in
                guard let decoded = ImageEncoder.decode(png) else { return (false, nil) }
                return (true, Pasteboard.companionTIFF(of: decoded.image, scale: decoded.scale))
            }.value
            guard converted.decoded else { throw CopyImageError.notAnImage }
            Pasteboard.copy(pngData: png, tiffData: converted.tiff)
            if settings.showNotification {
                // Read again: an upload that finished during the copy has given the record its key.
                let current = history.record(id: recordID) ?? record
                notifier.notify(title: "Image copied", body: current.uploadedKey ?? current.fileURL?.lastPathComponent ?? "")
            }
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Could not copy image")
        }
    }

    /// Save As… from a Quick Access card (and from a pin's menu, 6b): runs `saveCopy` after any
    /// menu tracking (`afterMenuTracking`).
    func saveAs(recordID: UUID) {
        afterMenuTracking { [weak self] in
            Task { await self?.saveCopy(recordID: recordID) }
        }
    }

    /// Activates the app, asks for a place with the editor's suggestion, then writes the capture's
    /// PNG there unchanged (`imageData(of:)`: the local file, or a signed GET). A copy only: the
    /// record, its link, `lastCaptureURL` and the clipboard stay as they are.
    private func saveCopy(recordID: UUID) async {
        guard history.record(id: recordID) != nil else { return }
        let panel = EditorNaming.savePanel(for: saveAsSuggestion(recordID: recordID))
        // Reached from a non-activating card while another app is active; a plain activate() can
        // be refused and the panel would open behind that app (as in SaveLocation.chooseFolder).
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard await panel.begin() == .OK, let url = panel.url else { return }
        // Read again: the upload may have finished, or the capture been deleted, while the panel was open.
        guard let record = history.record(id: recordID) else {
            NSLog("Save As: \(recordID) was deleted while the panel was open")
            return
        }
        let png: Data
        do {
            png = try await imageData(of: record, downloadTitle: "Saving a copy…")
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return
        }
        await writeSaveAsCopy(png, to: url)
    }

    /// The capture's PNG: the local file when it can be read, otherwise the uploaded object. Copy
    /// Image, Annotate and the card's Save As… use it. Between the two, the record's drag copy
    /// (`DragFileStore`), which an upload-only capture keeps while its card shows; an edit removes
    /// it (`applyLocalEdit`). The save folder is resolved here, on the main actor, and the file is
    /// read in a detached task, as `ThumbnailProvider` does: a temporary file in `pending`
    /// directly, a saved one through the folder's security scope.
    private func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data {
        let fileURL = record.fileURL
        let temporary = record.fileIsTemporary
        let folder = temporary ? nil : saveLocation.currentURL
        let drag = dragFiles
        let id = record.id
        let local = await Task.detached(priority: .userInitiated) { () -> Data? in
            if let fileURL {
                let data: Data?
                if temporary {
                    data = try? Data(contentsOf: fileURL)
                } else {
                    data = folder.flatMap { try? SaveLocation.readScoped(fileURL, folder: $0) }
                }
                if let data { return data }
            }
            // The drag copy: an upload-only capture's file kept while its card shows, or a download.
            return drag.stagedFile(id: id).flatMap { try? Data(contentsOf: $0) }
        }.value
        if let local { return local }
        // The record is read again: an upload-only capture whose upload finished during the read
        // has lost its `pending` file and gained the key that the snapshot above lacks.
        let current = history.record(id: record.id) ?? record
        if record.fileURL != nil, current.uploadedKey == nil || current.objectLocation == nil {
            // The file is recorded but cannot be read, and there is no upload to fall back on.
            throw CopyImageError.unreadableFile
        }
        return try await downloadImage(of: current, title: downloadTitle)
    }

    /// The uploaded object's bytes, from where the record says it went, signed with the
    /// credentials stored now. A nil title downloads quietly (a restored card's drag file).
    private func downloadImage(of record: CaptureRecord, title: String?) async throws -> Data {
        guard let key = record.uploadedKey else { throw CopyImageError.nothingToCopy }
        guard let location = record.objectLocation else { throw CopyImageError.unknownLocation }
        guard let credentials = loadCredentials() else { throw UploadError.notConfigured }
        if let title, settings.showNotification {
            notifier.notify(title: title, body: "Downloading \(key)")
        }
        return try await S3Destination(config: location.config, credentials: credentials).download(key: key)
    }

    func reveal(recordID: UUID) {
        guard let fileURL = history.record(id: recordID)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: Delete

    /// The one delete path, shared by the overlay and Recent Captures. One confirmation, Delete or
    /// Cancel. Delete stops an in-flight upload, removes its objects, each from the bucket the
    /// record names for it (`CaptureDeletion.objects(for:)`), then the local file, the thumbnail
    /// and the record. When the storage `DELETE` fails (or there are no credentials to sign it),
    /// or the file in the save folder cannot be removed, a second alert offers to remove the record
    /// from history anyway, so a capture whose object or file cannot be deleted is never stuck. A local file that is already gone is not an
    /// error; a temporary file in `pending` that cannot be removed keeps the record, with a
    /// notification.
    func deleteCapture(recordID: UUID) async {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        deletingIDs.insert(recordID)
        // The record's editor drops Save and Upload before the alert shows, through
        // `cancelUpload`, `deleteObjects` and the second alert, and learns the outcome either way.
        pushEditorState(for: recordID)
        defer {
            deletingIDs.remove(recordID)
            pushEditorState(for: recordID)
        }
        guard confirmDelete(of: record) else { return }

        // After this the record holds any key the cancelled job had reserved (`pendingObjectKey`),
        // or its uploaded key if the upload finished first.
        await cancelUpload(of: recordID)
        guard let current = history.record(id: recordID) else { return }

        // The record's own keys, its prior upload and its superseded objects, one location at a
        // time: an object left by an earlier destination lives in that destination's bucket.
        var sharedKeys: [String] = []
        for group in CaptureDeletion.grouped(CaptureDeletion.objects(for: current)) {
            // Never delete an object another capture still points at.
            // A record whose own delete is still pending (its alert open) counts as a sharer: if
            // that delete is cancelled, its URL must keep working. Read per group, because each
            // group's DELETEs await the network.
            let others = history.records.filter { $0.id != recordID }
            let shared = CaptureDeletion.sharedKeys(group.keys, at: group.location, with: others)
            sharedKeys += shared
            if let reason = await deleteObjects(group.keys.filter { !shared.contains($0) }, at: group.location) {
                if await confirmRemoveFromHistory(message: CaptureDeletion.storageFailureMessage(reason: reason),
                                                  informativeText: CaptureDeletion.storageFailureText) {
                    removeFromHistoryOnly(recordID)
                }
                return
            }
        }

        if let fileURL = current.fileURL {
            if current.fileIsTemporary {
                guard removePendingFile(at: fileURL, context: "on delete", failureTitle: "Not deleted") else { return }
            } else {
                do {
                    try saveLocation.remove(at: fileURL)
                } catch {
                    // The file lies outside the current save folder (the sandbox denies it), or the
                    // folder's bookmark no longer resolves. Any object this capture alone owned has
                    // been deleted by now (shared keys and pre-Phase 3 records keep theirs), so
                    // trying Delete again would fail on this file every time: offer to drop the
                    // record and leave the file where it is.
                    let message = CaptureDeletion.fileFailureMessage(reason: error.localizedDescription)
                    if await confirmRemoveFromHistory(message: message, informativeText: CaptureDeletion.fileFailureText) {
                        removeFromHistoryOnly(recordID)
                        notifyKept(sharedKeys)
                    }
                    return
                }
            }
            if lastCaptureURL == fileURL {
                lastCaptureURL = nil
            }
        }
        removeRecord(id: recordID)
        notifyKept(sharedKeys)
    }

    /// Says, per key, that the object stayed because another capture shares it.
    private func notifyKept(_ sharedKeys: [String]) {
        for key in sharedKeys {
            notifier.notifyError("Another capture shares this key, \(key), so its object was kept. This capture was removed from Recent Captures.",
                                 title: "Not deleted from storage")
        }
    }

    /// `DELETE`s `keys` at `location`, signed with the credentials stored now; the destination is
    /// built from where the object went, never from the current Upload settings. Returns nil when
    /// every key is gone (a 404 counts as gone), otherwise the reason for the first failure. A
    /// Keychain read that fails is reported as such, not as missing credentials.
    private func deleteObjects(_ keys: [String], at location: ObjectLocation) async -> String? {
        guard !keys.isEmpty else { return nil }
        let stored: AWSCredentials?
        do {
            stored = try storedCredentials()
        } catch {
            NSLog("Keychain read failed: \(error.localizedDescription)")
            return Self.keychainReadFailure(error)
        }
        guard let credentials = stored else {
            return "No credentials are saved in Settings > Upload."
        }
        let destination = S3Destination(config: location.config, credentials: credentials)
        for key in keys {
            do {
                try await destination.delete(key: key)
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    /// The second alert's Remove: drops the record and its thumbnail without touching storage or a
    /// file in the save folder (the delete already cancelled any upload). It re-reads the record,
    /// which may have changed while the alert waited and was open. A temporary file in
    /// `pending` is TidyShot's own copy that nothing else would ever remove, so it goes too; if it
    /// cannot be removed the record is kept, so the file is not left with nothing pointing at it.
    private func removeFromHistoryOnly(_ recordID: UUID) {
        guard let current = history.record(id: recordID) else { return }
        if current.fileIsTemporary, let fileURL = current.fileURL,
           !removePendingFile(at: fileURL, context: "on remove from history", failureTitle: "Not removed") {
            return
        }
        removeRecord(id: recordID)
    }

    /// Stops the upload for `recordID` in whichever queue has it: the current one, or one that
    /// a settings change replaced and that is still finishing its jobs. Returns after that
    /// queue's `.cancelled` event has been handled, so the record holds the reserved key.
    private func cancelUpload(of recordID: UUID) async {
        guard uploadingIDs.contains(recordID) else { return }
        // Still waiting for Clop: nothing is enqueued and no key is reserved, so this is the
        // whole cancel, as the queue's `.cancelled` event would do it.
        if optimisingIDs.remove(recordID) != nil {
            uploadingIDs.remove(recordID)
            history.update(id: recordID) { $0.uploadState = .failed(message: "Upload cancelled.") }
            refreshOverlay(for: recordID)
            return
        }
        for lane in [queue].compactMap({ $0 }) + drainingQueues {
            if case .stopped = await lane.queue.cancel(recordID: recordID) {
                return
            }
        }
    }

    /// Removes the record and its thumbnail, and closes the overlay if it shows the record. The
    /// record is read again here, not taken from before the delete's awaits, and the thumbnail
    /// named for the id is removed even when the record does not name it yet: one that finished
    /// during those awaits is not left behind.
    private func removeRecord(id: UUID) {
        let defaultName = thumbnails.fileName(for: id)
        if let name = history.record(id: id)?.thumbnailFileName, name != defaultName {
            thumbnails.remove(fileName: name)
        }
        thumbnails.remove(fileName: defaultName)
        history.remove(id: id)
        thumbnailProvider.forget(id)
        forgetLatestCapture(id)
        overlay.close(recordID: id, reason: .deleted)
        pins.close(recordID: id)
        removeDragFolder(id)
        pushEditorState(for: id)
    }

    /// Removes a temporary file from `pending`. A file that is already gone counts as removed.
    /// Any other failure is logged (`context` says when it happened), posted with `failureTitle`
    /// when one is given, and returns false.
    @discardableResult
    private func removePendingFile(at fileURL: URL, context: String, failureTitle: String? = nil) -> Bool {
        do {
            try pendingFiles.remove(fileURL)
            return true
        } catch {
            NSLog("Could not remove \(fileURL.lastPathComponent) \(context): \(error.localizedDescription)")
            if let failureTitle {
                notifier.notifyError("Could not delete \(fileURL.lastPathComponent): \(error.localizedDescription)", title: failureTitle)
            }
            return false
        }
    }

    /// The confirmation: Delete or Cancel (Escape). The app is activated first so the alert appears
    /// in front even when it was triggered from the non-activating overlay panel or the menu.
    private func confirmDelete(of record: CaptureRecord) -> Bool {
        let alert = NSAlert()
        alert.messageText = CaptureDeletion.confirmationMessage
        alert.informativeText = CaptureDeletion.confirmationText(for: record)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// The second alert, only after the storage `DELETE` failed or the file in the save folder could
    /// not be removed: Remove (from history; what could not be deleted stays) or Cancel. It comes
    /// after the delete's network awaits, and a main-actor continuation also runs while a menu is
    /// tracking (the main queue is served in the common run-loop modes), so the user may have
    /// opened the menu bar menu in the meantime. The alert therefore runs inside a block that the
    /// run loop performs only in its default mode, which is not entered while a menu tracks, so
    /// `runModal()` never starts inside a menu's tracking loop (resuming first and running the
    /// alert afterwards would leave one main-queue turn in which tracking could begin).
    private func confirmRemoveFromHistory(message: String, informativeText: String) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    let alert = NSAlert()
                    alert.messageText = message
                    alert.informativeText = informativeText
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Remove").hasDestructiveAction = true
                    alert.addButton(withTitle: "Cancel")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    done.resume(returning: alert.runModal() == .alertFirstButtonReturn)
                }
            }
        }
    }

    /// Thumbnails and temporary files of records dropped by retention, their pins closed, the
    /// retained image dropped when it is theirs, and their editors told the record is gone
    /// (`didPrune` runs after the store dropped them). Files in the save folder are
    /// left alone. (A record whose temporary file is its only copy, or holds an edit its link does
    /// not show yet, is never pruned.)
    private func removeFiles(ofPruned records: [CaptureRecord]) {
        for record in records {
            thumbnailProvider.forget(record.id)
            if let name = record.thumbnailFileName {
                thumbnails.remove(fileName: name)
            }
            if record.fileIsTemporary, let fileURL = record.fileURL {
                removePendingFile(at: fileURL, context: "after pruning")
            }
            forgetLatestCapture(record.id)
            pins.close(recordID: record.id)
            pushEditorState(for: record.id)
        }
    }

    // MARK: Upload events

    private func markFailed(_ recordID: UUID, message: String) {
        uploadingIDs.remove(recordID)
        history.update(id: recordID) { $0.uploadState = .failed(message: message) }
        refreshOverlay(for: recordID)
        notifier.notifyError(message, title: "Upload failed")
    }

    /// Pushes the record's current state into the overlay, if the overlay is showing it, and into
    /// the record's editor, so every upload progress, success, failure and retry reaches both.
    private func refreshOverlay(for id: UUID) {
        if let record = history.record(id: id) {
            overlay.update(record: record)
        }
        pushEditorState(for: id)
    }

    /// `location` is where the queue that sent `event` uploads to.
    private func handle(_ event: UploadEvent, at location: ObjectLocation) {
        switch event {
        case .started(let id, let attempt):
            if attempt > 1 {
                NSLog("Upload retry \(attempt) for \(id)")
                // Start the bar again rather than leaving the failed attempt's fraction.
                if history.setProgress(id: id, fraction: 0) {
                    refreshOverlay(for: id)
                }
            }
        case .progress(let id, let fraction):
            if history.setProgress(id: id, fraction: fraction) {
                refreshOverlay(for: id)
            }
        case .uploaded(let id, let url, let key):
            uploadingIDs.remove(id)
            guard let before = history.record(id: id) else {
                // The record disappeared while its upload was running. Nothing would point at the
                // new object, so remove it again instead of copying or announcing its URL.
                deleteOrphanedObject(key: key, at: location)
                return
            }
            // Upload-only mode: the temporary file has done its job. While a card shows the
            // capture it moves into the drag folder under the key's name, so the card can still be
            // dragged out (spec 2.9); otherwise it is removed. Either way the record drops it
            // below. If it can be neither moved nor removed the record keeps pointing at it, so
            // Delete can still remove it later.
            var removedTemporaryFile = false
            if before.fileIsTemporary, let fileURL = before.fileURL {
                removedTemporaryFile = keepForDragOut(fileURL, record: before, url: url, key: key)
                    || removePendingFile(at: fileURL, context: "after upload")
            }
            history.update(id: id) { record in
                record.uploadState = .uploaded(url: url, key: key)
                if record.objectLocation != location {
                    // A reserved key from another destination named an object there, not here.
                    record.pendingObjectKey = nil
                } else if record.pendingObjectKey == key {
                    record.pendingObjectKey = nil
                }
                record.objectLocation = location
                if removedTemporaryFile {
                    record.fileURL = nil
                    record.fileIsTemporary = false
                }
                record = EditorUploadPlan.applyingSuccess(to: record)
            }
            Pasteboard.copy(url: url)
            if EditorUploadPlan.shouldPostCacheNote(prior: before.priorUpload, uploadedKey: key, at: location,
                                                    alreadyPosted: postedCacheNote) {
                // In place of the usual notification, and also with Show notification off.
                postedCacheNote = true
                notifier.notify(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)
            } else if settings.showNotification {
                notifier.notifyUploaded(url: url)
            }
            refreshOverlay(for: id)
            Task { [weak self] in await self?.deleteSupersededObjects(of: id) }
        case .failed(let id, let message):
            guard history.record(id: id)?.priorUpload != nil else {
                markFailed(id, message: message)
                return
            }
            // An upload of a record that has a link: the old object is untouched, so the record
            // goes back to it, and keeps the edited file and the stale note.
            NSLog("Upload failed, the earlier link is kept: \(message)")
            uploadingIDs.remove(id)
            history.update(id: id) { $0 = EditorUploadPlan.applyingFailure(to: $0, message: message) }
            refreshOverlay(for: id)
            notifier.notifyError(EditorUploadPlan.failedReplaceMessage, title: "Not uploaded")
        case .cancelled(let id, let reservedKey):
            // Requested by the delete flow, which removes the record next; no notification.
            uploadingIDs.remove(id)
            history.update(id: id) { record in
                record.uploadState = .failed(message: "Upload cancelled.")
                if let reservedKey {
                    // The PUT may have landed as it was cancelled. Persisted, so Delete removes
                    // this key even if its first DELETE fails and it is tried again later.
                    record.pendingObjectKey = reservedKey
                    record.objectLocation = location
                }
            }
            refreshOverlay(for: id)
        }
    }

    /// Best-effort `DELETE` of an object whose record vanished mid-upload, built from where the
    /// object went (as Delete does) and the credentials stored now. The outcome is only logged.
    private func deleteOrphanedObject(key: String, at location: ObjectLocation) {
        // A collision-prone template can give a live record the same key; never delete that.
        guard CaptureDeletion.sharedKeys([key], at: location, with: history.records).isEmpty else {
            NSLog("Uploaded \(key) for a record that no longer exists, but another capture shares it; kept")
            return
        }
        guard let credentials = loadCredentials() else {
            NSLog("Uploaded \(key) for a record that no longer exists; no credentials to delete it")
            return
        }
        let destination = S3Destination(config: location.config, credentials: credentials)
        Task {
            do {
                try await destination.delete(key: key)
                NSLog("Deleted \(key), uploaded for a record that no longer exists")
            } catch {
                NSLog("Could not delete \(key), uploaded for a record that no longer exists: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Drag-out

    /// How long a closed card's drag folder stays, for a receiver still reading the dropped file.
    static let dragCleanupDelay: Duration = .seconds(60)

    /// Stages the record's drag file for its card: at a press on the card, and when a restored
    /// card appears. The name and the source are worked out here; the copy runs detached. The
    /// card's `dragFileURL` is nil until it is done. A record with no readable file uses its kept
    /// copy, or, uploaded, a quiet download (`prefetchDragFile`).
    func prepareDragFile(recordID: UUID) {
        guard let record = history.record(id: recordID), overlay.isShowing(recordID: recordID) else { return }
        dragCleanups.removeValue(forKey: recordID)?.cancel()
        let name = DragFileName.name(for: record, suggestion: saveAsSuggestion(recordID: recordID))
        let generation = dragGenerations[recordID, default: 0]
        dragStageSeqs[recordID, default: 0] += 1
        let seq = dragStageSeqs[recordID, default: 0]
        overlay.setDragFile(nil, for: recordID)
        let store = dragFiles
        let source = record.fileURL
        let scope = record.fileIsTemporary ? nil : saveLocation.currentURL
        Task { [weak self] in
            let staged = await Task.detached(priority: .userInitiated) { () -> URL? in
                if let source, let url = try? store.stage(id: recordID, name: name, from: source, scope: scope) {
                    return url
                }
                // An adopted or downloaded copy, or the last copy of a file that has gone since,
                // under the name worked out above.
                return store.restage(id: recordID, name: name)
            }.value
            guard let self else { return }
            guard self.dragGenerations[recordID, default: 0] == generation else {
                // The folder was replaced while this stage ran (an upload's adopt), so `staged`
                // may be a file the adopt's place() deleted. A card still showing gets whatever
                // the folder holds now; otherwise the folder this stage recreated goes.
                if self.overlay.isShowing(recordID: recordID) {
                    let current = await Task.detached(priority: .userInitiated) {
                        store.restage(id: recordID, name: name)
                    }.value
                    if self.dragStageSeqs[recordID, default: 0] == seq, self.overlay.isShowing(recordID: recordID) {
                        self.overlay.setDragFile(current, for: recordID)
                    }
                } else {
                    self.dropStaleDragFolder(recordID)
                }
                return
            }
            // A later press staged again; its file is the card's.
            guard self.dragStageSeqs[recordID, default: 0] == seq else { return }
            if let staged {
                self.overlay.setDragFile(staged, for: recordID)
            } else {
                await self.prefetchDragFile(recordID: recordID, name: name)
            }
        }
    }

    /// A quiet signed GET (no notification) of an uploaded capture that has no local file, into
    /// its drag folder. A failure is only logged; the card then cannot be dragged.
    private func prefetchDragFile(recordID: UUID, name: String) async {
        guard !prefetchingDragIDs.contains(recordID), let record = history.record(id: recordID),
              record.uploadedKey != nil, record.objectLocation != nil else { return }
        prefetchingDragIDs.insert(recordID)
        defer { prefetchingDragIDs.remove(recordID) }
        let generation = dragGenerations[recordID, default: 0]
        let store = dragFiles
        do {
            let data = try await downloadImage(of: record, title: nil)
            let url = try await Task.detached(priority: .utility) {
                try store.write(data, id: recordID, name: name)
            }.value
            guard dragGenerations[recordID, default: 0] == generation else {
                dropStaleDragFolder(recordID)
                return
            }
            overlay.setDragFile(url, for: recordID)
        } catch {
            NSLog("Drag-out download for \(recordID) failed: \(error.localizedDescription)")
        }
    }

    /// `.uploaded` for an upload-only capture: when a card shows it, moves the pending file to
    /// `Drag/<id>/<key name>` and hands it to the card. False when no card shows the record or the
    /// move failed (logged); the caller then removes the pending file as before.
    private func keepForDragOut(_ fileURL: URL, record: CaptureRecord, url: URL, key: String) -> Bool {
        guard overlay.isShowing(recordID: record.id) else { return false }
        var uploaded = record
        uploaded.uploadState = .uploaded(url: url, key: key)
        let name = DragFileName.name(for: uploaded, suggestion: saveAsSuggestion(recordID: record.id))
        do {
            let kept = try dragFiles.adopt(id: record.id, name: name, moving: fileURL)
            dragGenerations[record.id, default: 0] += 1
            overlay.setDragFile(kept, for: record.id)
            return true
        } catch {
            NSLog("Could not keep \(fileURL.lastPathComponent) for drag-out: \(error.localizedDescription)")
            return false
        }
    }

    /// A drag-out ended. With `Close after dragging out` on, a drop that a receiver took closes the
    /// card as `.draggedOut` (restorable).
    private func dragDidEnd(recordID: UUID, accepted: Bool) {
        guard accepted, settings.overlayCloseAfterDrag else { return }
        overlay.close(recordID: recordID, reason: .draggedOut)
    }

    /// A card closed, for any reason: its drag folder goes after `dragCleanupDelay`, unless the
    /// card shows again first (`prepareDragFile` cancels this).
    private func scheduleDragCleanup(_ id: UUID) {
        dragCleanups[id]?.cancel()
        dragCleanups[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.dragCleanupDelay)
            guard !Task.isCancelled, let self else { return }
            self.dragCleanups[id] = nil
            guard !self.overlay.isShowing(recordID: id) else { return }
            self.removeDragFolder(id)
        }
    }

    /// Removes the record's drag folder now (Delete, or the delayed clean-up), and makes any stage
    /// or download still running for it drop what it makes.
    private func removeDragFolder(_ id: UUID) {
        dragCleanups.removeValue(forKey: id)?.cancel()
        dragGenerations[id, default: 0] += 1
        dragFiles.remove(id: id)
    }

    /// A stage or download finished after its folder was removed or replaced: unless a card shows
    /// the record, the folder it recreated goes again.
    private func dropStaleDragFolder(_ id: UUID) {
        guard !overlay.isShowing(recordID: id) else { return }
        dragFiles.remove(id: id)
    }

    // MARK: Editor

    /// Open annotation editors, one per record.
    @ObservationIgnored private var editors: [UUID: EditorWindowController] = [:]
    /// True while a save-folder observation is registered (`observeSaveFolderForEditors`).
    @ObservationIgnored private var isObservingSaveFolder = false

    /// True while any open editor has changes that were not saved.
    var hasUnsavedEditors: Bool {
        editors.values.contains { $0.model.hasUnsavedChanges }
    }

    /// Opens the annotation editor for a capture, or brings its open editor forward. The capture
    /// just taken opens at once from the image kept in memory. Any other capture is read from its
    /// file or downloaded through `imageData(of:)`, and the PNG is decoded in a detached task, which
    /// also recovers its scale. Callers run this once menu tracking has ended.
    func openEditor(recordID: UUID) {
        if let open = editors[recordID] {
            open.present()
            return
        }
        guard !openingEditorIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        switch EditorInput.source(for: record, retainedID: latestCapture?.id, saveFolder: saveLocation.currentURL) {
        case .retained:
            guard let retained = latestCapture else { return }
            presentEditor(record: record, image: retained.image)
        case .pendingFile, .saveFolderFile, .download:
            openingEditorIDs.insert(recordID)
            Task { [weak self] in
                await self?.loadAndPresentEditor(for: record)
            }
        case .unavailable(let reason):
            notifier.notifyError(reason, title: "Could not open the capture")
        }
    }

    /// Reads or downloads the PNG, decodes it off the main actor, then opens the editor, unless
    /// the record was deleted or an editor for it opened during the load.
    private func loadAndPresentEditor(for record: CaptureRecord) async {
        defer { openingEditorIDs.remove(record.id) }
        guard let image = await loadImage(for: record) else { return }
        guard editors[record.id] == nil, let current = history.record(id: record.id) else { return }
        presentEditor(record: current, image: image)
    }

    /// The capture's pixels: its PNG through `imageData(of:)` (the local file, the drag copy or a
    /// signed GET, posting `downloadTitle` while that downloads), decoded off the main actor with
    /// the scale recovered from the PNG. On failure posts `failureTitle` and returns nil. The
    /// editor and Pin to screen use it.
    func loadImage(for record: CaptureRecord, downloadTitle: String = "Opening the capture…",
                   failureTitle: String = "Could not open the capture") async -> ScaledImage? {
        do {
            let png = try await imageData(of: record, downloadTitle: downloadTitle)
            let decoded = await Task.detached(priority: .userInitiated) { () -> ScaledImage? in
                ImageEncoder.decode(png).map { ScaledImage(image: $0.image, scale: $0.scale) }
            }.value
            guard let decoded else { throw CopyImageError.notAnImage }
            return decoded
        } catch {
            notifier.notifyError(error.localizedDescription, title: failureTitle)
            return nil
        }
    }

    var hasPins: Bool { pins.hasPins }
    var hasLockedPins: Bool { pins.hasLockedPins }
    func unlockPins() { pins.unlockAll() }
    func closePins() { pins.closeAll() }

    /// Pin to screen (spec 2.9): a floating copy of the capture. The newest capture's pixels are
    /// retained; any other is loaded with `loadImage(for:)`. An image over 8,192 px on a side is
    /// shown from `ThumbnailMaker.scaled` at the screen's pixel size; the pin keeps the capture's
    /// point size for Actual Size. A pin of the newest area capture opens over the spot it came
    /// from, any other centred on the pointer's screen. A second Pin on a pinned capture brings
    /// its pin forward. A capture deleted during the load is not pinned.
    func pin(recordID: UUID) async {
        guard let record = history.record(id: recordID), !deletingIDs.contains(recordID) else { return }
        guard !pins.bringToFront(recordID: recordID), pinningIDs.insert(recordID).inserted else { return }
        defer { pinningIDs.remove(recordID) }
        let image: ScaledImage
        if let retained = latestCapture, retained.id == recordID {
            image = retained.image
        } else {
            guard let loaded = await loadImage(for: record, downloadTitle: "Pinning the capture…",
                                               failureTitle: "Could not pin the capture") else { return }
            image = loaded
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var preferred: CGRect?
        if let area = latestCaptureArea, area.id == recordID {
            preferred = Geometry.appKitRect(fromCG: area.rect, primaryHeight: primaryHeight)
        }
        guard let screen = pinScreen(preferred: preferred) else { return }
        var shown = image.image
        let screenSide = Int((max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor).rounded())
        if let side = PinGeometry.downsampleMaxSide(pixelWidth: shown.width, pixelHeight: shown.height, screenPixelSide: screenSide) {
            let source = image
            guard let scaled = await Task.detached(priority: .userInitiated, operation: {
                ThumbnailMaker.scaled(source.image, maxSide: side)
            }).value else {
                notifier.notifyError("The capture is too large to pin.", title: "Could not pin the capture")
                return
            }
            shown = scaled
        }
        // Deleted, or its delete started, while the image loaded.
        guard history.record(id: recordID) != nil, !deletingIDs.contains(recordID) else { return }
        let imagePoints = CGSize(width: CGFloat(image.image.width) / image.scale,
                                 height: CGFloat(image.image.height) / image.scale)
        let frame = PinGeometry.initialFrame(imagePoints: imagePoints, preferred: preferred, visibleFrame: screen.visibleFrame)
        pins.open(recordID: recordID, image: shown, imagePoints: imagePoints, frame: frame, actions: pinActions())
    }

    /// The screen holding `preferred`'s centre, otherwise the pointer's, otherwise the first.
    private func pinScreen(preferred: CGRect?) -> NSScreen? {
        let screens = NSScreen.screens
        if let preferred, let screen = screens.first(where: { $0.frame.contains(CGPoint(x: preferred.midX, y: preferred.midY)) }) {
            return screen
        }
        return screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screens.first
    }

    /// The pin context menu's actions: all three work on the record, after the menu has closed.
    private func pinActions() -> PinController.Actions {
        PinController.Actions(
            copyImage: { [weak self] id in self?.afterMenuTracking { Task { await self?.copyImage(recordID: id) } } },
            saveAs: { [weak self] id in self?.saveAs(recordID: id) },
            annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) })
    }

    /// Drops the retained image if it is `id`'s.
    private func forgetLatestCapture(_ id: UUID) {
        if latestCapture?.id == id {
            latestCapture = nil
            latestCaptureArea = nil
        }
    }

    /// Runs `work` when the run loop is back in its default mode, after any menu tracking (the
    /// card's context menu, the status menu), as `RecentCapturesMenu.afterMenusClose` does for rows.
    private func afterMenuTracking(_ work: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { work() }
        }
    }

    /// The card's Annotate.
    private func openEditorAfterMenuTracking(recordID: UUID) {
        afterMenuTracking { [weak self] in self?.openEditor(recordID: recordID) }
    }

    /// Builds the model and the window and shows them. `openEditor` and `loadAndPresentEditor`
    /// have checked that no editor is open for the record and that it still exists.
    private func presentEditor(record: CaptureRecord, image: ScaledImage) {
        // A save-folder file names the window and gives it a proxy icon; a pending file in the
        // container is not shown.
        let fileURL = record.fileIsTemporary ? nil : record.fileURL
        let title = fileURL?.lastPathComponent
            ?? "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
        let model = EditorModel(recordID: record.id, image: image, renderer: RedactionRenderer.shared, defaults: settings.editorDefaults)
        let controller = EditorWindowController(model: model, actions: editorActions(for: record.id), title: title,
                                                representedURL: fileURL,
                                                cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
        controller.onClose = { [weak self] closed in self?.editorDidClose(closed) }
        editors[record.id] = controller
        pushEditorState(for: record.id)
        observeSaveFolderForEditors()
        Task { await RedactionRenderer.shared.warmUp(with: image.image) }
        controller.present()
        // The editor is now the capture's surface; the record stays in Recent Captures.
        overlay.close(recordID: record.id, reason: .editorOpened)
        // The card may already be closed (editor opened from Recent Captures): not restorable.
        closedOverlays.didClose(record.id, reason: .editorOpened)
    }

    /// The editor's actions for `recordID`. Save, Save As…, Copy, Upload and Upload as New all go
    /// through the coordinator.
    private func editorActions(for recordID: UUID) -> EditorActions {
        EditorActions(
            save: { [weak self] image in await self?.editorSave(recordID: recordID, image: image) ?? false },
            saveAs: { [weak self] image, url in
                await self?.editorSaveAs(recordID: recordID, image: image, to: url) ?? false
            },
            saveAsSuggestion: { [weak self] in
                self?.saveAsSuggestion(recordID: recordID)
                    ?? EditorNaming.SaveAsSuggestion(fileName: "Screenshot.png", directory: nil)
            },
            copy: { [weak self] image in
                await self?.editorCopy(recordID: recordID, image: image)
            },
            objectClipboard: EditorObjectClipboard(
                // An object copy is not an image: clipboardOwner is left alone. The write moves the
                // change count, so the clipboard rule will not replace the object after a Save.
                copy: { data in Pasteboard.copy(annotationClip: data) },
                paste: { Pasteboard.annotationClipData() },
                canPaste: { Pasteboard.hasAnnotationClip }),
            upload: { [weak self] image, asNew in
                await self?.editorUpload(recordID: recordID, image: image, asNew: asNew) ?? .refused
            })
    }

    /// Tells the record's open editor, if any, what it may do now: the record as it is (nil once
    /// deleted or pruned), the save folder and whether a delete is running.
    private func pushEditorState(for id: UUID) {
        editors[id]?.recordDidChange(history.record(id: id), saveFolder: saveLocation.currentURL,
                                     isDeleting: deletingIDs.contains(id))
    }

    /// While any editor is open, pushes every editor's state when the save folder changes, so Save
    /// and the subtitle follow a folder chosen in Settings. Observation calls `onChange` once per
    /// registration, before the value changes, so the push is scheduled and registers again (as
    /// StatusMenuController.updateIcon does). With no editor left it stops re-registering; the flag
    /// keeps an editor opened while a registration is pending from adding a second one. Save stays
    /// safe without this push, because `applyLocalEdit` plans from the folder at write time.
    private func observeSaveFolderForEditors() {
        guard !isObservingSaveFolder, !editors.isEmpty else { return }
        isObservingSaveFolder = true
        withObservationTracking {
            _ = saveLocation.currentURL
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isObservingSaveFolder = false
                for id in self.editors.keys {
                    self.pushEditorState(for: id)
                }
                self.observeSaveFolderForEditors()
            }
        }
    }

    /// ⌘S with a file to write over (the editor runs Save As… otherwise): encodes the edit off the
    /// main actor and saves it over the capture's own file through `applyLocalEdit`. Never touches
    /// the network.
    private func editorSave(recordID: UUID, image: ScaledImage) async -> Bool {
        if let reason = EditorAvailability.refusal(for: .save, record: history.record(id: recordID),
                                                   saveFolder: saveLocation.currentURL,
                                                   isDeleting: deletingIDs.contains(recordID)) {
            notifier.notifyError(reason, title: "Not saved")
            return false
        }
        let png: Data
        do {
            png = try await Task.detached(priority: .userInitiated) {
                try ImageEncoder.pngData(from: image.image, scale: image.scale)
            }.value
        } catch {
            await keepFailedEditOnClipboard(image, png: nil, recordID: recordID, error: error)
            return false
        }
        return await applyLocalEdit(recordID: recordID, png: png, image: image)
    }

    /// The one local-edit path, for Save and for the local write before an editor Upload. It
    /// re-checks the live record and `deletingIDs` (a Save racing a delete writes nothing), writes
    /// the PNG to the target `EditorSaveTarget.plan` picks now, records the edit, replaces the
    /// thumbnail, applies the clipboard rule and pushes the editor's state. Returns false, with
    /// `Not saved` posted, when nothing was written.
    private func applyLocalEdit(recordID: UUID, png: Data, image: ScaledImage) async -> Bool {
        let folder = saveLocation.currentURL
        let live = history.record(id: recordID)
        if let reason = EditorAvailability.refusal(for: .save, record: live, saveFolder: folder,
                                                   isDeleting: deletingIDs.contains(recordID)) {
            notifier.notifyError(reason, title: "Not saved")
            return false
        }
        guard let live else { return false }
        do {
            switch EditorSaveTarget.plan(for: live, saveFolder: folder) {
            case .saveFolderFile(let fileURL, let scope):
                try await Task.detached(priority: .userInitiated) {
                    try SaveLocation.overwriteScoped(png, at: fileURL, folder: scope)
                }.value
            case .pendingFile:
                // Always `pending/<id>.png`, replaced in place, so a retry uploads the edit.
                _ = try pendingFiles.write(png, id: recordID, ext: "png")
            case .unavailable(let reason):
                // The folder changed, or the file went, after the editor chose to write over it.
                notifier.notifyError(reason, title: "Not saved")
                return false
            }
        } catch {
            await keepFailedEditOnClipboard(image, png: png, recordID: recordID, error: error)
            return false
        }
        // The drag copy holds the pixels from before the edit: `imageData(of:)` would read it
        // before the bucket once the file is gone. A press on a showing card stages the edit.
        removeDragFolder(recordID)
        overlay.setDragFile(nil, for: recordID)
        let editedAt = Date()
        history.update(id: recordID) {
            $0.recordLocalEdit(pixelWidth: image.image.width, pixelHeight: image.image.height, at: editedAt)
        }
        replaceThumbnail(for: recordID, from: image.image, editedAt: editedAt)
        await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        pushEditorState(for: recordID)
        return true
    }

    /// A save that failed: the edit goes on the clipboard, so it is never lost, and `Not saved`
    /// says why. TidyShot put it there for this record, so the record owns the clipboard and a
    /// later successful save may replace it (the clipboard rule).
    private func keepFailedEditOnClipboard(_ image: ScaledImage, png: Data?, recordID: UUID, error: any Error) async {
        NSLog("Save over failed: \(error.localizedDescription)")
        let changeCount: Int
        if let png {
            changeCount = Pasteboard.copy(image: image.image, pngData: png, scale: image.scale)
        } else {
            // No PNG: the TIFF is the only copy, at any size, made off the main actor.
            let tiff = await Task.detached(priority: .userInitiated) {
                Pasteboard.tiffData(of: image.image, scale: image.scale)
            }.value
            changeCount = Pasteboard.copy(tiffData: tiff)
        }
        clipboardOwner = EditorClipboard.Owner(recordID: recordID, changeCount: changeCount)
        notifier.notifyError("\(error.localizedDescription) The edited image is on the clipboard.", title: "Not saved")
    }

    /// Makes the edited capture's thumbnail on a detached task and names it on the record under a
    /// new name, so Recent Captures rows reload; then drops the provider's cached images and
    /// removes the previous file. `forget` runs here, as the name changes, not before: a row that
    /// reloaded earlier would cache the old thumbnail again. A later save, a delete or a prune that
    /// got there first wins, and the new file is removed. When no thumbnail could be made the
    /// record names none, so `ThumbnailProvider` makes one from the edited file instead of showing
    /// the original.
    private func replaceThumbnail(for id: UUID, from image: CGImage, editedAt: Date) {
        let store = thumbnails
        let name = store.fileName(for: id, editedAt: editedAt)
        Task { [weak self] in
            let written = await Task.detached(priority: .utility) { () -> Bool in
                do {
                    guard let small = ThumbnailMaker.thumbnail(from: image) else { return false }
                    _ = try store.write(try ThumbnailMaker.pngData(small), fileName: name)
                    return true
                } catch {
                    NSLog("Edited thumbnail failed: \(error.localizedDescription)")
                    return false
                }
            }.value
            guard let self, let record = self.history.record(id: id), record.editedAt == editedAt else {
                if written { store.remove(fileName: name) }
                return
            }
            let previous = record.thumbnailFileName
            self.history.update(id: id) { $0.thumbnailFileName = written ? name : nil }
            self.thumbnailProvider.forget(id)
            if let previous, previous != name {
                store.remove(fileName: previous)
            }
        }
    }

    /// Save As… (⇧⌘S, and ⌘S with no file to write over): writes the flattened PNG to the URL the
    /// save panel returned, atomically. The panel's URL is user-selected, so the sandbox grants
    /// access, and no bookmark is kept. No record is made, nothing uploads, and the record and its
    /// thumbnail are left alone. Then the clipboard rule applies, as after Save: a clipboard that
    /// still holds what TidyShot put there for `recordID` gets the edited image. Never refused,
    /// like Copy.
    private func editorSaveAs(recordID: UUID, image: ScaledImage, to url: URL) async -> Bool {
        // The panel picked the record's own file, which Save can write over: run Save, so the
        // record, its thumbnail and the stale flag follow.
        if EditorSaveTarget.saveAsWritesOverOwnFile(url, record: history.record(id: recordID),
                                                    saveFolder: saveLocation.currentURL,
                                                    isDeleting: deletingIDs.contains(recordID)) {
            return await editorSave(recordID: recordID, image: image)
        }
        let png: Data
        do {
            png = try await Task.detached(priority: .userInitiated) {
                try ImageEncoder.pngData(from: image.image, scale: image.scale)
            }.value
        } catch {
            NSLog("Save As failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return false
        }
        guard await writeSaveAsCopy(png, to: url) else { return false }
        await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        return true
    }

    /// The one Save As… write, for the editor and for a card: `png` as it is, atomically, to a
    /// URL a save panel returned. The panel's URL is user-selected, so the sandbox grants the
    /// write, and no bookmark is kept. Posts `Saved` with the file name when notifications are on,
    /// or the error as `Not saved`. Touches no record.
    @discardableResult
    private func writeSaveAsCopy(_ png: Data, to url: URL) async -> Bool {
        do {
            try await Task.detached(priority: .userInitiated) {
                try png.write(to: url, options: .atomic)
            }.value
        } catch {
            NSLog("Save As failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return false
        }
        if settings.showNotification {
            notifier.notifySaved(fileURL: url, title: "Saved")
        }
        return true
    }

    /// The Save As… suggestion for `recordID`, the editor's and the card's: its file name in the
    /// save folder, or the file name template's name with the current `{counter}` (none is drawn).
    private func saveAsSuggestion(recordID: UUID) -> EditorNaming.SaveAsSuggestion {
        EditorNaming.saveAsSuggestion(for: history.record(id: recordID), saveFolder: saveLocation.currentURL,
                                      namer: FileNamer(template: settings.fileNameTemplate),
                                      currentCounter: settings.currentCounter)
    }

    /// Upload (⌘U) and Upload as New (⌥⌘U). The edit is written locally first, so the file equals
    /// the object; then it goes through the live lane like any upload, over the link's own key for
    /// a replace or under a new template key. The outcome says whether the edit was written
    /// locally (the editor marks itself saved) and whether the job was enqueued (the editor then
    /// closes; the link reaches the clipboard through `.uploaded`). Every enqueued upload has
    /// written the edit locally first. A refused upload leaves the window open.
    private func editorUpload(recordID: UUID, image: ScaledImage, asNew: Bool) async -> EditorUploadOutcome {
        let action: EditorAction = asNew ? .uploadAsNew : .upload
        // 1. The editor's available set can lag behind the record.
        if refuseUpload(action, recordID: recordID) { return .refused }
        // 2. Nothing is written, and the record stays as it is, without a destination.
        guard let destination = makeDestination() else {
            notifier.notifyError("Set up a destination in Settings > Upload, then upload again.", title: "Upload not configured")
            return .refused
        }
        let png: Data
        do {
            png = try await Task.detached(priority: .userInitiated) {
                try ImageEncoder.pngData(from: image.image, scale: image.scale)
            }.value
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Not uploaded")
            return .refused
        }
        // 3. The local write, on the record as it is after the encode.
        if refuseUpload(action, recordID: recordID) { return .refused }
        guard let record = history.record(id: recordID) else { return .refused }
        switch EditorSaveTarget.uploadWrite(for: record, saveFolder: saveLocation.currentURL) {
        case .saveTarget:
            guard await applyLocalEdit(recordID: recordID, png: png, image: image) else { return .refused }
        case .newPendingFile:
            // Nothing to write over: an uploaded upload-only capture (its pending file went after
            // its upload), or a save-folder file outside the current folder (or no folder). The edit
            // gets pending/<id>.png and the record switches to it, so Retry and a replace retry read
            // the edited bytes, a failed upload keeps them (keepsUnuploadedEdit), and
            // handle(.uploaded) removes the file. A save-folder original is left where it is.
            do {
                let url = try pendingFiles.write(png, id: recordID, ext: "png")
                history.update(id: recordID) { record in
                    record.fileURL = url
                    record.fileIsTemporary = true
                }
            } catch {
                NSLog("Pending write failed: \(error.localizedDescription)")
                keepOnClipboard(image, png: png, alreadyOnClipboard: false)
                notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
                return .refused
            }
            // Now a pending-file target: applyLocalEdit rewrites the same bytes and does the
            // bookkeeping (pixel size, editedAt, uploadIsStale, thumbnail, clipboard, editor state).
            guard await applyLocalEdit(recordID: recordID, png: png, image: image) else { return .refused }
        }
        // 4. Plan on the live record, against where the lane writes (as in startUpload).
        let notEnqueued = EditorUploadOutcome(wroteLocally: true, enqueued: false)
        if refuseUpload(action, recordID: recordID) { return notEnqueued }
        guard let current = history.record(id: recordID) else { return notEnqueued }
        let location = queue?.location ?? ObjectLocation(config: destination.config)
        let plan = EditorUploadPlan.plan(record: current, currentLocation: location,
                                         others: history.records.filter { $0.id != recordID }, asNew: asNew)
        switch plan {
        case .refuse(let reason):
            notifier.notifyError(reason, title: "Not uploaded")
            return notEnqueued
        case .newObject(_, let notice?):
            notifier.notify(title: "New link", body: notice)
        case .newObject, .replace:
            break
        }
        // 5. Uploading, the prior link and any superseded object, in one write.
        history.update(id: recordID) { $0 = EditorUploadPlan.startingUpload($0, plan: plan) }
        // 6. startUpload skips this refresh for a record already uploading, so the overlay and the
        // editor (through pushEditorState) show Uploading… now, before the first progress event.
        refreshOverlay(for: recordID)
        // 7. Through the live lane: uploadingIDs, progress, cancel, Delete and the menu bar icon.
        if case .replace(let key) = plan {
            startUpload(recordID: recordID, data: png, destination: destination, fixedKey: key)
        } else {
            startUpload(recordID: recordID, data: png, destination: destination)
        }
        return EditorUploadOutcome(wroteLocally: true, enqueued: true)
    }

    /// Posts the live refusal for `action` as "Not uploaded". True when the upload must stop.
    private func refuseUpload(_ action: EditorAction, recordID: UUID) -> Bool {
        guard let reason = EditorAvailability.refusal(for: action, record: history.record(id: recordID),
                                                      saveFolder: saveLocation.currentURL,
                                                      isDeleting: deletingIDs.contains(recordID)) else { return false }
        notifier.notifyError(reason, title: "Not uploaded")
        return true
    }

    /// After a successful upload: deletes each superseded object at its own location, signed with
    /// the credentials stored now. A key another capture points at is kept and dropped from the
    /// list (that capture's own Delete removes it). A key that cannot be deleted stays listed, so
    /// Delete tries it again through `CaptureDeletion.objects(for:)`. Nothing is deleted while a
    /// newer upload of the record runs (`EditorUploadPlan.supersededStep`): the record is read
    /// again before each DELETE, because that upload may start during an earlier one.
    private func deleteSupersededObjects(of id: UUID) async {
        guard !deletingIDs.contains(id), let record = history.record(id: id), !record.isUploading,
              !record.supersededObjects.isEmpty else { return }
        var settled: [ObjectRef] = []
        for ref in record.supersededObjects {
            guard let current = history.record(id: id) else { break }
            switch EditorUploadPlan.supersededStep(for: ref, of: current) {
            case .keep:
                continue
            case .drop:
                settled.append(ref) // never delete the link itself
                continue
            case .delete:
                break
            }
            let others = history.records.filter { $0.id != id }
            if !CaptureDeletion.sharedKeys([ref.key], at: ref.location, with: others).isEmpty {
                NSLog("Kept superseded \(ref.key): another capture shares it")
                settled.append(ref)
            } else if let reason = await deleteObjects([ref.key], at: ref.location) {
                NSLog("Could not delete superseded \(ref.key): \(reason)")
            } else {
                settled.append(ref)
            }
        }
        // An upload that started meanwhile may have listed the dropped link again as its prior
        // link; that entry stays for its own clean-up.
        history.update(id: id) { record in
            let prior = record.priorUpload.map { ObjectRef(key: $0.key, location: $0.location) }
            record.supersededObjects.removeAll { settled.contains($0) && $0 != prior }
        }
    }

    /// The clipboard rule (spec 2.6), after a local edit (Save, or the write before Upload) or a
    /// Save As…. Puts the edited PNG and TIFF on the clipboard only while it still holds exactly
    /// what TidyShot put there for `recordID`, and leaves anything copied since alone. The TIFF is
    /// made in a detached task. Ownership is checked again after that await, right before the
    /// write, so a URL that a finished upload copied in the meantime is never overwritten.
    /// TidyShot then owns the clipboard for this record at the new count, so a later edit replaces
    /// this one too.
    private func replaceClipboardIfStillOriginal(recordID: UUID, png: Data, image: ScaledImage) async {
        guard EditorClipboard.shouldReplace(owner: clipboardOwner, recordID: recordID,
                                            currentChangeCount: NSPasteboard.general.changeCount) else { return }
        let tiff = await Task.detached(priority: .userInitiated) {
            Pasteboard.companionTIFF(of: image.image, scale: image.scale)
        }.value
        guard EditorClipboard.shouldReplace(owner: clipboardOwner, recordID: recordID,
                                            currentChangeCount: NSPasteboard.general.changeCount) else { return }
        let changeCount = Pasteboard.copy(pngData: png, tiffData: tiff)
        clipboardOwner = EditorClipboard.Owner(recordID: recordID, changeCount: changeCount)
    }

    /// Copy (⌘C, ⇧⌘C): the edited image as PNG and TIFF (`Pasteboard.companionTIFF`), both encoded in a detached task and
    /// written here on the main actor. TidyShot then owns the clipboard for this record, so a later
    /// Save or Save As… puts the newer edit there. The window stays open.
    private func editorCopy(recordID: UUID, image: ScaledImage) async {
        do {
            let encoded = try await Task.detached(priority: .userInitiated) { () throws -> (png: Data, tiff: Data?) in
                (try ImageEncoder.pngData(from: image.image, scale: image.scale),
                 Pasteboard.companionTIFF(of: image.image, scale: image.scale))
            }.value
            let changeCount = Pasteboard.copy(pngData: encoded.png, tiffData: encoded.tiff)
            clipboardOwner = EditorClipboard.Owner(recordID: recordID, changeCount: changeCount)
            if settings.showNotification {
                let record = history.record(id: recordID)
                notifier.notify(title: "Image copied", body: record?.uploadedKey ?? record?.fileURL?.lastPathComponent ?? "")
            }
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Could not copy image")
        }
    }

    /// Drops a closed editor. When the last one closes, the renderer frees its caches.
    private func editorDidClose(_ controller: EditorWindowController) {
        let id = controller.model.recordID
        guard editors[id] === controller else { return }
        editors[id] = nil
        if editors.isEmpty {
            Task { await RedactionRenderer.shared.clearCaches() }
        }
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

    // MARK: Helpers

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            if ScreenCapturePermission.isGranted {
                notifier.notifyError("Could not list screens and windows: \(error.localizedDescription)")
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

    private func withCaptureLock(_ body: () async -> Void) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        await body()
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

/// Why Copy Image had nothing to put on the clipboard.
nonisolated enum CopyImageError: LocalizedError, Equatable, Sendable {
    /// No local file and no upload: nothing to fetch.
    case nothingToCopy
    /// Uploaded, with no file URL and no stored location. No real history holds such a record: one
    /// uploaded before Phase 3 always keeps its `fileURL`, so when that file is gone the read fails
    /// with `unreadableFile`, and an upload-only capture stores its location before its temporary
    /// file is dropped. `RecentCaptureFormatting.canCopyImage` disables the button for it.
    case unknownLocation
    /// A file is recorded but cannot be read, and there is no upload to fall back on.
    case unreadableFile
    case notAnImage

    var errorDescription: String? {
        switch self {
        case .nothingToCopy: "This capture was never uploaded and has no local file."
        case .unknownLocation: "The capture has no local file, and TidyShot does not know where its upload went."
        case .unreadableFile: "The local file could not be read."
        case .notAnImage: "The file is not an image TidyShot can read."
        }
    }
}
