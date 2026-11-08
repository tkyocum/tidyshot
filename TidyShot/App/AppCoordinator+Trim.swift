import AppKit
import AVFoundation

// Trim (design, Trim): the window, the pass that writes the trimmed recording, its upload, and what the
// card and the row offer. Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// Whether an upload destination is set up, for `Trim…`, the sheet and `Upload Trimmed` (plan,
    /// Gap 9). It never reads the keychain: the write itself calls `makeDestination()`.
    var hasUploadDestination: Bool {
        settings.s3Config?.isComplete == true
    }

    /// The card's and the row's Trim items for `record`, from the save folder, the destination and
    /// whether the record is being deleted or trimmed.
    func trimMenuState(for record: CaptureRecord) -> RecordingTrim.MenuState {
        RecordingTrim.menuState(record, saveFolder: saveLocation.currentURL, hasDestination: hasUploadDestination,
                                isDeleting: deletingIDs.contains(record.id), isTrimming: trimmingIDs.contains(record.id))
    }

    // MARK: The window

    /// `Trim…` from a card or a Recent Captures row, run once menu tracking has ended. An open window
    /// comes forward. Otherwise, while the menu rule allows it, the window opens on the recording
    /// (design, Source file): a pending file directly, a save-folder file under the folder's scope,
    /// held until the window closes, or the uploaded object downloaded to `tmp/Trim/<id>.mp4`.
    /// Nothing to read, or a sheet that would have no button, posts `Not trimmed` with the reason
    /// (`RecordingTrim.openRefusal`, given the source worked out here, which the window then opens).
    func trimCapture(recordID: UUID) {
        if let open = trimWindows[recordID] {
            open.present()
            return
        }
        guard !openingTrimIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        let source = EditorInput.fileSource(for: record, saveFolder: saveLocation.currentURL)
        if let reason = RecordingTrim.openRefusal(for: record, source: source, saveFolder: saveLocation.currentURL,
                                                  hasDestination: hasUploadDestination) {
            notifier.notifyError(reason, title: RecordingTrim.notTrimmedTitle)
            return
        }
        // Uploading, being deleted or trimmed: the item is disabled.
        guard trimMenuState(for: record).canTrim else { return }
        switch source {
        case .pendingFile(let fileURL):
            presentTrimWindow(for: record, fileURL: fileURL, scope: nil)
        case .saveFolderFile(let fileURL):
            // `fileSource` gives a save-folder file only with a folder.
            guard let folder = saveLocation.currentURL else { return }
            let accessing = folder.startAccessingSecurityScopedResource()
            presentTrimWindow(for: record, fileURL: fileURL, scope: accessing ? folder : nil)
        case .download:
            openingTrimIDs.insert(recordID)
            Task { await downloadAndPresentTrimWindow(for: record) }
        case .retained, .unavailable:
            // Never reached: `fileSource` never gives `.retained`, and `openRefusal` posted
            // `.unavailable`'s reason above.
            break
        }
    }

    /// Downloads the uploaded object to `tmp/Trim/<id>.mp4`, which it makes first, posting `Downloading
    /// <key>` under `Opening the recording…` (plan, Gap 9), then opens the window unless the record was
    /// deleted meanwhile. A failed download posts `Not trimmed` with the error.
    private func downloadAndPresentTrimWindow(for record: CaptureRecord) async {
        let id = record.id
        defer { openingTrimIDs.remove(id) }
        let fileURL = RecordingTrim.downloadURL(for: id)
        do {
            let (key, destination) = try downloadSource(of: record, title: "Opening the recording…")
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.createDirectory(at: RecordingTrim.directory, withIntermediateDirectories: true)
                try await destination.download(key: key, to: fileURL)
            }.value
        } catch {
            log("Trim: the download for \(id) failed: \(error.localizedDescription)")
            notifier.notifyError(RecordingTrim.failureText(for: error), title: RecordingTrim.notTrimmedTitle)
            return
        }
        guard trimWindows[id] == nil, let current = history.record(id: id) else {
            await Task.detached(priority: .utility) { RecordingTrim.removeWorkFiles(of: id) }.value
            return
        }
        presentTrimWindow(for: current, fileURL: fileURL, scope: nil)
    }

    /// Opens the record's Trim window on `fileURL`. `scope` is the save folder whose access the window
    /// holds; its close releases it.
    private func presentTrimWindow(for record: CaptureRecord, fileURL: URL, scope: URL?) {
        let id = record.id
        // A save-folder file names the window, as the editor's does; a pending file in the container is not shown.
        let title = (record.fileIsTemporary ? nil : record.fileURL?.lastPathComponent)
            ?? "Recording \(record.timestamp.formatted(date: .omitted, time: .shortened))"
        let controller = TrimWindowController(recordID: id, fileURL: fileURL, title: title,
                                              pixelSize: CGSize(width: record.pixelWidth, height: record.pixelHeight))
        controller.onRange = { [weak self, weak controller] start, end in
            guard let self, let controller else { return }
            Task { await self.trimRangeChosen(start: start, end: end, in: controller) }
        }
        controller.onFailure = { [weak self, weak controller] message in
            self?.notifier.notifyError(message, title: RecordingTrim.notTrimmedTitle)
            controller?.close()
        }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.trimWindowDidClose(controller, scope: scope)
        }
        trimWindows[id] = controller
        controller.present()
    }

    /// The trim bar's `Trim`: the range, then the save sheet from the live record, the Save target and
    /// whether a destination is set (design, The sheet). A range under half a second, and the sheet's
    /// `Cancel`, close the window.
    private func trimRangeChosen(start: CMTime, end: CMTime, in controller: TrimWindowController) async {
        let id = controller.recordID
        guard trimWindows[id] === controller else { return }
        let duration = controller.duration
        guard duration.isNumeric else {
            notifier.notifyError(RecordingTrimError.couldNotRead.localizedDescription, title: RecordingTrim.notTrimmedTitle)
            controller.close()
            return
        }
        guard let range = RecordingTrim.range(start: start, end: end, duration: duration) else {
            notifier.notifyError(RecordingTrim.tooShortText, title: RecordingTrim.notTrimmedTitle)
            controller.close()
            return
        }
        guard let record = history.record(id: id) else {
            controller.close()
            return
        }
        let plan = EditorSaveTarget.plan(for: record, saveFolder: saveLocation.currentURL)
        guard let sheet = RecordingTrim.sheet(plan: plan, hasDestination: hasUploadDestination,
                                              hasLink: record.linkURL != nil) else {
            // The destination went while the window was open, and there is nothing to save over.
            if case .unavailable(let reason) = plan {
                notifier.notifyError(reason, title: RecordingTrim.notTrimmedTitle)
            }
            controller.close()
            return
        }
        let text = RecordingTrim.informativeText(kept: range.duration.seconds, of: duration.seconds, sheet: sheet)
        let button = await controller.askToSave(message: RecordingTrim.saveMessage, informativeText: text,
                                                buttons: sheet.buttons)
        // Closed under the sheet: deleted or pruned.
        guard trimWindows[id] === controller else { return }
        guard button != .cancel else {
            controller.close()
            return
        }
        startTrimPass(button, range: range, in: controller)
    }

    // MARK: The pass

    /// Save or Save and Upload (design, Write-time checks): the live record is checked, and for Save
    /// and Upload the destination read, before the marker is set and the pass starts in a task kept in
    /// `trimPasses`, which `Stop` and the window's close cancel before the put.
    private func startTrimPass(_ button: RecordingTrim.SheetButton, range: CMTimeRange, in controller: TrimWindowController) {
        let id = controller.recordID
        let plan = RecordingTrim.writePlan(button, record: history.record(id: id), saveFolder: saveLocation.currentURL,
                                           isDeleting: deletingIDs.contains(id))
        if case .refuse(let reason) = plan {
            notifier.notifyError(reason, title: RecordingTrim.notTrimmedTitle)
            controller.close()
            return
        }
        // With no credentials, nothing is written (plan, Gap 9). This only gates the pass: the upload
        // half reads the destination again, as Settings > Upload can change during the export.
        if button == .saveAndUpload, makeDestination() == nil {
            notifier.notifyError(Self.uploadNotConfiguredBody, title: "Upload not configured")
            controller.close()
            return
        }
        guard !trimmingIDs.contains(id), let record = history.record(id: id) else {
            controller.close()
            return
        }
        trimmingIDs.insert(id)
        refreshOverlay(for: id)
        let intervals = record.unmutedIntervals
        trimPasses[id] = Task { [weak self] in
            await self?.runTrimPass(button, range: range, unmutedIntervals: intervals, in: controller)
        }
    }

    /// The pass: the method, read from the source before any mute step; the `Trimming…` sheet for a
    /// re-encode; Save's export; the write-time checks again; the put; and the bookkeeping, then for
    /// Save and Upload the upload. A stop or a close before the put writes nothing. Once the put
    /// starts the pass runs to its end. Every exit goes through `endTrimPass`.
    private func runTrimPass(_ button: RecordingTrim.SheetButton, range: CMTimeRange, unmutedIntervals: [MuteInterval],
                             in controller: TrimWindowController) async {
        let id = controller.recordID
        let source = controller.fileURL
        let method: RecordingTrim.TrimMethod
        do {
            method = try await RecordingTrim.startsOnSyncSample(source, at: range.start) ? .passthrough : .reencode
        } catch {
            endTrimPass(id, controller: controller, failure: Task.isCancelled ? nil : error)
            return
        }
        if method == .reencode, !Task.isCancelled {
            controller.showProgress(onStop: { [weak self] in self?.trimPasses[id]?.cancel() })
        }
        let trimmed: URL
        do {
            trimmed = try await RecordingTrim.exportForSave(
                source, id: id, range: range, method: method, unmutedIntervals: unmutedIntervals,
                freeBytes: { [freeBytes = environment.freeBytes] in freeBytes(RecordingTrim.directory) },
                progress: { fraction in
                    Task { @MainActor in controller.setProgress(fraction) }
                })
        } catch {
            endTrimPass(id, controller: controller, failure: Task.isCancelled ? nil : error)
            return
        }
        // The trimmed file's length and size, read before the put moves it (plan, Gap 11).
        let facts = await VideoValidation.inspect(trimmed)
        // Stopped, or the window closed: nothing is written. The window's close removes the file.
        guard !Task.isCancelled else {
            endTrimPass(id, controller: controller, failure: nil)
            return
        }
        // Right before the put: a record that started uploading, or a save folder changed in Settings,
        // during the export writes nothing.
        let plan = RecordingTrim.writePlan(button, record: history.record(id: id), saveFolder: saveLocation.currentURL,
                                           isDeleting: deletingIDs.contains(id))
        guard let target = RecordingTrim.putTarget(for: plan), let record = history.record(id: id) else {
            if case .refuse(let reason) = plan {
                notifier.notifyError(reason, title: RecordingTrim.notTrimmedTitle)
            }
            endTrimPass(id, controller: controller, failure: nil)
            return
        }
        controller.setStopEnabled(false)
        let marksStale = RecordingTrim.putMarksLinkStale(record)
        if marksStale {
            history.update(id: id) { $0.uploadIsStale = true }
        }
        let written: URL
        do {
            written = try await writeTrimmedFile(trimmed, to: target, id: id)
        } catch {
            // The record and its file are as they were.
            if marksStale {
                history.update(id: id) { $0.uploadIsStale = false }
            }
            endTrimPass(id, controller: controller, failure: error)
            return
        }
        // Pruning does not read the marker, so the record can be gone.
        switch RecordingTrim.afterPut(plan, fileURL: written, recordExists: history.record(id: id) != nil) {
        case .finish:
            finishTrimWrite(id: id, length: facts.duration, byteCount: facts.byteCount, range: range,
                            pendingFile: target == .newPendingFile ? written : nil)
            if button == .saveAndUpload {
                uploadTrimmedFile(of: id)
            }
        case .removePendingFile(let fileURL):
            removePendingFile(at: fileURL, context: "after a trim of a pruned record")
        case .keepFile:
            break
        }
        endTrimPass(id, controller: controller, failure: nil)
    }

    /// The put, in a detached task: over the Save target with `FileReplacement`, under the save
    /// folder's scope for a save-folder file, or moved in as `pending/<id>.mp4`. Returns the file
    /// written.
    private func writeTrimmedFile(_ trimmed: URL, to target: RecordingTrim.PutTarget, id: UUID) async throws -> URL {
        switch target {
        case .replace(let fileURL, let scope):
            try await Task.detached(priority: .userInitiated) {
                try RecordingTrim.putTrimmed(trimmed, over: fileURL, scope: scope)
            }.value
            return fileURL
        case .newPendingFile:
            let pending = pendingFiles
            return try await Task.detached(priority: .userInitiated) {
                try pending.moveIn(trimmed, id: id, ext: MediaKind.video.fileExtension)
            }.value
        }
    }

    /// Every exit of a pass (written, refused, failed, stopped, window closed): the marker goes and the
    /// card follows; a failure posts `Not trimmed` with its text (`Disk Full` for a full disk); the
    /// window closes, which removes `tmp/Trim/<id>*`. A stop or a close posts nothing.
    private func endTrimPass(_ id: UUID, controller: TrimWindowController, failure: (any Error)?) {
        trimPasses[id] = nil
        if trimmingIDs.remove(id) != nil {
            refreshOverlay(for: id)
        }
        if let failure {
            log("Trim: \(id) was not trimmed: \(failure.localizedDescription)")
            notifier.notifyError(RecordingTrim.failureText(for: failure), title: RecordingTrim.notTrimmedTitle)
        }
        controller.close()
    }

    /// The one bookkeeping step after any write, Save's put or Save and Upload's new pending file, so
    /// the two cannot drift (design, Save): `CaptureRecord.recordTrimWrite` in one update (the new
    /// pending file, the length, `editedAt`, the trimmed file's size, and `unmutedIntervals` emptied,
    /// as the trimmed file was cut from the muted copy); the drag copy dropped, as it holds the
    /// untrimmed video; the card refreshed; and the thumbnail made again from the new file. `length`
    /// and `byteCount` are the trimmed file's, 0 when unreadable.
    private func finishTrimWrite(id: UUID, length: TimeInterval, byteCount: Int64, range: CMTimeRange, pendingFile: URL?) {
        let editedAt = environment.now()
        history.update(id: id) { record in
            record.recordTrimWrite(length: length, byteCount: byteCount, rangeDuration: range.duration.seconds,
                                   pendingFile: pendingFile, at: editedAt)
        }
        removeDragFolder(id)
        overlay.setDragFile(nil, for: id)
        refreshOverlay(for: id)
        guard let record = history.record(id: id), let fileURL = record.fileURL else { return }
        let scope = UploadPayload.scope(for: fileURL, isTemporary: record.fileIsTemporary, saveFolder: saveLocation.currentURL)
        Task { [weak self] in
            let poster = await Self.posterFrame(of: fileURL, scope: scope)
            // A later trim, a delete or a prune got there first.
            guard let self, self.history.record(id: id)?.editedAt == editedAt else { return }
            if let poster {
                self.replaceThumbnail(for: id, from: poster, editedAt: editedAt)
            } else {
                self.dropThumbnail(of: id)
            }
            // With no poster the card shows the row's placeholder, not the untrimmed first frame.
            self.showCardPoster(poster, for: id)
        }
    }

    /// A trimmed recording whose poster could not be read keeps no thumbnail, rather than the
    /// untrimmed recording's first frame: the record names none, the provider drops what it cached,
    /// and the old file goes. The row then shows the placeholder, as `ThumbnailProvider` never makes a
    /// recording's thumbnail from its file, and so does a card showing it (Decided 2026-10-24, 11).
    private func dropThumbnail(of id: UUID) {
        let previous = history.record(id: id)?.thumbnailFileName
        history.update(id: id) { $0.thumbnailFileName = nil }
        thumbnailProvider.forget(id)
        if let previous {
            thumbnails.remove(fileName: previous)
        }
    }

    /// The trimmed recording's first frame, read holding `scope` when the file is in the save folder.
    @concurrent
    nonisolated private static func posterFrame(of fileURL: URL, scope: URL?) async -> CGImage? {
        await scope.withSecurityScope { await PosterFrame.image(of: fileURL) }
    }

    /// The window closed, for any reason: the pass is cancelled, which stops it before its put; once it
    /// has ended, the folder's scope is released and `tmp/Trim/<id>*` removed (design, Cleanup), unless
    /// a new window for the record has opened since, whose own close removes them. A window that is not
    /// the record's (none is replaced today) leaves the dictionary, the pass and the files alone, and
    /// its scope too goes only once the record's pass has ended, so each start has its stop and no
    /// pass loses the scope it reads under.
    private func trimWindowDidClose(_ controller: TrimWindowController, scope: URL?) {
        let id = controller.recordID
        let pass = trimPasses[id]
        let isCurrent = trimWindows[id] === controller
        if isCurrent {
            trimWindows[id] = nil
            pass?.cancel()
        }
        Task { [weak self] in
            await pass?.value
            scope?.stopAccessingSecurityScopedResource()
            guard isCurrent, let self, self.trimWindows[id] == nil, !self.openingTrimIDs.contains(id) else { return }
            await Task.detached(priority: .utility) { RecordingTrim.removeWorkFiles(of: id) }.value
        }
    }

    // MARK: Upload Trimmed

    /// `Upload Trimmed` (design, Stale link), run once menu tracking has ended: the upload half of Save
    /// and Upload for a trimmed MP4 whose link still shows the full recording. One action on the
    /// existing queue; its success clears `uploadIsStale`.
    func uploadTrimmed(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let refusal = Self.uploadTrimmedRefusal(for: record, saveFolder: saveLocation.currentURL,
                                                   isDeleting: deletingIDs.contains(recordID),
                                                   isTrimming: trimmingIDs.contains(recordID)) {
            notifier.notifyError(refusal, title: "Not uploaded")
            return
        }
        uploadTrimmedFile(of: recordID)
    }

    /// Why `Upload Trimmed` must not run, or nil: `uploadRefusal` (being trimmed, or marked `Sound not
    /// muted`), then the editor's Upload refusal (deleted, being deleted, uploading), then no local file,
    /// then a link that is not stale, as the menu shows the item only for a stale one (an upload that
    /// ended while the menu was open). A record with no link, which the menu never offers it for, is
    /// told so rather than that its link is current.
    nonisolated static func uploadTrimmedRefusal(for record: CaptureRecord, saveFolder: URL?, isDeleting: Bool,
                                                 isTrimming: Bool) -> String? {
        if let refusal = uploadRefusal(for: record, isTrimming: isTrimming) { return refusal }
        if let refusal = EditorAvailability.refusal(for: .upload, record: record, saveFolder: saveFolder,
                                                    isDeleting: isDeleting) {
            return refusal
        }
        guard record.hasLocalFile else { return UploadError.fileUnreadable("no local file").localizedDescription }
        guard record.uploadIsStale else {
            return record.linkURL == nil ? "This capture has no link to update." : linkShowsTrimText
        }
        return nil
    }

    /// `Upload Trimmed`'s refusal for a link that shows the file already.
    nonisolated static let linkShowsTrimText = "The link already shows the trimmed recording."

    /// The upload half (design, Save and Upload): the record's file over the link's own key
    /// (`EditorUploadPlan`, never as new), or as a first upload. The destination is read here, not
    /// when a pass started, so a Settings > Upload change during the export is followed; with none
    /// now it posts `Upload not configured`, and a trimmed file with a link keeps `uploadIsStale`.
    /// The clipboard's change count is taken first, so an unchanged clipboard gets the URL as after a
    /// save. `trimmingIDs` is cleared right before `startPlannedUpload` (the editor's Upload's last
    /// steps), in this main-actor turn, so `startUpload`'s trimming check passes and nothing else can
    /// start in between.
    private func uploadTrimmedFile(of id: UUID) {
        guard let record = history.record(id: id) else { return }
        guard let destination = makeDestination() else {
            notifier.notifyError(Self.uploadNotConfiguredBody, title: "Upload not configured")
            return
        }
        let location = queue?.location ?? destination.location
        let plan = EditorUploadPlan.plan(record: record, currentLocation: location,
                                         others: history.records.filter { $0.id != id }, asNew: false)
        if case .refuse(let reason) = plan {
            notifier.notifyError(reason, title: "Not uploaded")
            return
        }
        let payload: UploadPayload
        do {
            payload = try uploadPayload(for: record)
        } catch {
            notifier.notifyError(UploadError.fileUnreadable(record.fileURL?.lastPathComponent ?? "no local file")
                .localizedDescription, title: "Not uploaded")
            return
        }
        if case .newObject(_, let notice?) = plan {
            notifier.notify(title: "New link", body: notice)
        }
        videoClipboardCounts[id] = clipboard.changeCount
        trimmingIDs.remove(id)
        startPlannedUpload(recordID: id, plan: plan, payload: payload, destination: destination)
    }
}
