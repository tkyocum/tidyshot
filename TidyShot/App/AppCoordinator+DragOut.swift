import AppKit

// Drag-out from a card and the drag folders (spec 2.9, Gap 7). Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// How long a closed card's drag folder stays, for a receiver still reading the dropped file.
    static let dragCleanupDelay: Duration = .seconds(60)

    /// Stages the record's drag file for its card: at a press on the card, and when a restored
    /// card appears. The name and the source are worked out here; the copy runs detached. The
    /// card's `dragFileURL` is nil until it is done. A record with no readable file uses its kept
    /// copy, or, uploaded, a quiet download (`prefetchDragFile`). A recording goes through
    /// `stageVideoDragFile`, which reuses its copy and never downloads. A recording marked `Sound not
    /// muted` stages nothing, so its card has no file to drag.
    func prepareDragFile(recordID: UUID) {
        guard let record = history.record(id: recordID), overlay.isShowing(recordID: recordID),
              record.uploadBlockedReason == nil else { return }
        dragCleanups.removeValue(forKey: recordID)?.cancel()
        if record.isTimeBased {
            Task { await stageVideoDragFile(recordID: recordID) }
            return
        }
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
    /// its drag folder. A failure is only logged; the card then cannot be dragged. Never for a
    /// recording: a silent download of hundreds of MB on a click would surprise (R2).
    private func prefetchDragFile(recordID: UUID, name: String) async {
        guard !prefetchingDragIDs.contains(recordID), let record = history.record(id: recordID), !record.isTimeBased,
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
    /// move failed (logged); the caller then removes the pending file as before. A recording whose
    /// drag folder already holds a staged copy keeps that copy, which a Copy File reference may
    /// point at and an adopt would delete, so its pending file is removed instead (Gap 7).
    func keepForDragOut(_ fileURL: URL, record: CaptureRecord, url: URL, key: String) -> Bool {
        guard overlay.isShowing(recordID: record.id) else { return false }
        if record.isTimeBased, dragFiles.stagedFile(id: record.id) != nil { return false }
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
    func dragDidEnd(recordID: UUID, accepted: Bool) {
        guard accepted, settings.overlayCloseAfterDrag else { return }
        overlay.close(recordID: recordID, reason: .draggedOut)
    }

    /// A card closed, for any reason, or Copy File staged a copy with no card showing: the drag
    /// folder goes after `dragCleanupDelay`, unless a card shows the record again first
    /// (`prepareDragFile` and Copy File cancel this). While the clipboard still holds Copy File's
    /// reference to a recording's copy, it waits again, so the copy goes once the clipboard has
    /// moved on; the launch sweep is the backstop (Gap 7).
    func scheduleDragCleanup(_ id: UUID) {
        dragCleanups[id]?.cancel()
        dragCleanups[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.dragCleanupDelay)
            guard !Task.isCancelled, let self else { return }
            self.dragCleanups[id] = nil
            switch Self.dragCleanupStep(isShowing: self.overlay.isShowing(recordID: id),
                                        copyFileCount: self.copyFileCounts[id],
                                        changeCount: NSPasteboard.general.changeCount) {
            case .leave: break
            case .waitAgain: self.scheduleDragCleanup(id)
            case .remove: self.removeDragFolder(id)
            }
        }
    }

    /// A drag clean-up whose delay is over: nothing while a card shows the record (its close
    /// schedules the next one), another wait while the clipboard's change count is still the one
    /// Copy File left, and otherwise the folder goes.
    nonisolated static func dragCleanupStep(isShowing: Bool, copyFileCount: Int?, changeCount: Int) -> DragCleanupStep {
        if isShowing { return .leave }
        if let copyFileCount, copyFileCount == changeCount { return .waitAgain }
        return .remove
    }

    /// Removes the record's drag folder now (Delete, or the delayed clean-up), and makes any stage
    /// or download still running for it drop what it makes.
    func removeDragFolder(_ id: UUID) {
        dragCleanups.removeValue(forKey: id)?.cancel()
        dragGenerations[id, default: 0] += 1
        copyFileCounts[id] = nil
        dragFiles.remove(id: id)
    }

    /// A recording's drag copy (design, Drag-out with a local file), for a press on its card and
    /// for Copy File. The local file is staged with `reusingMatch`: a copy already there with the
    /// same size and modification date is kept, whatever its name, so a large file is copied
    /// across volumes once, and a Copy File reference to the copy stays good when the drag name
    /// worked out here changes (`{counter}` or `{random}` in the template, or the key's name once
    /// the upload ends). With no local file (an uploaded upload-only recording) the copy the
    /// folder holds is used as it is, under the name it has, so a Copy File reference to it stays
    /// good; nothing is downloaded (R2). One stage per record runs at a time, and a second caller
    /// waits for it. The card showing the record has no drag file while the copy runs, and gets
    /// the result.
    @discardableResult
    func stageVideoDragFile(recordID: UUID) async -> URL? {
        if let running = stagingVideoIDs[recordID] { return await running.value }
        guard let record = history.record(id: recordID) else { return nil }
        let name = DragFileName.name(for: record, suggestion: saveAsSuggestion(recordID: recordID))
        let generation = dragGenerations[recordID, default: 0]
        let store = dragFiles
        let source = record.fileURL
        let scope = record.fileIsTemporary ? nil : saveLocation.currentURL
        overlay.setDragFile(nil, for: recordID)
        let stage = Task { [weak self] () -> URL? in
            var staged = await Task.detached(priority: .userInitiated) { () -> URL? in
                if let source, let url = try? store.stage(id: recordID, name: name, from: source, scope: scope,
                                                          reusingMatch: true) {
                    return url
                }
                return store.stagedFile(id: recordID)
            }.value
            guard let self else { return nil }
            if self.dragGenerations[recordID, default: 0] != generation {
                // The folder was removed (Delete, the clean-up, a trim's write) or the pending file
                // adopted while the copy ran, so the copy can be of the file as it was. A card still
                // showing gets the folder's file only when it is a copy of the record's file now;
                // otherwise the folder goes, and the next press stages again, so a trimmed recording
                // is never dragged as its untrimmed copy. With no card, the folder this stage
                // recreated goes.
                if self.overlay.isShowing(recordID: recordID) {
                    staged = await self.currentDragCopy(of: recordID)
                } else {
                    self.dropStaleDragFolder(recordID)
                    staged = nil
                }
            }
            self.stagingVideoIDs[recordID] = nil
            if self.overlay.isShowing(recordID: recordID) {
                self.overlay.setDragFile(staged, for: recordID)
            }
            return staged
        }
        stagingVideoIDs[recordID] = stage
        return await stage.value
    }

    /// The record's drag copy after a stage that straddled a change to its folder: the folder's file
    /// when it is a copy of the record's file now (`DragFileStore.copy(id:matching:scope:)`). When it
    /// is not, or the record is gone, the folder is removed, unless it changed again meanwhile, and
    /// nil comes back.
    private func currentDragCopy(of recordID: UUID) async -> URL? {
        let store = dragFiles
        let generation = dragGenerations[recordID, default: 0]
        var copy: URL?
        if let record = history.record(id: recordID) {
            let source = record.fileURL
            let scope = record.fileIsTemporary ? nil : saveLocation.currentURL
            copy = await Task.detached(priority: .userInitiated) {
                store.copy(id: recordID, matching: source, scope: scope)
            }.value
        }
        if copy == nil, dragGenerations[recordID, default: 0] == generation {
            dragFiles.remove(id: recordID)
        }
        return copy
    }

    /// A stage or download finished after its folder was removed or replaced: unless a card shows
    /// the record, the folder it recreated goes again.
    private func dropStaleDragFolder(_ id: UUID) {
        guard !overlay.isShowing(recordID: id) else { return }
        dragFiles.remove(id: id)
    }
}

/// What a drag clean-up does when its delay is over (`AppCoordinator.dragCleanupStep`).
nonisolated enum DragCleanupStep: Equatable, Sendable {
    /// A card shows the record again.
    case leave
    /// The clipboard still holds Copy File's reference to the copy: wait another delay.
    case waitAgain
    case remove
}
