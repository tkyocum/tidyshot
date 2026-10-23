import AppKit

// The one delete path, and the teardown that pruning shares with it. Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// The one delete path, shared by the overlay and Recent Captures. One confirmation, Delete or
    /// Cancel, unless General's `Ask before deleting` is off (`CaptureDeletion.asksFirst`). Delete
    /// stops an in-flight upload, removes its objects, each from the bucket the record names for it
    /// (`CaptureDeletion.objects(for:)`), then the local file, the thumbnail
    /// and the record. When the storage `DELETE` fails (or there are no credentials to sign it),
    /// or the file in the save folder cannot be removed, a second alert offers to remove the record
    /// from history anyway, so a capture whose object or file cannot be deleted is never stuck. A local file that is already gone is not an
    /// error; a temporary file in `pending` that cannot be removed keeps the record, with a
    /// notification.
    func deleteCapture(recordID: UUID) async {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        // A Trim pass may be putting the file in place: refused before any alert (design, Write-time checks).
        if trimmingIDs.contains(recordID) {
            notifier.notifyError(CaptureDeletion.trimmingRefusal, title: "Not deleted")
            return
        }
        deletingIDs.insert(recordID)
        // The record's editor drops Save and Upload before the alert shows, through
        // `cancelUpload`, `deleteObjects` and the second alert, and learns the outcome either way.
        pushEditorState(for: recordID)
        defer {
            deletingIDs.remove(recordID)
            pushEditorState(for: recordID)
        }
        if CaptureDeletion.asksFirst(confirmBeforeDeleting: settings.confirmBeforeDeleting) {
            guard confirmDelete(of: record) else { return }
        }

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
    func deleteObjects(_ keys: [String], at location: ObjectLocation) async -> String? {
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
        optimizingVideoIDs.remove(id)
        fileUploadIDs.remove(id)
        videoClipboardCounts[id] = nil
        linkNotCopiedIDs.remove(id)
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
    func removePendingFile(at fileURL: URL, context: String, failureTitle: String? = nil) -> Bool {
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
    func removeFiles(ofPruned records: [CaptureRecord]) {
        for record in records {
            optimizingVideoIDs.remove(record.id)
            fileUploadIDs.remove(record.id)
            videoClipboardCounts[record.id] = nil
            linkNotCopiedIDs.remove(record.id)
            copyFileCounts[record.id] = nil
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
}
