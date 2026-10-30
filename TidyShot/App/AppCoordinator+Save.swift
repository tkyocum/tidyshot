import AppKit

// The screenshot save funnel and the tail it shares with saveRecording (finishSave). Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// Encode, copy to clipboard (image now, or URL later), then `persist`: write the file, record
    /// in history, start the thumbnail, show the overlay, and start the upload. A file is always
    /// written before the upload starts; if it cannot be written the image stays on the clipboard,
    /// so a capture is never dropped. When the image goes on the clipboard, `clipboardOwner`
    /// records it for this capture, so an edit can replace it later. The PNG, and the TIFF when the
    /// image goes on the clipboard now, are made in a detached task, so a tall capture does not hold
    /// up the main actor. The intent's action replaces the General one; `copyOnly` leaves after
    /// `copyOnly(_:sender:)`; `then` opens the editor or a pin on the new record. A window capture
    /// first goes on its background when the Capture tab asks for one (`withWindowBackground`).
    /// Returns the record, or nil when nothing was recorded.
    @discardableResult
    func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord? {
        // Before the copy-only branch, so `action=copy` gets the background too.
        let result = await withWindowBackground(result)
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
            log("Encode failed: \(error.localizedDescription)")
            // Never drop a capture: without PNG data the clipboard still gets the image as TIFF.
            let tiff = await Task.detached(priority: .userInitiated) {
                Pasteboard.tiffData(of: image.image, scale: image.scale)
            }.value
            clipboard.copy(tiffData: tiff)
            notifier.notifyError(error.localizedDescription)
            return nil
        }
        let png = encoded.png
        let copiedChangeCount: Int? = copyImageNow ? clipboard.copy(pngData: png, tiffData: encoded.tiff) : nil

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

    /// A window capture on the Capture tab's background when `Add background to window captures` is
    /// on (spec 2.11), so the file, clipboard, thumbnail, card and upload all get it; any other
    /// capture as it is. The desktop picture is the window's display's, and composing runs detached.
    /// When it fails the capture keeps the plain window image and the reason is logged, with no
    /// notification, since nothing is lost.
    private func withWindowBackground(_ result: CaptureResult) async -> CaptureResult {
        guard settings.windowBackground, case .window = result.target else { return result }
        let style = settings.backgroundStyle
        let content = result.image
        let scale = result.scale
        let fillImage = await BackgroundFillSource.fillImage(for: style.fill, displayID: result.target.displayID)
        let composed = await Task.detached(priority: .userInitiated) {
            BackgroundCompositor.compose(content, style: style, scale: scale, fillImage: fillImage)
        }.value
        guard let composed else {
            let fits = BackgroundLayout.make(contentSize: CGSize(width: content.width, height: content.height),
                                             style: style, scale: scale) != nil
            let reason = fits ? "no bitmap could be made" : "the window is too large for a background"
            log("Background: \(reason), keeping the window capture")
            return result
        }
        return CaptureResult(image: composed, scale: scale, target: result.target)
    }

    /// The style editor's `Choose Image…` was given a file that does not decode (spec 2.11).
    func notifyUnusableBackgroundImage(named fileName: String) {
        notifier.notifyError(fileName, title: "Not a usable image")
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
            clipboard.copy(pngData: png, tiffData: encoded.tiff)
        } else {
            // As `save` does when the PNG fails: the TIFF alone, so the capture is not lost.
            let tiff = await Task.detached(priority: .userInitiated) {
                Pasteboard.tiffData(of: image.image, scale: image.scale)
            }.value
            clipboard.copy(tiffData: tiff)
        }
        if settings.playSound {
            environment.playShutter()
        }
        if settings.showNotification {
            notifier.notify(title: "Image copied", body: "\(image.image.width) × \(image.image.height) px",
                            subtitle: sender.map { "From \($0)" })
        }
    }

    /// The capture save path behind `save(_:intent:)`: writes the PNG (save folder, or the
    /// container's `pending` folder in upload-only mode), then runs the tail it shares with
    /// `saveRecording` (`finishSave`). Returns nil when the file could not be written; the writer
    /// has then notified and left the image on the clipboard (`alreadyOnClipboard` says it is there
    /// already). Any other clipboard write is the caller's.
    private func persist(png: Data, image: ScaledImage, action: AfterCaptureAction, destination: UploadTarget?,
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
        var warning: String?
        if action.uploads, destination == nil {
            warning = action == .uploadOnly
                ? "Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard."
                : "Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard."
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
        // The size is the PNG's, as written.
        let record = CaptureRecord(id: id, fileURL: fileURL, fileIsTemporary: action == .uploadOnly,
                                   pixelWidth: image.image.width, pixelHeight: image.image.height,
                                   appName: nil, uploadState: state, byteCount: png.count)
        // Save mode, or upload mode with no destination (as in Phase 2): the file was saved.
        let notification: SaveNotification = destination == nil && action != .uploadOnly
            ? .saved(title: "Screenshot saved") : .none
        await finishSave(record, image: image.image, scale: image.scale, captureDisplayID: captureDisplayID,
                         notConfiguredWarning: warning, showsCard: true, upload: destination,
                         payload: { .data(png) }, notification: notification)
        return record
    }

    /// What `finishSave` posts once the record is made, besides the upload's own notifications.
    enum SaveNotification {
        case none
        /// `Screenshot saved` or `Recording saved`, naming the file, when Show notification is on.
        /// A click reveals the file.
        case saved(title: String)
        /// Always posts, as `notifyError` does: `Not saved to a folder` for a recording.
        case notice(RecordingNotice)
    }

    /// The tail both save funnels share once the file is in place, `persist` for a screenshot's PNG
    /// and `saveRecording` for a recording's move, so they cannot drift: the not-configured
    /// warning, the shutter, the record, the thumbnail, the card, the upload and the notification.
    /// `image` is the capture, or a recording's poster: the thumbnail is made from it and the card
    /// shows it, but only a screenshot's becomes `latestCapture`. `payload` is made only when
    /// `upload` is given; one that cannot be made fails the upload as a retry does. With
    /// `awaitsThumbnail` (quit mode) it returns once the thumbnail is written.
    func finishSave(_ record: CaptureRecord, image: CGImage?, scale: CGFloat, captureDisplayID: CGDirectDisplayID,
                            notConfiguredWarning: String?, showsCard: Bool, upload destination: UploadTarget?,
                            payload: () throws -> UploadPayload, notification: SaveNotification,
                            awaitsThumbnail: Bool = false) async {
        if let notConfiguredWarning {
            warnUploadNotConfiguredOnce(notConfiguredWarning)
        }
        if settings.playSound {
            environment.playShutter()
        }
        history.add(record)
        let thumbnail = image.map { makeThumbnail(from: $0, for: record.id) }
        if showsCard {
            showOverlay(for: record, image: image, scale: scale, captureDisplayID: captureDisplayID,
                        retainsImage: !record.isTimeBased)
        }
        if let destination {
            do {
                startUpload(recordID: record.id, payload: try payload(), destination: destination)
            } catch {
                markFailed(record.id, message: UploadError.fileUnreadable(record.fileURL?.lastPathComponent ?? "no local file")
                    .localizedDescription)
            }
        }
        switch notification {
        case .none:
            break
        case .saved(let title):
            if settings.showNotification, let fileURL = record.fileURL {
                notifier.notifySaved(fileURL: fileURL, title: title)
            }
        case .notice(let notice):
            notifier.notifyError(notice.body, title: notice.title)
        }
        if awaitsThumbnail {
            await thumbnail?.value
        }
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
            log("Save failed: \(error.localizedDescription)")
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
            log("Pending write failed: \(error.localizedDescription)")
            keepOnClipboard(image, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    /// A failed write's fallback, so a capture or an edit is never dropped. It sets no
    /// `clipboardOwner`: no record was made for this image.
    func keepOnClipboard(_ image: ScaledImage, png: Data, alreadyOnClipboard: Bool) {
        if !alreadyOnClipboard {
            clipboard.copy(image: image.image, pngData: png, scale: image.scale)
        }
    }

    /// Makes and writes the 320 px thumbnail on a detached task, off the main actor, and stores
    /// its file name on the record when that finishes. Until then `ThumbnailProvider` makes one
    /// from the file itself; a failure is logged and it falls back the same way. If the record was
    /// deleted in the meantime, or an edit was saved since, the new file is removed again. The task
    /// is returned for quit mode, which awaits it so the thumbnail is written before the app quits.
    @discardableResult
    func makeThumbnail(from image: CGImage, for id: UUID) -> Task<Void, Never> {
        let store = thumbnails
        let log = environment.log
        return Task { [weak self] in
            let name = await Task.detached(priority: .utility) { () -> String? in
                do {
                    guard let small = ThumbnailMaker.thumbnail(from: image) else { return nil }
                    return try store.write(try ThumbnailMaker.pngData(small), id: id)
                } catch {
                    log("Thumbnail failed: \(error.localizedDescription)")
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
}
