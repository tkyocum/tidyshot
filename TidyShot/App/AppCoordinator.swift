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
    let credentialStore: any CredentialStore = KeychainCredentialStore()
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    private let overlay = QuickAccessController()
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)
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
    /// Records whose delete is in progress (alert showing or requests running): a second click
    /// shows no second alert, and a retry does not re-enqueue them.
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
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            await save(result)
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
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: mode, content: content) else { return }

            let result: CaptureResult?
            switch selection {
            case .area(let rect, let display):
                let overlays = await selector.overlayWindows()
                result = await capture(.area(rect: rect, display: display), excludingWindows: overlays)
            case .window(let window):
                result = await capture(.window(window))
            }
            selector.dismiss()

            if let result {
                await save(result)
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
    func save(_ result: CaptureResult) async {
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
            guard let url = await writeFile(png, result: result, alreadyOnClipboard: copyImageNow) else { return }
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
                                   pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: nil, uploadState: state)
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
    private func writeFile(_ png: Data, result: CaptureResult, alreadyOnClipboard: Bool) async -> URL? {
        guard let folder = await saveLocation.ensureFolder() else {
            keepOnClipboard(result, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("No folder was chosen. The image is on the clipboard.", title: "Not saved")
            return nil
        }
        do {
            let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let baseName = FileNamer(template: settings.fileNameTemplate).name(counter: counter)
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
    /// its file name on the record when that finishes. Until then `ThumbnailProvider` makes one
    /// from the file itself; a failure is logged and it falls back the same way. If the record was
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
        // up, and every retry, get a counter drawn when their upload starts. The date stays the
        // capture's own, so a retried upload lands in the capture's date folder.
        let counter = lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, counter: counter))
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

    /// Copy URL: the public URL of an uploaded capture. A capture that was never uploaded has none,
    /// and its row's button is disabled.
    func copyLink(recordID: UUID) {
        guard let url = history.record(id: recordID)?.uploadedURL else { return }
        Pasteboard.copy(url: url)
    }

    /// Copy Image: the PNG and TIFF on the clipboard, from the local file when it can be read;
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
                return (true, Pasteboard.tiffData(of: decoded.image, scale: decoded.scale))
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

    /// The capture's PNG: the local file when it can be read, otherwise the uploaded object. The
    /// save folder is resolved here, on the main actor, and the file is read in a detached task,
    /// as `ThumbnailProvider` does: a temporary file in `pending` directly, a saved one through
    /// the folder's security scope.
    private func imageData(of record: CaptureRecord) async throws -> Data {
        if let fileURL = record.fileURL {
            let temporary = record.fileIsTemporary
            let folder = temporary ? nil : saveLocation.currentURL
            let local = await Task.detached(priority: .userInitiated) { () -> Data? in
                if temporary { return try? Data(contentsOf: fileURL) }
                guard let folder else { return nil }
                return try? SaveLocation.readScoped(fileURL, folder: folder)
            }.value
            if let local { return local }
            // The file is recorded but cannot be read; the uploaded object is the other copy. The
            // record is read again: an upload-only capture whose upload finished during the read
            // has lost its `pending` file and gained the key that the snapshot above lacks.
            let current = history.record(id: record.id) ?? record
            guard current.uploadedKey != nil, current.objectLocation != nil else { throw CopyImageError.unreadableFile }
            return try await downloadImage(of: current)
        }
        return try await downloadImage(of: record)
    }

    /// The uploaded object's bytes, from where the record says it went, signed with the
    /// credentials stored now.
    private func downloadImage(of record: CaptureRecord) async throws -> Data {
        guard let key = record.uploadedKey else { throw CopyImageError.nothingToCopy }
        guard let location = record.objectLocation else { throw CopyImageError.unknownLocation }
        guard let credentials = loadCredentials() else { throw UploadError.notConfigured }
        if settings.showNotification {
            notifier.notify(title: "Copying image…", body: "Downloading \(key)")
        }
        return try await S3Destination(config: location.config, credentials: credentials).download(key: key)
    }

    func reveal(recordID: UUID) {
        guard let fileURL = history.record(id: recordID)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    // MARK: Delete

    /// The one delete path, shared by the overlay and Recent Captures. One confirmation, Delete or
    /// Cancel. Delete stops an in-flight upload, removes the object from the bucket the record says
    /// it went to, then the local file, the thumbnail and the record. When the storage `DELETE`
    /// fails (or there are no credentials to sign it), or the file in the save folder cannot be
    /// removed, a second alert offers to remove the record from history anyway, so a capture whose
    /// object or file cannot be deleted is never stuck. A local file that is already gone is not an
    /// error; a temporary file in `pending` that cannot be removed keeps the record, with a
    /// notification.
    func deleteCapture(recordID: UUID) async {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        deletingIDs.insert(recordID)
        defer { deletingIDs.remove(recordID) }
        guard confirmDelete(of: record) else { return }

        // After this the record holds any key the cancelled job had reserved (`pendingObjectKey`),
        // or its uploaded key if the upload finished first.
        await cancelUpload(of: recordID)
        guard let current = history.record(id: recordID) else { return }

        var sharedKeys: [String] = []
        let keys = CaptureDeletion.objectKeys(for: current)
        if !keys.isEmpty, let location = current.objectLocation {
            // Never delete an object another capture still points at.
            // A record whose own delete is still pending (its alert open) counts as a sharer: if
            // that delete is cancelled, its URL must keep working.
            let others = history.records.filter { $0.id != recordID }
            sharedKeys = CaptureDeletion.sharedKeys(keys, at: location, with: others)
            if let reason = await deleteObjects(keys.filter { !sharedKeys.contains($0) }, at: location) {
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

    /// Thumbnails and temporary files of records dropped by retention. Files in the save folder
    /// are left alone. (A record whose temporary file is its only copy is never pruned.)
    private func removeFiles(ofPruned records: [CaptureRecord]) {
        for record in records {
            thumbnailProvider.forget(record.id)
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
            guard history.record(id: id) != nil else {
                // The record disappeared while its upload was running. Nothing would point at the
                // new object, so remove it again instead of copying or announcing its URL.
                deleteOrphanedObject(key: key, at: location)
                return
            }
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

    // MARK: Editor

    /// Open annotation editors, one per record.
    @ObservationIgnored private var editors: [UUID: EditorWindowController] = [:]

    /// True while any open editor has changes that were not saved.
    var hasUnsavedEditors: Bool {
        editors.values.contains { $0.model.hasUnsavedChanges }
    }

    /// Opens the annotation editor for `recordID`, or brings its open editor forward. The PNG is
    /// read as Copy Image reads it (`imageData(of:)`: the local file, else the uploaded object),
    /// and decoded in a detached task, which also recovers the capture's scale from its DPI.
    /// Task 16 adds the in-memory image of the capture just taken (`EditorInput`).
    func openEditor(recordID: UUID) {
        if let open = editors[recordID] {
            open.present()
            return
        }
        guard let record = history.record(id: recordID) else { return }
        Task {
            do {
                let png = try await imageData(of: record)
                let decoded = await Task.detached(priority: .userInitiated) { ImageEncoder.decode(png) }.value
                guard let decoded else { throw CopyImageError.notAnImage }
                showEditor(recordID: recordID, image: ScaledImage(image: decoded.image, scale: decoded.scale))
            } catch {
                notifier.notifyError(error.localizedDescription, title: "Could not open the capture")
            }
        }
    }

    /// Builds the model and the window and shows them. Re-checked after the load's awaits: an
    /// editor opened meanwhile is brought forward instead, and a record deleted meanwhile opens
    /// nothing.
    private func showEditor(recordID: UUID, image: ScaledImage) {
        if let open = editors[recordID] {
            open.present()
            return
        }
        guard let record = history.record(id: recordID) else { return }
        // A save-folder file names the window and gives it a proxy icon; a pending file in the
        // container is not shown.
        let fileURL = record.fileIsTemporary ? nil : record.fileURL
        let title = fileURL?.lastPathComponent
            ?? "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
        let model = EditorModel(recordID: recordID, image: image, renderer: RedactionRenderer.shared, defaults: .standard)
        let controller = EditorWindowController(model: model, actions: editorActions(for: recordID), title: title,
                                                representedURL: fileURL,
                                                cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
        controller.onClose = { [weak self] closed in self?.editorDidClose(closed) }
        editors[recordID] = controller
        Task { await RedactionRenderer.shared.warmUp(with: image.image) }
        controller.present()
    }

    /// Stubs that only log, so the window, tools and undo can be used before the actions exist:
    /// Task 12 wires Save Copy and Copy, Task 13 Save, Task 15 Upload. A stub reports failure, so
    /// nothing is marked saved and the close sheet's Save keeps the window open.
    private func editorActions(for recordID: UUID) -> EditorActions {
        EditorActions(
            save: { image in
                NSLog("Editor: Save of \(recordID) (\(image.image.width)x\(image.image.height) @\(image.scale)x) is not wired yet")
                return false
            },
            saveCopy: { _ in
                NSLog("Editor: Save Copy of \(recordID) is not wired yet")
                return false
            },
            copy: { _ in
                NSLog("Editor: Copy of \(recordID) is not wired yet")
            },
            upload: { _, asNew in
                NSLog("Editor: Upload\(asNew ? " as New" : "") of \(recordID) is not wired yet")
                return false
            })
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
