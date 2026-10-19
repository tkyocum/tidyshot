import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, output, upload, and history together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    let history: HistoryStore
    let credentialStore: any CredentialStore = KeychainCredentialStore()
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    private let overlay = QuickAccessController()
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)
    @ObservationIgnored private var queue: UploadQueue?
    /// Set after the first "Upload not configured" notification so later captures stay quiet.
    @ObservationIgnored private var warnedUploadNotConfigured = false

    private(set) var isCapturing = false
    private(set) var lastCaptureURL: URL?
    /// Records with an upload in flight; drives the menu bar icon.
    private(set) var uploadingIDs: Set<UUID> = []

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }
    var isUploading: Bool { !uploadingIDs.isEmpty }

    init() {
        let url = (try? HistoryStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: HistoryStore.fileName)
        history = HistoryStore(fileURL: url, retentionDays: { AppSettings.shared.historyRetentionDays })
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

    /// Encode, copy to clipboard (image now, or URL later), save, record in history, show the
    /// overlay, and start the upload. The local file is always written before the upload starts;
    /// if it cannot be written the image stays on the clipboard, so a capture is never dropped.
    func save(_ result: CaptureResult, appName: String?) async {
        let png: Data
        do {
            png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return
        }

        let wantsUpload = settings.afterCaptureAction == .upload
        // One keychain read per capture; the result is passed to startUpload below.
        let destination = wantsUpload ? makeDestination() : nil
        let copyImageNow: Bool
        if destination != nil {
            copyImageNow = settings.alsoCopyImageWhenUploading
        } else if wantsUpload {
            // Upload wanted but not possible: the clipboard gets the image instead of a URL.
            copyImageNow = true
        } else {
            copyImageNow = settings.copyImageToClipboard
        }
        if copyImageNow {
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
        }

        guard let url = await writeFile(png, result: result, appName: appName, alreadyOnClipboard: copyImageNow) else { return }
        if wantsUpload, destination == nil {
            warnUploadNotConfiguredOnce("Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard.")
        }
        if settings.playSound {
            SoundPlayer.playShutter()
        }
        lastCaptureURL = url

        let record = CaptureRecord(fileURL: url, pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: appName, uploadState: destination != nil ? .uploading(fraction: 0) : .none)
        history.add(record)
        showOverlay(for: record, image: result.image, scale: result.scale)

        if let destination {
            startUpload(recordID: record.id, data: png, destination: destination)
        } else if settings.showNotification {
            notifier.notifySaved(fileURL: url)
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

    /// Writes the PNG into the save folder. Returns nil after notifying, with the image left on
    /// the clipboard, when there is no folder or the write fails.
    private func writeFile(_ png: Data, result: CaptureResult, appName: String?, alreadyOnClipboard: Bool) async -> URL? {
        func keepOnClipboard() {
            if !alreadyOnClipboard {
                Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
            }
        }
        guard let folder = await saveLocation.ensureFolder() else {
            keepOnClipboard()
            notifier.notifyError("No folder was chosen. The image is on the clipboard.", title: "Not saved")
            return nil
        }
        do {
            let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: counter)
            return try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            keepOnClipboard()
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat) {
        guard settings.showOverlay else { return }
        let thumbnail = image.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
        overlay.show(record: record, thumbnail: thumbnail, corner: settings.overlayCorner,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds,
                     actions: QuickAccessController.Actions(
                        copy: { [weak self] id in self?.copyURL(recordID: id) },
                        retry: { [weak self] id in self?.retryUpload(recordID: id) },
                        reveal: { [weak self] id in self?.reveal(recordID: id) }))
    }

    /// The configured destination, or nil when the Upload tab is incomplete, no credentials are
    /// stored, or the keychain could not be read. "No item" is the normal not-configured case and
    /// stays silent here; any other keychain error is logged and reported once per launch.
    func makeDestination() -> S3Destination? {
        guard let config = settings.s3Config, config.isComplete else { return nil }
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
        return S3Destination(config: config, credentials: credentials)
    }

    /// Called by the Upload settings tab after saving, so the next upload uses the new settings.
    func destinationDidChange() {
        queue = nil
    }

    /// Enqueues `data` for `recordID`. `destination` is only used when the queue has to be
    /// created (first upload, or after the Upload tab was saved); callers read it once.
    private func startUpload(recordID: UUID, data: Data, destination: S3Destination) {
        if queue == nil {
            let config = destination.config
            queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(prefix: config.keyPrefix, length: config.keyLength),
                                events: { [weak self] event in self?.handle(event) })
        }
        guard let queue else { return }
        uploadingIDs.insert(recordID)
        history.update(id: recordID) { $0.uploadState = .uploading(fraction: 0) }
        refreshOverlay(for: recordID)
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png")
        Task { await queue.enqueue(job) }
    }

    /// Re-reads the file from the save folder and uploads it again.
    func retryUpload(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        guard let destination = makeDestination() else {
            markFailed(recordID, message: UploadError.notConfigured.localizedDescription)
            return
        }
        do {
            let data = try saveLocation.read(contentsOf: record.fileURL)
            startUpload(recordID: recordID, data: data, destination: destination)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL.lastPathComponent).localizedDescription)
        }
    }

    func retryFailedUploads() {
        for record in history.failedRecords {
            retryUpload(recordID: record.id)
        }
    }

    func copyURL(recordID: UUID) {
        guard let url = history.record(id: recordID)?.uploadedURL else { return }
        Pasteboard.copy(url: url)
    }

    func reveal(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
    }

    /// Menu action for a history row: copy the URL, retry a failed upload, or reveal the file.
    func historyItemSelected(_ recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        switch record.uploadState {
        case .uploaded: copyURL(recordID: recordID)
        case .failed: retryUpload(recordID: recordID)
        case .none, .uploading: reveal(recordID: recordID)
        }
    }

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

    private func handle(_ event: UploadEvent) {
        switch event {
        case .started(let id, let attempt):
            if attempt > 1 {
                NSLog("Upload retry \(attempt) for \(id)")
            }
        case .progress(let id, let fraction):
            history.setProgress(id: id, fraction: fraction)
            refreshOverlay(for: id)
        case .uploaded(let id, let url, let key):
            uploadingIDs.remove(id)
            history.update(id: id) { $0.uploadState = .uploaded(url: url, key: key) }
            Pasteboard.copy(url: url)
            if settings.showNotification {
                notifier.notifyUploaded(url: url)
            }
            refreshOverlay(for: id)
        case .failed(let id, let message):
            markFailed(id, message: message)
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
