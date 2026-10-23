import AppKit

// The Quick Access overlay: showing, restoring and refreshing cards. Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// With `retainsImage` the image becomes `latestCapture`, so Annotate opens at once. A
    /// recording's poster never does: a video cannot be annotated or pinned.
    func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat, captureDisplayID: CGDirectDisplayID,
                             retainsImage: Bool) {
        guard settings.showOverlay, let screen = overlayScreen(captureDisplayID: captureDisplayID) else { return }
        // The well shows the top of a tall capture, as its thumbnail does. The crop shares the pixels.
        let shown = image.map { full in
            full.cropping(to: ThumbnailMaker.cropForThumbnail(CGSize(width: full.width, height: full.height))) ?? full
        }
        let thumbnail = shown.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
        overlay.show(record: record, thumbnail: thumbnail, screen: screen,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds, actions: overlayActions())
        pushCardFlags(for: record.id)
        // After `show`: a card it pushed out of the stack has already reported its capture.
        if retainsImage {
            latestCapture = image.map { (id: record.id, image: ScaledImage(image: $0, scale: scale)) }
        }
    }

    /// Every card's buttons. Shared by new captures' cards and restored ones (Task 4).
    private func overlayActions() -> QuickAccessController.Actions {
        QuickAccessController.Actions(
            copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
            retry: { [weak self] id in self?.retryUpload(recordID: id) },
            reveal: { [weak self] id in self?.reveal(recordID: id) },
            delete: { [weak self] id in self?.afterMenuTracking { Task { await self?.deleteCapture(recordID: id) } } },
            annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) },
            pin: { [weak self] id in self?.afterMenuTracking { Task { await self?.pin(recordID: id) } } },
            saveAs: { [weak self] id in self?.saveAs(recordID: id) },
            copyImage: { [weak self] id in self?.afterMenuTracking { Task { await self?.copyImage(recordID: id) } } },
            open: { [weak self] id in self?.openCapture(recordID: id) },
            copyFile: { [weak self] id in self?.afterMenuTracking { Task { await self?.copyFile(recordID: id) } } },
            // Held with Trim (R2 plan, Gates): `pushCardFlags` leaves the card's `trimState` at its
            // default, so neither item shows and these are never called.
            trim: { _ in },
            uploadTrimmed: { _ in },
            prepareDrag: { [weak self] id in self?.prepareDragFile(recordID: id) },
            dragEnded: { [weak self] id, accepted in self?.dragDidEnd(recordID: id, accepted: accepted) })
    }

    /// The screen for the card stack under `settings.overlayDisplay`; nil without screens.
    private func overlayScreen(captureDisplayID: CGDirectDisplayID?) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let pointer = screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) }
        let index = OverlayScreenChoice.index(choice: settings.overlayDisplay, captureDisplayID: captureDisplayID,
                                              pointerIndex: pointer, screenDisplayIDs: screens.map { $0.displayID ?? 0 })
        return screens[index]
    }

    /// Every card close: the retained image goes with the newest card, a restorable close is
    /// remembered, and the card's drag folder is scheduled for removal.
    func overlayDidClose(_ id: UUID, reason: QuickAccessCloseReason) {
        forgetLatestCapture(id)
        if isRestoring, reason == .pushedOut {
            closedOverlays.didCloseBehind(id)
        } else {
            closedOverlays.didClose(id, reason: reason)
        }
        scheduleDragCleanup(id)
    }

    /// Whether Restore Closed Overlay has a card to bring back (the menu item's state).
    var canRestoreClosedOverlay: Bool {
        closedOverlays.hasRestorable(exists: { history.record(id: $0) != nil }, shown: Set(overlay.shownIDs).union(deletingIDs))
    }

    /// Restore Closed Overlay: the newest closed card whose capture still exists and is not
    /// showing, again at the corner of the stack's screen, with the record as it is now and its
    /// stored thumbnail. Annotate on it loads from the file or the bucket. It does not check
    /// `settings.showOverlay`: it is an explicit request.
    func restoreClosedOverlay() async {
        guard let id = closedOverlays.popRestorable(exists: { history.record(id: $0) != nil },
                                                    shown: Set(overlay.shownIDs).union(deletingIDs)),
              let record = history.record(id: id) else { return }
        let thumbnail = await thumbnailProvider.thumbnail(for: record)
        // Deleted (or being deleted) during the read, or shown by a second restore meanwhile.
        guard let current = history.record(id: id), !deletingIDs.contains(id), !overlay.isShowing(recordID: id),
              let screen = overlay.screen ?? overlayScreen(captureDisplayID: nil) else { return }
        isRestoring = true
        defer { isRestoring = false }
        overlay.show(record: current, thumbnail: thumbnail, screen: screen,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds, actions: overlayActions())
        pushCardFlags(for: id)
        // A record without a local file starts its quiet download now (never a recording's).
        prepareDragFile(recordID: id)
    }

    /// Pushes the record's current state into the overlay, if the overlay is showing it, and into
    /// the record's editor, so every upload progress, success, failure and retry reaches both.
    /// Every change to `optimizingVideoIDs` or `linkNotCopiedIDs` calls it too.
    func refreshOverlay(for id: UUID) {
        if let record = history.record(id: id) {
            overlay.update(record: record)
        }
        pushCardFlags(for: id)
        pushEditorState(for: id)
    }

    /// The card's two flags that are not on the record: `Optimizing…` and whether the URL was copied.
    /// Its `trimState` waits for the trim gate (R2 plan, Gates) and stays at its default.
    private func pushCardFlags(for id: UUID) {
        overlay.setOptimizing(optimizingVideoIDs.contains(id), for: id)
        overlay.setLinkWasCopied(!linkNotCopiedIDs.contains(id), for: id)
    }
}
