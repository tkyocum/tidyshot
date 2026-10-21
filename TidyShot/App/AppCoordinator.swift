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
    @ObservationIgnored private lazy var scrollCapture = ScrollCaptureController(engine: engine, settings: settings)
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
    /// The capture just taken and its pixels, kept while its overlay shows, so Annotate opens the
    /// editor at once: also while the upload runs, and after an upload-only capture's pending file
    /// is gone. The overlay's NSImage wraps the same CGImage, so this costs no memory. Cleared when
    /// the overlay closes, by the next capture and by `removeRecord`.
    @ObservationIgnored private var latestCapture: (id: UUID, image: ScaledImage)?
    /// Records whose editor image is loading, so a second Annotate does not open a second editor.
    @ObservationIgnored private var openingEditorIDs: Set<UUID> = []
    /// Set when the first same-key replace of this launch posts `EditorUploadPlan.cacheNote`.
    @ObservationIgnored private var postedCacheNote = false
    /// What TidyShot last put on the clipboard for a capture: set when `save(_:)` copies the
    /// image, by the editor's Copy, and after an edit replaced the clipboard. An edit of that
    /// capture replaces the clipboard only while the count still matches.
    @ObservationIgnored private var clipboardOwner: EditorClipboard.Owner?

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
        history.didPrune = { [weak self] records in self?.removeFiles(ofPruned: records) }
        overlay.onDidClose = { [weak self] id in self?.forgetLatestCapture(id) }
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
        KeyboardShortcuts.onKeyUp(for: .captureScrolling) { [weak self] in
            Task { await self?.captureScrolling() }
        }
        // Escape must never be swallowed outside a scrolling capture; the session enables it.
        KeyboardShortcuts.disable(.cancelScrollingCapture)
        // Live only while a scrolling session runs: the controller enables and disables it.
        KeyboardShortcuts.onKeyUp(for: .cancelScrollingCapture) { [weak self] in
            self?.scrollCapture.cancel()
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

    /// Capture Scrolling: select an area or a window's frame, run the scrolling session, and save
    /// the stitched image like any capture. During a session the shortcut is Start, then Done.
    func captureScrolling() async {
        // During a session the shortcut is Start, then Done (the lock is held meanwhile).
        if scrollCapture.isRunning {
            scrollCapture.advance()
            return
        }
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: .scrolling, content: content) else { return }
            guard case .area(let rect, let display) = selection else {
                selector.dismiss()
                return
            }
            guard rect.height >= CGFloat(ScrollCaptureLimits.minimumAreaHeightPoints) else {
                selector.dismiss()
                notifier.notifyError("Select an area at least 100 points tall.", title: "Scrolling capture")
                return
            }
            selector.dismiss()
            let outcome = await scrollCapture.run(rect: rect, display: display)
            if let notice = outcome.failureNotice {
                notifier.notifyError(notice.body, title: notice.title)
            }
            if let image = outcome.imageToSave {
                await save(CaptureResult(image: image.image, scale: image.scale,
                                         target: .area(rect: rect, display: display)))
            }
        }
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
                result = await capture(.area(rect: rect, display: display), excludingWindows: overlays, duringSelection: true)
            case .window(let window):
                result = await capture(.window(window), duringSelection: true)
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
    /// up the main actor.
    func save(_ result: CaptureResult) async {
        latestCapture = nil
        let image = result.scaled
        let action = settings.afterCaptureAction
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
            return
        }
        let png = encoded.png
        let copiedChangeCount: Int? = copyImageNow ? Pasteboard.copy(pngData: png, tiffData: encoded.tiff) : nil

        guard let record = await persist(png: png, image: image, action: action, destination: destination,
                                         alreadyOnClipboard: copyImageNow) else { return }
        if let copiedChangeCount {
            clipboardOwner = EditorClipboard.Owner(recordID: record.id, changeCount: copiedChangeCount)
        }
    }

    /// The capture save path behind `save(_:)`. Writes the file (save folder, or the container's
    /// `pending` folder in upload-only mode), warns once when upload is not configured, plays the
    /// sound, records the capture, starts the thumbnail, shows the overlay, and starts the upload
    /// or posts "saved". Returns nil when the file could not be written; the writer has then
    /// notified and left the image on the clipboard (`alreadyOnClipboard` says it is there
    /// already). Any other clipboard write is the caller's.
    private func persist(png: Data, image: ScaledImage, action: AfterCaptureAction, destination: S3Destination?,
                         alreadyOnClipboard: Bool) async -> CaptureRecord? {
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
        showOverlay(for: record, image: image.image, scale: image.scale)

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

    private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat) {
        guard settings.showOverlay else { return }
        // The well shows the top of a tall capture, as its thumbnail does. The crop shares the pixels.
        let shown = image.map { full in
            full.cropping(to: ThumbnailMaker.cropForThumbnail(CGSize(width: full.width, height: full.height))) ?? full
        }
        let thumbnail = shown.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
        overlay.show(record: record, thumbnail: thumbnail, corner: settings.overlayCorner,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds,
                     actions: QuickAccessController.Actions(
                        copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
                        retry: { [weak self] id in self?.retryUpload(recordID: id) },
                        reveal: { [weak self] id in self?.reveal(recordID: id) },
                        delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } },
                        annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) }))
        // After `show`: its `close()` of the previous panel has already reported that capture.
        latestCapture = image.map { (id: record.id, image: ScaledImage(image: $0, scale: scale)) }
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
        let job: UploadJob
        if let fixedKey {
            job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            fixedKey: fixedKey, cacheControl: "no-cache")
        } else {
            // The key is named now, not at capture time: a capture taken while no destination was
            // set up, and every retry, get a counter drawn when their upload starts. The date stays
            // the capture's own, so a retried upload lands in the capture's date folder.
            let counter = lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0
            job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, counter: counter))
        }
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

    /// The capture's PNG: the local file when it can be read, otherwise the uploaded object. The
    /// save folder is resolved here, on the main actor, and the file is read in a detached task,
    /// as `ThumbnailProvider` does: a temporary file in `pending` directly, a saved one through
    /// the folder's security scope.
    private func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data {
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
            return try await downloadImage(of: current, title: downloadTitle)
        }
        return try await downloadImage(of: record, title: downloadTitle)
    }

    /// The uploaded object's bytes, from where the record says it went, signed with the
    /// credentials stored now.
    private func downloadImage(of record: CaptureRecord, title: String) async throws -> Data {
        guard let key = record.uploadedKey else { throw CopyImageError.nothingToCopy }
        guard let location = record.objectLocation else { throw CopyImageError.unknownLocation }
        guard let credentials = loadCredentials() else { throw UploadError.notConfigured }
        if settings.showNotification {
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
        overlay.close(recordID: id)
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

    /// Thumbnails and temporary files of records dropped by retention, and their editors told the
    /// record is gone (`didPrune` runs after the store dropped them). Files in the save folder are
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
            // Upload-only mode: the temporary file has done its job. If it cannot be removed the
            // record keeps pointing at it, so Delete can still remove it later.
            var removedTemporaryFile = false
            if before.fileIsTemporary, let fileURL = before.fileURL {
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
        let image: ScaledImage
        do {
            let png = try await imageData(of: record, downloadTitle: "Opening the capture…")
            let decoded = await Task.detached(priority: .userInitiated) { () -> ScaledImage? in
                ImageEncoder.decode(png).map { ScaledImage(image: $0.image, scale: $0.scale) }
            }.value
            guard let decoded else { throw CopyImageError.notAnImage }
            image = decoded
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Could not open the capture")
            return
        }
        guard editors[record.id] == nil, let current = history.record(id: record.id) else { return }
        presentEditor(record: current, image: image)
    }

    /// Drops the retained image if it is `id`'s.
    private func forgetLatestCapture(_ id: UUID) {
        if latestCapture?.id == id {
            latestCapture = nil
        }
    }

    /// The overlay's Annotate: runs `openEditor` when the run loop is back in its default mode,
    /// after any menu tracking, as `RecentCapturesMenu.afterMenusClose` does for rows.
    private func openEditorAfterMenuTracking(recordID: UUID) {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { self.openEditor(recordID: recordID) }
        }
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
        overlay.close(recordID: record.id)
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
                self?.editorSaveAsSuggestion(recordID: recordID)
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
                let png = try ImageEncoder.pngData(from: image.image, scale: image.scale)
                try png.write(to: url, options: .atomic)
                return png
            }.value
        } catch {
            NSLog("Save As failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return false
        }
        await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        if settings.showNotification {
            notifier.notifySaved(fileURL: url, title: "Saved")
        }
        return true
    }

    /// The save panel's suggestion for `recordID`: its file name in the save folder, or the file
    /// name template's name with the current `{counter}` (none is drawn).
    private func editorSaveAsSuggestion(recordID: UUID) -> EditorNaming.SaveAsSuggestion {
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
