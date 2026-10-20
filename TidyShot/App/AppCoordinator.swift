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

    /// The buttons of the delete confirmation.
    private enum DeleteChoice {
        case delete
        case removeFromHistoryOnly
        case cancel
    }

    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    let history: HistoryStore
    /// `thumbnails` and `pending` folders next to `history.json`.
    let thumbnails: ThumbnailStore
    let pendingFiles: PendingFileStore
    let credentialStore: any CredentialStore = KeychainCredentialStore()
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    private let overlay = QuickAccessController()
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)
    /// The queue new uploads go to, built from the destination of the first upload after launch
    /// or after the Upload tab was saved.
    @ObservationIgnored private var queue: UploadLane?
    /// Queues replaced by `destinationDidChange()`, kept until they report idle. Their jobs
    /// finish against the destination they started with (their records store that location),
    /// and Delete can still cancel them.
    @ObservationIgnored private var drainingQueues: [UploadLane] = []
    /// Records whose delete is in progress (alert showing or requests running): a second click
    /// shows no second alert, and the shared-key check ignores them.
    @ObservationIgnored private var deletingIDs: Set<UUID> = []
    /// Set after the first "Upload not configured" notification so later captures stay quiet.
    @ObservationIgnored private var warnedUploadNotConfigured = false

    private(set) var isCapturing = false
    /// The last capture written to the save folder (upload-only captures do not count).
    private(set) var lastCaptureURL: URL?
    /// Records with an upload in flight; drives the menu bar icon.
    private(set) var uploadingIDs: Set<UUID> = []

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }
    var isUploading: Bool { !uploadingIDs.isEmpty }

    init() {
        let url = (try? HistoryStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: HistoryStore.fileName)
        history = HistoryStore(fileURL: url, retentionDays: { AppSettings.shared.historyRetentionDays })
        thumbnails = ThumbnailStore(nextTo: url)
        pendingFiles = PendingFileStore(nextTo: url)
        history.didPrune = { [weak self] records in self?.removeFiles(ofPruned: records) }
    }

    func start() {
        notifier.setUp()
        history.load()
        registerShortcuts()
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .captureFullscreen) { [weak self] in
            Task { await self?.captureFullscreen() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in
            Task { await self?.captureArea() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in
            Task { await self?.captureWindow() }
        }
    }

    func captureFullscreen() async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            await save(result, appName: frontApp)
        }
    }

    func captureArea() async {
        await runSelection(mode: .area)
    }

    func captureWindow() async {
        await runSelection(mode: .window)
    }

    /// Show the overlay, capture with the overlay excluded, dismiss, then save.
    private func runSelection(mode: SelectionMode) async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: mode, content: content) else { return }

            let result: CaptureResult?
            let appName: String?
            switch selection {
            case .area(let rect, let display):
                let overlays = await selector.overlayWindows()
                result = await capture(.area(rect: rect, display: display), excludingWindows: overlays)
                appName = frontApp
            case .window(let window):
                result = await capture(.window(window))
                appName = window.owningApplication?.applicationName
            }
            selector.dismiss()

            if let result {
                await save(result, appName: appName)
            }
        }
    }

    func revealLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    /// Runs the engine. On failure posts a notification and returns nil.
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = []) async -> CaptureResult? {
        do {
            return try await engine.capture(target, options: CaptureOptions(showsCursor: settings.showsCursor), excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return nil
        }
    }

    // MARK: Save and upload

    /// Encode, copy to clipboard (image now, or URL later), write the file (save folder, or the
    /// container's `pending` folder in upload-only mode), record in history, start the thumbnail,
    /// show the overlay, and start the upload. A file is always written before the upload starts;
    /// if it cannot be written the image stays on the clipboard, so a capture is never dropped.
    func save(_ result: CaptureResult, appName: String?) async {
        let png: Data
        do {
            png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            // Never drop a capture: without PNG data the clipboard still gets the image as TIFF.
            Pasteboard.copy(image: result.image, scale: result.scale)
            notifier.notifyError(error.localizedDescription)
            return
        }

        let action = settings.afterCaptureAction
        // One keychain read per capture; the result is passed to startUpload below.
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
        if copyImageNow {
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
        }

        // The object key is not named here: `startUpload` names it when the upload starts.
        let id = UUID()
        let fileURL: URL
        if action == .uploadOnly {
            guard let url = writePendingFile(png, id: id, result: result, alreadyOnClipboard: copyImageNow) else { return }
            fileURL = url
        } else {
            guard let url = await writeFile(png, result: result, appName: appName, alreadyOnClipboard: copyImageNow) else { return }
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
        let record = CaptureRecord(id: id, fileURL: fileURL, fileIsTemporary: action == .uploadOnly,
                                   pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: appName, uploadState: state)
        history.add(record)
        makeThumbnail(from: result.image, for: id)
        showOverlay(for: record, image: result.image, scale: result.scale)

        if let destination {
            startUpload(recordID: record.id, data: png, destination: destination)
        } else if action != .uploadOnly, settings.showNotification {
            // Save mode, or upload mode with no destination (as in Phase 2): the file was saved.
            notifier.notifySaved(fileURL: fileURL)
        }
    }

    /// Posts "Upload not configured" the first time per launch only. With the default
    /// after-capture action set to upload, a user without a destination would otherwise get a
    /// notification for every capture.
    private func warnUploadNotConfiguredOnce(_ message: String) {
        guard !warnedUploadNotConfigured else { return }
        warnedUploadNotConfigured = true
        notifier.notifyError(message, title: "Upload not configured")
    }

    /// Writes the PNG into the save folder, drawing the file name's `{counter}` as Phase 1 did.
    /// Returns nil after notifying, with the image left on the clipboard, when there is no folder
    /// or the write fails.
    private func writeFile(_ png: Data, result: CaptureResult, appName: String?, alreadyOnClipboard: Bool) async -> URL? {
        guard let folder = await saveLocation.ensureFolder() else {
            keepOnClipboard(result, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("No folder was chosen. The image is on the clipboard.", title: "Not saved")
            return nil
        }
        do {
            let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: counter)
            return try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            keepOnClipboard(result, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    /// Upload-only mode: writes the PNG into the container's `pending` folder, no folder prompt.
    private func writePendingFile(_ png: Data, id: UUID, result: CaptureResult, alreadyOnClipboard: Bool) -> URL? {
        do {
            return try pendingFiles.write(png, id: id, ext: "png")
        } catch {
            NSLog("Pending write failed: \(error.localizedDescription)")
            keepOnClipboard(result, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    private func keepOnClipboard(_ result: CaptureResult, png: Data, alreadyOnClipboard: Bool) {
        if !alreadyOnClipboard {
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
        }
    }

    /// Makes and writes the 320 px thumbnail on a detached task, off the main actor, and stores
    /// its file name on the record when that finishes. Until then the gallery makes one from the
    /// file itself; a failure is logged and the gallery falls back the same way. If the record was
    /// deleted in the meantime the new file is removed again.
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
            guard let self, self.history.record(id: id) != nil else {
                store.remove(fileName: name)
                return
            }
            self.history.update(id: id) { $0.thumbnailFileName = name }
        }
    }

    private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat) {
        guard settings.showOverlay else { return }
        let thumbnail = image.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
        overlay.show(record: record, thumbnail: thumbnail, corner: settings.overlayCorner,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds,
                     actions: QuickAccessController.Actions(
                        copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
                        retry: { [weak self] id in self?.retryUpload(recordID: id) },
                        reveal: { [weak self] id in self?.reveal(recordID: id) },
                        delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } }))
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
        let stored: AWSCredentials?
        do {
            stored = try credentialStore.load(account: KeychainCredentialStore.defaultAccount)
        } catch {
            NSLog("Keychain read failed: \(error.localizedDescription)")
            warnUploadNotConfiguredOnce("Could not read S3 credentials from the keychain: \(error.localizedDescription)")
            return nil
        }
        guard let credentials = stored, !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            return nil
        }
        return credentials
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
            while !(await old.queue.isIdle) {
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
    /// created (first upload, or after the Upload tab was saved); callers read it once.
    private func startUpload(recordID: UUID, data: Data, destination: S3Destination) {
        // Look the record up before marking it uploading, so a missing record never leaves an
        // id in `uploadingIDs` (and the menu bar icon spinning) with no job to clear it.
        guard let record = history.record(id: recordID) else { return }
        let lane = queue ?? makeLane(for: destination)
        queue = lane
        uploadingIDs.insert(recordID)
        // `save` adds new records already marked uploading and shows them in the overlay, so
        // only a retry (a record in another state) needs the write and the overlay refresh.
        if !record.isUploading {
            history.update(id: recordID) { $0.uploadState = .uploading(fraction: 0) }
            refreshOverlay(for: recordID)
        }
        // The key is named now, not at capture time: a capture taken while no destination was set
        // up, and every retry, get a counter drawn when their upload starts. The date and app stay
        // the capture's own, so a retried upload lands in the capture's date folder.
        let counter = lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, appName: record.appName, counter: counter))
        Task { await lane.queue.enqueue(job) }
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
    private func retry(recordID: UUID, destination: S3Destination) {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        do {
            let data = try readLocalFile(of: record)
            startUpload(recordID: recordID, data: data, destination: destination)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL?.lastPathComponent ?? "no local file").localizedDescription)
        }
    }

    /// The record's PNG: straight from the container for a temporary file, through the save
    /// folder's security scope otherwise. Throws when the record has no file any more.
    func readLocalFile(of record: CaptureRecord) throws -> Data {
        guard let fileURL = record.fileURL else { throw UploadError.fileUnreadable("no local file") }
        return record.fileIsTemporary ? try Data(contentsOf: fileURL) : try saveLocation.read(contentsOf: fileURL)
    }

    /// Copies the public URL, or the local file for a capture that was never uploaded.
    func copyLinkOrFile(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let url = record.uploadedURL {
            Pasteboard.copy(url: url)
        } else if let fileURL = record.fileURL {
            Pasteboard.copy(fileURL: fileURL)
        }
    }

    func reveal(recordID: UUID) {
        guard let fileURL = history.record(id: recordID)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Menu action for a history row: copy the URL, retry a failed upload, or reveal the file.
    /// Replaced by the gallery in the next task.
    func historyItemSelected(_ recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        switch record.uploadState {
        case .uploaded: copyLinkOrFile(recordID: recordID)
        case .failed: retryUpload(recordID: recordID)
        case .none, .uploading: reveal(recordID: recordID)
        }
    }

    // MARK: Delete

    /// Shared by the overlay and the gallery. One confirmation with three answers. Delete stops
    /// an in-flight upload, removes the object from the bucket the record says it went to, then
    /// the local file, the thumbnail and the record. A failed `DELETE` or a local file that
    /// cannot be removed keeps the record, with a notification, so Delete can be tried again; a
    /// local file that is already gone is not an error. "Remove from History Only" drops just the
    /// record, for a capture whose object can no longer be deleted.
    func deleteCapture(recordID: UUID) async {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        deletingIDs.insert(recordID)
        defer { deletingIDs.remove(recordID) }

        switch confirmDelete(of: record) {
        case .cancel:
            return
        case .removeFromHistoryOnly:
            // Stop an upload still running so it cannot finish for a record that is gone. Nothing
            // in the bucket or the save folder is touched; a temporary file in `pending` is
            // TidyShot's own copy that nothing else would ever remove, so it goes with the record.
            await cancelUpload(of: recordID)
            guard let current = history.record(id: recordID) else { return }
            // If the temporary file cannot be removed the record is kept, as Delete does, so the
            // file is not left behind with nothing pointing at it.
            if current.fileIsTemporary, let fileURL = current.fileURL,
               !removePendingFile(at: fileURL, context: "on remove from history", failureTitle: "Not removed") {
                return
            }
            removeRecord(id: recordID)
            return
        case .delete:
            break
        }

        // After this the record holds any key the cancelled job had reserved (`pendingObjectKey`),
        // or its uploaded key if the upload finished first.
        await cancelUpload(of: recordID)
        guard let current = history.record(id: recordID) else { return }

        var sharedKeys: [String] = []
        let keys = CaptureDeletion.objectKeys(for: current)
        if !keys.isEmpty, let location = current.objectLocation {
            guard let credentials = loadCredentials() else {
                notifier.notifyError("Save credentials in Settings > Upload so the uploaded object can be removed, then try again, or choose Remove from History Only.",
                                     title: "Not deleted")
                return
            }
            // Never delete an object another capture still points at.
            let others = history.records.filter { $0.id != recordID && !deletingIDs.contains($0.id) }
            sharedKeys = CaptureDeletion.sharedKeys(keys, at: location, with: others)
            // Built from where the object went, not from the current Upload settings.
            let destination = S3Destination(config: location.config, credentials: credentials)
            for key in keys where !sharedKeys.contains(key) {
                do {
                    try await destination.delete(key: key)
                } catch {
                    notifier.notifyError("Could not delete \(key): \(error.localizedDescription)", title: "Not deleted")
                    return
                }
            }
        }

        if let fileURL = current.fileURL {
            if current.fileIsTemporary {
                guard removePendingFile(at: fileURL, context: "on delete", failureTitle: "Not deleted") else { return }
            } else {
                do {
                    try saveLocation.remove(at: fileURL)
                } catch {
                    notifier.notifyError("Could not delete \(fileURL.lastPathComponent): \(error.localizedDescription)", title: "Not deleted")
                    return
                }
            }
            if lastCaptureURL == fileURL {
                lastCaptureURL = nil
            }
        }
        removeRecord(id: recordID)
        for key in sharedKeys {
            notifier.notifyError("Another capture shares this key, \(key), so its object was kept. This capture was removed from Recent Captures.",
                                 title: "Not deleted from storage")
        }
    }

    /// Stops the upload for `recordID` in whichever queue has it: the current one, or one that
    /// a settings change replaced and that is still finishing its jobs. Returns after that
    /// queue's `.cancelled` event has been handled, so the record holds the reserved key.
    private func cancelUpload(of recordID: UUID) async {
        guard uploadingIDs.contains(recordID) else { return }
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
        overlay.close(recordID: id)
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

    /// The one confirmation. The app is activated first so the alert appears in front even when
    /// it was triggered from the non-activating overlay panel.
    private func confirmDelete(of record: CaptureRecord) -> DeleteChoice {
        let alert = NSAlert()
        alert.messageText = "Delete this capture?"
        alert.informativeText = CaptureDeletion.confirmationText(for: record)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Remove from History Only")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .delete
        case .alertSecondButtonReturn: return .removeFromHistoryOnly
        default: return .cancel
        }
    }

    /// Thumbnails and temporary files of records dropped by retention. Files in the save folder
    /// are left alone. (A record whose temporary file is its only copy is never pruned.)
    private func removeFiles(ofPruned records: [CaptureRecord]) {
        for record in records {
            if let name = record.thumbnailFileName {
                thumbnails.remove(fileName: name)
            }
            if record.fileIsTemporary, let fileURL = record.fileURL {
                removePendingFile(at: fileURL, context: "after pruning")
            }
        }
    }

    // MARK: Upload events

    private func markFailed(_ recordID: UUID, message: String) {
        uploadingIDs.remove(recordID)
        history.update(id: recordID) { $0.uploadState = .failed(message: message) }
        refreshOverlay(for: recordID)
        notifier.notifyError(message, title: "Upload failed")
    }

    /// Pushes the record's current state into the overlay, if the overlay is showing it.
    private func refreshOverlay(for id: UUID) {
        if let record = history.record(id: id) {
            overlay.update(record: record)
        }
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
            // Upload-only mode: the temporary file has done its job. If it cannot be removed the
            // record keeps pointing at it, so Delete can still remove it later.
            var removedTemporaryFile = false
            if let record = history.record(id: id), record.fileIsTemporary, let fileURL = record.fileURL {
                removedTemporaryFile = removePendingFile(at: fileURL, context: "after upload")
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
            }
            Pasteboard.copy(url: url)
            if settings.showNotification {
                notifier.notifyUploaded(url: url)
            }
            refreshOverlay(for: id)
        case .failed(let id, let message):
            markFailed(id, message: message)
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
