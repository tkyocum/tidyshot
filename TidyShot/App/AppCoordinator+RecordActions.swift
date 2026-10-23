import AppKit

// The actions on a record from a card, a pin or a Recent Captures row: copy, open, reveal, Save As…. Their state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// Copies the link (`linkURL`, which also covers an editor upload that is running or was
    /// interrupted), or the local file for a capture that has no link. A recording's file goes
    /// through Copy File, so a pending file is referenced through its drag copy. A recording marked
    /// `Sound not muted` copies nothing: its file still holds the muted sound (design, Privacy rule).
    func copyLinkOrFile(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let url = record.linkURL {
            Pasteboard.copy(url: url)
        } else if record.uploadBlockedReason != nil {
            return
        } else if record.isTimeBased {
            Task { await copyFile(recordID: recordID) }
        } else if let fileURL = record.fileURL {
            Pasteboard.copy(fileURL: fileURL)
        }
    }

    /// Copy File (design, Quick Access card): a recording's file reference on the clipboard. A file
    /// in the save folder goes on as itself. A pending file goes on as its drag copy (the same stage
    /// and reuse as drag-out), so the reference does not dangle once the upload removes the
    /// pending file; its change count goes into `copyFileCounts`, so the drag clean-up leaves
    /// that copy while the clipboard holds it. A clean-up already due is cancelled first, as a
    /// press does, and with no card showing (a Recent Captures row) one is scheduled afterwards. A
    /// recording marked `Sound not muted` is never copied.
    func copyFile(recordID: UUID) async {
        guard let record = history.record(id: recordID), record.isTimeBased, record.uploadBlockedReason == nil,
              let fileURL = record.fileURL else { return }
        guard record.fileIsTemporary else {
            Pasteboard.copy(fileURL: fileURL)
            return
        }
        // Otherwise a clean-up due for a closed card could remove the copy this stage reuses.
        dragCleanups.removeValue(forKey: recordID)?.cancel()
        if let staged = await stageVideoDragFile(recordID: recordID) {
            copyFileCounts[recordID] = Pasteboard.copy(fileURL: staged)
        } else {
            NSLog("Copy File: \(fileURL.lastPathComponent) could not be staged")
        }
        // No card close will schedule the copy's clean-up.
        if !overlay.isShowing(recordID: recordID) {
            scheduleDragCleanup(recordID)
        }
    }

    /// A recording's thumbnail click: its local file in the default app (QuickTime), holding the
    /// save folder's scope for a file there, or, with only the upload left, its link.
    func openCapture(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let fileURL = record.fileURL {
            let scope = UploadPayload.scope(for: fileURL, isTemporary: record.fileIsTemporary,
                                            saveFolder: saveLocation.currentURL)
            let accessing = scope?.startAccessingSecurityScopedResource() ?? false
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                // The scope is held until the default app has the file.
                NSWorkspace.shared.open(fileURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if accessing { scope?.stopAccessingSecurityScopedResource() }
                    if let error {
                        NSLog("Could not open \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    }
                }
                return
            }
            if accessing { scope?.stopAccessingSecurityScopedResource() }
        }
        if let link = record.linkURL {
            NSWorkspace.shared.open(link)
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
        guard let record = history.record(id: recordID), !record.isTimeBased else { return }
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

    /// Save As… from a Quick Access card (and from a pin's menu, 6b): runs `saveCopy`, or
    /// `saveVideoCopy` for a recording, after any menu tracking (`afterMenuTracking`). A recording
    /// marked `Sound not muted` is never written anywhere.
    func saveAs(recordID: UUID) {
        guard history.record(id: recordID)?.uploadBlockedReason == nil else { return }
        afterMenuTracking { [weak self] in
            guard let self else { return }
            if self.history.record(id: recordID)?.isTimeBased == true {
                Task { await self.saveVideoCopy(recordID: recordID) }
            } else {
                Task { await self.saveCopy(recordID: recordID) }
            }
        }
    }

    /// A recording's Save As…: asks for a place (`.mpeg4Movie` only), then copies the movie there,
    /// never through memory. It copies, in a detached task, the local file under its scope, else
    /// the drag copy, else downloads the object with `download(key:to:)`, posting `Downloading
    /// <key>`. An existing file the panel confirmed is replaced with `FileManager.replaceItemAt`.
    /// `Saved` or `Not saved` posts as for an image. The record, its link, `lastCaptureURL` and
    /// the clipboard stay as they are.
    func saveVideoCopy(recordID: UUID) async {
        guard let target = await askSaveAsTarget(recordID: recordID) else { return }
        let record = target.record
        let url = target.url
        let local = record.fileURL.map {
            (file: $0, scope: UploadPayload.scope(for: $0, isTemporary: record.fileIsTemporary,
                                                  saveFolder: saveLocation.currentURL))
        }
        let drag = dragFiles
        await performSaveAs(to: url) {
            let copied = try await Task.detached(priority: .userInitiated) {
                try Self.copyVideo(from: local, orDragCopyOf: recordID, in: drag, to: url)
            }.value
            guard !copied else { return }
            let (key, destination) = try self.downloadSource(of: self.uploadedFallback(for: record),
                                                             title: "Saving a copy…")
            // Its file work runs where it is called.
            try await Task.detached(priority: .userInitiated) {
                try await destination.download(key: key, to: url)
            }.value
        }
    }

    /// Copies a recording to `destination`: the local file, holding its scope, when it exists,
    /// else the record's drag copy. False when there is neither, for the caller to download. The
    /// copy goes through `FileReplacement`, as a download does, so an existing destination is
    /// replaced with `replaceItemAt` and a failed copy leaves it as it was. Runs in a detached task.
    nonisolated private static func copyVideo(from local: (file: URL, scope: URL?)?, orDragCopyOf id: UUID,
                                              in dragFiles: DragFileStore, to destination: URL) throws -> Bool {
        let fileManager = FileManager.default
        var source: URL?
        let accessing = local?.scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { local?.scope?.stopAccessingSecurityScopedResource() } }
        if let file = local?.file, fileManager.isReadableFile(atPath: file.path(percentEncoded: false)) {
            source = file
        } else {
            source = dragFiles.stagedFile(id: id)
        }
        guard let source else { return false }
        try FileReplacement.put(at: destination) { try fileManager.copyItem(at: source, to: $0) }
        return true
    }

    /// Activates the app, asks for a place with the editor's suggestion, then writes the capture's
    /// PNG there unchanged (`imageData(of:)`: the local file, or a signed GET). A copy only: the
    /// record, its link, `lastCaptureURL` and the clipboard stay as they are.
    private func saveCopy(recordID: UUID) async {
        guard let target = await askSaveAsTarget(recordID: recordID) else { return }
        let png: Data
        do {
            png = try await imageData(of: target.record, downloadTitle: "Saving a copy…")
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return
        }
        await writeSaveAsCopy(png, to: target.url)
    }

    /// A card's Save As… panel, for an image and for a recording: activates the app and asks for a
    /// place with the record's suggestion (`EditorNaming.savePanel(for:)`). Then the record is read
    /// again, since the upload may have finished, or the capture been deleted, while the panel was
    /// open. Nil when the panel was cancelled or the capture is gone.
    private func askSaveAsTarget(recordID: UUID) async -> (record: CaptureRecord, url: URL)? {
        guard history.record(id: recordID) != nil else { return nil }
        let panel = EditorNaming.savePanel(for: saveAsSuggestion(recordID: recordID))
        // Reached from a non-activating card while another app is active; a plain activate() can
        // be refused and the panel would open behind that app (as in SaveLocation.chooseFolder).
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard await panel.begin() == .OK, let url = panel.url else { return nil }
        guard let record = history.record(id: recordID) else {
            NSLog("Save As: \(recordID) was deleted while the panel was open")
            return nil
        }
        return (record, url)
    }

    /// The capture's PNG: the local file when it can be read, otherwise the uploaded object. Copy
    /// Image, Annotate and the card's Save As… use it. Between the two, the record's drag copy
    /// (`DragFileStore`), which an upload-only capture keeps while its card shows; an edit removes
    /// it (`applyLocalEdit`). The save folder is resolved here, on the main actor, and the file is
    /// read in a detached task, as `ThumbnailProvider` does: a temporary file in `pending`
    /// directly, a saved one through the folder's security scope.
    func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data {
        // A recording is never read into memory.
        guard !record.isTimeBased else { throw CopyImageError.notAnImage }
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
        return try await downloadImage(of: uploadedFallback(for: record), title: downloadTitle)
    }

    /// The record to download when its local copy could not be read, an image's for
    /// `imageData(of:)` and a recording's for `saveVideoCopy`. It is read again: an upload-only
    /// capture whose upload finished during the read has lost its `pending` file and gained the
    /// key that `record` lacks.
    private func uploadedFallback(for record: CaptureRecord) throws -> CaptureRecord {
        let current = history.record(id: record.id) ?? record
        if record.fileURL != nil, current.uploadedKey == nil || current.objectLocation == nil {
            // The file is recorded but cannot be read, and there is no upload to fall back on.
            throw CopyImageError.unreadableFile
        }
        return current
    }

    /// The uploaded object's bytes, from where the record says it went (`downloadSource`).
    func downloadImage(of record: CaptureRecord, title: String?) async throws -> Data {
        let (key, destination) = try downloadSource(of: record, title: title)
        return try await destination.download(key: key)
    }

    /// Where the record's uploaded object is: its key, and the bucket the record says it went to
    /// signed with the credentials stored now. Posts `Downloading <key>` under `title` when
    /// notifications are on; a nil title downloads quietly (a restored card's drag file). Images
    /// download into memory (`downloadImage`), a recording to a file (`saveVideoCopy`).
    private func downloadSource(of record: CaptureRecord, title: String?) throws -> (key: String, destination: S3Destination) {
        guard let key = record.uploadedKey else { throw CopyImageError.nothingToCopy }
        guard let location = record.objectLocation else { throw CopyImageError.unknownLocation }
        guard let credentials = loadCredentials() else { throw UploadError.notConfigured }
        if let title, settings.showNotification {
            notifier.notify(title: title, body: "Downloading \(key)")
        }
        return (key, S3Destination(config: location.config, credentials: credentials))
    }

    func reveal(recordID: UUID) {
        guard let fileURL = history.record(id: recordID)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Runs `work` when the run loop is back in its default mode, after any menu tracking (the
    /// card's context menu, the status menu), as `RecentCapturesMenu.afterMenusClose` does for rows.
    func afterMenuTracking(_ work: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { work() }
        }
    }

    /// The one Save As… write, for the editor and for a card: `png` as it is, atomically, to a
    /// URL a save panel returned. The panel's URL is user-selected, so the sandbox grants the
    /// write, and no bookmark is kept. Posts `Saved` with the file name when notifications are on,
    /// or the error as `Not saved`. Touches no record.
    @discardableResult
    func writeSaveAsCopy(_ png: Data, to url: URL) async -> Bool {
        await performSaveAs(to: url) {
            try await Task.detached(priority: .userInitiated) {
                try png.write(to: url, options: .atomic)
            }.value
        }
    }

    /// Runs a Save As… write to `url`, an image's (`writeSaveAsCopy`) or a recording's
    /// (`saveVideoCopy`), and posts how it went: `Saved` with the file name when notifications
    /// are on, or the error as `Not saved`. False when the write threw.
    @discardableResult
    private func performSaveAs(to url: URL, _ write: () async throws -> Void) async -> Bool {
        do {
            try await write()
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
    /// A recording's template name uses the time it started, as its file name and key do, so its
    /// drag copy keeps one name from press to press.
    func saveAsSuggestion(recordID: UUID) -> EditorNaming.SaveAsSuggestion {
        let record = history.record(id: recordID)
        let startedAt = record?.timestamp ?? Date()
        return EditorNaming.saveAsSuggestion(
            for: record, saveFolder: saveLocation.currentURL,
            namer: FileNamer(template: settings.fileNameTemplate),
            recordingNamer: FileNamer(template: settings.recordingFileNameTemplate,
                                      fallbackName: FileNamer.recordingFallbackName, now: { startedAt }),
            currentCounter: settings.currentCounter)
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
