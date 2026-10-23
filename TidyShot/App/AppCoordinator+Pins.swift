import AppKit

// Pin to screen and the retained capture (spec 2.9). Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// The record whose image is retained, for the Annotate flag on Recent Captures rows.
    var retainedCaptureID: UUID? { latestCapture?.id }

    var hasPins: Bool { pins.hasPins }
    var hasLockedPins: Bool { pins.hasLockedPins }
    func unlockPins() { pins.unlockAll() }
    func closePins() { pins.closeAll() }

    /// Pin to screen (spec 2.9): a floating copy of the capture. The newest capture's pixels are
    /// retained; any other is loaded with `loadImage(for:)`. An image over 8,192 px on a side is
    /// shown from `ThumbnailMaker.scaled` at the screen's pixel size; the pin keeps the capture's
    /// point size for Actual Size. A pin of the newest area capture opens over the spot it came
    /// from, any other centred on the pointer's screen. A second Pin on a pinned capture brings
    /// its pin forward. A capture deleted during the load is not pinned.
    func pin(recordID: UUID) async {
        guard let record = history.record(id: recordID), !record.isVideo, !deletingIDs.contains(recordID) else { return }
        guard !pins.bringToFront(recordID: recordID), pinningIDs.insert(recordID).inserted else { return }
        defer { pinningIDs.remove(recordID) }
        let image: ScaledImage
        if let retained = latestCapture, retained.id == recordID {
            image = retained.image
        } else {
            guard let loaded = await loadImage(for: record, downloadTitle: "Pinning the capture…",
                                               failureTitle: "Could not pin the capture") else { return }
            image = loaded
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var preferred: CGRect?
        if let area = latestCaptureArea, area.id == recordID {
            preferred = Geometry.appKitRect(fromCG: area.rect, primaryHeight: primaryHeight)
        }
        guard let screen = pinScreen(preferred: preferred) else { return }
        var shown = image.image
        let screenSide = Int((max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor).rounded())
        if let side = PinGeometry.downsampleMaxSide(pixelWidth: shown.width, pixelHeight: shown.height, screenPixelSide: screenSide) {
            let source = image
            guard let scaled = await Task.detached(priority: .userInitiated, operation: {
                ThumbnailMaker.scaled(source.image, maxSide: side)
            }).value else {
                notifier.notifyError("The capture is too large to pin.", title: "Could not pin the capture")
                return
            }
            shown = scaled
        }
        // Deleted, or its delete started, while the image loaded.
        guard history.record(id: recordID) != nil, !deletingIDs.contains(recordID) else { return }
        let imagePoints = CGSize(width: CGFloat(image.image.width) / image.scale,
                                 height: CGFloat(image.image.height) / image.scale)
        let frame = PinGeometry.initialFrame(imagePoints: imagePoints, preferred: preferred, visibleFrame: screen.visibleFrame)
        pins.open(recordID: recordID, image: shown, imagePoints: imagePoints, frame: frame, actions: pinActions())
    }

    /// The screen holding `preferred`'s centre, otherwise the pointer's, otherwise the first.
    private func pinScreen(preferred: CGRect?) -> NSScreen? {
        let screens = NSScreen.screens
        if let preferred, let screen = screens.first(where: { $0.frame.contains(CGPoint(x: preferred.midX, y: preferred.midY)) }) {
            return screen
        }
        return screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screens.first
    }

    /// The pin context menu's actions: all three work on the record, after the menu has closed.
    private func pinActions() -> PinController.Actions {
        PinController.Actions(
            copyImage: { [weak self] id in self?.afterMenuTracking { Task { await self?.copyImage(recordID: id) } } },
            saveAs: { [weak self] id in self?.saveAs(recordID: id) },
            annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) })
    }

    /// Drops the retained image if it is `id`'s.
    func forgetLatestCapture(_ id: UUID) {
        if latestCapture?.id == id {
            latestCapture = nil
            latestCaptureArea = nil
        }
    }
}
