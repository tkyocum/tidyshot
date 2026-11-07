import AppKit
import Observation

// The editor bridge (spec 2.6): opening editors and their Save, Save As…, Upload and Copy. Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
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
        guard !record.isTimeBased else {
            notifier.notifyError(EditorInput.videoText, title: failureTitle)
            return nil
        }
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

    /// The card's Annotate.
    func openEditorAfterMenuTracking(recordID: UUID) {
        afterMenuTracking { [weak self] in self?.openEditor(recordID: recordID) }
    }

    /// Builds the model and, through `environment.makeEditor`, the editor (the window in the app, a
    /// fake in the suite), and shows them. `openEditor` and `loadAndPresentEditor` have checked
    /// that no editor is open for the record and that it still exists.
    private func presentEditor(record: CaptureRecord, image: ScaledImage) {
        // A save-folder file names the window and gives it a proxy icon; a pending file in the
        // container is not shown.
        let fileURL = record.fileIsTemporary ? nil : record.fileURL
        let title = fileURL?.lastPathComponent
            ?? "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
        let model = EditorModel(recordID: record.id, image: image, renderer: RedactionRenderer.shared, defaults: settings.editorDefaults)
        let editor = environment.makeEditor(model, editorActions(for: record.id), title, fileURL,
                                            { [weak self] closed in self?.editorDidClose(closed) })
        editors[record.id] = editor
        pushEditorState(for: record.id)
        observeSaveFolderForEditors()
        Task { await RedactionRenderer.shared.warmUp(with: image.image) }
        editor.present()
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
                copy: { [clipboard] data in clipboard.copy(annotationClip: data) },
                paste: { [clipboard] in clipboard.annotationClipData() },
                canPaste: { [clipboard] in clipboard.hasAnnotationClip }),
            upload: { [weak self] image, asNew in
                await self?.editorUpload(recordID: recordID, image: image, asNew: asNew) ?? .refused
            },
            exportFailed: { [weak self] message, title in self?.notifier.notifyError(message, title: title) },
            unusableBackgroundImage: { [weak self] fileName in self?.notifyUnusableBackgroundImage(named: fileName) })
    }

    /// Tells the record's open editor, if any, what it may do now: the record as it is (nil once
    /// deleted or pruned), the save folder and whether a delete is running.
    func pushEditorState(for id: UUID) {
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
    /// the PNG to the target `EditorSaveTarget.plan` picks now, records the edit and the new file's
    /// size, replaces the thumbnail, applies the clipboard rule and pushes the editor's state.
    /// Returns false, with `Not saved` posted, when nothing was written.
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
        let editedAt = environment.now()
        history.update(id: recordID) {
            $0.recordLocalEdit(pixelWidth: image.image.width, pixelHeight: image.image.height, at: editedAt)
            $0.byteCount = png.count
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
        log("Save over failed: \(error.localizedDescription)")
        let changeCount: Int
        if let png {
            changeCount = clipboard.copy(image: image.image, pngData: png, scale: image.scale)
        } else {
            // No PNG: the TIFF is the only copy, at any size, made off the main actor.
            let tiff = await Task.detached(priority: .userInitiated) {
                Pasteboard.tiffData(of: image.image, scale: image.scale)
            }.value
            changeCount = clipboard.copy(tiffData: tiff)
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
    func replaceThumbnail(for id: UUID, from image: CGImage, editedAt: Date) {
        let store = thumbnails
        let name = store.fileName(for: id, editedAt: editedAt)
        let log = environment.log
        Task { [weak self] in
            let written = await Task.detached(priority: .utility) { () -> Bool in
                do {
                    guard let small = ThumbnailMaker.thumbnail(from: image) else { return false }
                    _ = try store.write(try ThumbnailMaker.pngData(small), fileName: name)
                    return true
                } catch {
                    log("Edited thumbnail failed: \(error.localizedDescription)")
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
            log("Save As failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return false
        }
        guard await writeSaveAsCopy(png, to: url) else { return false }
        await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        return true
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
            notifier.notifyError(Self.uploadNotConfiguredBody, title: "Upload not configured")
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
                log("Pending write failed: \(error.localizedDescription)")
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
        let location = queue?.location ?? destination.location
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
        // 5 to 7. Uploading, the prior link and any superseded object, in one write; the overlay and
        // the editor (through pushEditorState) show Uploading… now, before the first progress event;
        // then the live lane.
        startPlannedUpload(recordID: recordID, plan: plan, payload: .data(png), destination: destination)
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
    func deleteSupersededObjects(of id: UUID) async {
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
                log("Kept superseded \(ref.key): another capture shares it")
                settled.append(ref)
            } else if let reason = await deleteObjects([ref.key], at: ref.location) {
                log("Could not delete superseded \(ref.key): \(reason)")
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
                                            currentChangeCount: clipboard.changeCount) else { return }
        let tiff = await Task.detached(priority: .userInitiated) {
            Pasteboard.companionTIFF(of: image.image, scale: image.scale)
        }.value
        guard EditorClipboard.shouldReplace(owner: clipboardOwner, recordID: recordID,
                                            currentChangeCount: clipboard.changeCount) else { return }
        let changeCount = clipboard.copy(pngData: png, tiffData: tiff)
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
            copyOwnedImage(png: encoded.png, tiff: encoded.tiff, recordID: recordID)
            if settings.showNotification {
                let record = history.record(id: recordID)
                notifier.notify(title: "Image copied", body: record?.uploadedKey ?? record?.fileURL?.lastPathComponent ?? "")
            }
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Could not copy image")
        }
    }

    /// Drops a closed editor. When the last one closes, the renderer frees its caches.
    private func editorDidClose(_ editor: any EditorPresenting) {
        let id = editor.model.recordID
        guard editors[id] === editor else { return }
        editors[id] = nil
        if editors.isEmpty {
            Task { await RedactionRenderer.shared.clearCaches() }
        }
    }
}
