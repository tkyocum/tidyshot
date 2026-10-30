import AppKit

/// Why a Quick Access card closed (spec 2.9, Close and restore).
nonisolated enum QuickAccessCloseReason: Equatable, Sendable {
    /// The Close badge or the context menu's Close.
    case user
    case autoClose
    /// A newer card took the last place in the stack.
    case pushedOut
    /// Dragged out with Close after dragging out on (Task 6).
    case draggedOut
    /// The capture was deleted or removed from history.
    case deleted
    /// Annotate: the editor holds the capture now.
    case editorOpened

    /// Restore Closed Overlay brings these back; a deleted capture is gone and an edited one is
    /// in its editor.
    var isRestorable: Bool {
        switch self {
        case .user, .autoClose, .pushedOut, .draggedOut: true
        case .deleted, .editorOpened: false
        }
    }
}

/// Shows the Quick Access cards: a stack on one screen, newest at the configured corner. Each
/// card updates as its upload progresses and closes on its own countdown once the upload has
/// settled, restarted while the pointer is over it.
final class QuickAccessController {
    struct Actions {
        var copy: (UUID) -> Void
        var retry: (UUID) -> Void
        var reveal: (UUID) -> Void
        /// Deletes the capture everywhere after one confirmation (none with `Ask before deleting`
        /// off); see `AppCoordinator.deleteCapture`.
        var delete: (UUID) -> Void
        /// Opens the annotation editor; see `AppCoordinator.openEditor(recordID:)`. Stays enabled
        /// while the upload runs.
        var annotate: (UUID) -> Void
        /// Pins the capture on screen; see AppCoordinator.pin(recordID:).
        var pin: (UUID) -> Void
        /// Save As… for the card's button and menu item; see `AppCoordinator.saveAs(recordID:)`.
        var saveAs: (UUID) -> Void
        /// Copy Image for the card's menu item; see `AppCoordinator.copyImage(recordID:)`.
        var copyImage: (UUID) -> Void
        /// A recording's thumbnail click: the file in its default app, or the link; see
        /// `AppCoordinator.openCapture(recordID:)`.
        var open: (UUID) -> Void
        /// Copy File for a recording's menu item; see `AppCoordinator.copyFile(recordID:)`.
        var copyFile: (UUID) -> Void
        /// `Trim…` for an MP4's menu item; see `AppCoordinator.trimCapture(recordID:)`.
        var trim: (UUID) -> Void
        /// `Upload Trimmed` for a trimmed MP4 whose link is stale; see `AppCoordinator.uploadTrimmed(recordID:)`.
        var uploadTrimmed: (UUID) -> Void
        /// Stages the card's drag file; see `AppCoordinator.prepareDragFile(recordID:)`.
        var prepareDrag: (UUID) -> Void
        /// A drag-out ended; true when a receiver took the file.
        var dragEnded: (UUID, Bool) -> Void
        /// A drag past the threshold with no drag file: downloads an uploaded recording that has no
        /// local file; see `AppCoordinator.downloadDragFile(recordID:)`.
        var downloadForDrag: (UUID) -> Void
    }

    /// One card: its panel, its model and its auto-close countdown.
    private final class Card {
        let model: QuickAccessModel
        let panel: QuickAccessPanel
        let autoCloseSeconds: Double
        var closeTask: Task<Void, Never>?

        init(model: QuickAccessModel, autoCloseSeconds: Double) {
            self.model = model
            self.panel = QuickAccessPanel(model: model)
            self.autoCloseSeconds = autoCloseSeconds
        }

        var id: UUID { model.record.id }
    }

    /// Called with the record's id and the reason each time a card closes.
    var onDidClose: ((UUID, QuickAccessCloseReason) -> Void)?

    private let settings: AppSettings
    /// Newest first; index 0 sits at the corner.
    private var cards: [Card] = []
    /// The display the stack is on: an id, because AppKit replaces its `NSScreen` objects when
    /// the screen configuration changes.
    private var displayID: CGDirectDisplayID?
    /// The union of the frames from the last layout. The pointer inside it (plus the spacing)
    /// holds back the slide after a close.
    private var stackRegion = CGRect.null
    /// A close happened with the pointer over the stack; the cards close the gap once it leaves.
    private var relayoutPending = false
    private var pointerWatch: Task<Void, Never>?
    /// Lives as long as the controller, which `AppCoordinator.shared` owns for the app's life.
    private var screenObserver: (any NSObjectProtocol)?

    init(settings: AppSettings) {
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidChange() }
        }
    }

    /// The cards on screen, for a capture's `excludingWindows`.
    var windowNumbers: Set<CGWindowID> {
        Set(cards.compactMap { $0.panel.isVisible && $0.panel.windowNumber > 0 ? CGWindowID($0.panel.windowNumber) : nil })
    }

    /// The records the cards show, newest first.
    var shownIDs: [UUID] { cards.map(\.id) }

    /// Whether a card shows `recordID` (restore's check, and Task 6's drag-file hand-over).
    func isShowing(recordID: UUID) -> Bool {
        cards.contains { $0.id == recordID }
    }

    /// The stack's screen while a card shows.
    var screen: NSScreen? {
        cards.isEmpty ? nil : displayID.flatMap(CaptureEngine.screen(forDisplayID:))
    }

    /// Adds a card for `record` at the corner of `screen`, moving the stack there. A card that
    /// already shows the record moves to the corner with the new state instead.
    func show(record: CaptureRecord, thumbnail: NSImage?, screen: NSScreen, autoCloseSeconds: Double, actions: Actions) {
        let sameScreen = displayID == screen.displayID
        displayID = screen.displayID
        let card: Card
        if let index = cards.firstIndex(where: { $0.id == record.id }) {
            card = cards.remove(at: index)
            card.model.record = record
            if let thumbnail { card.model.thumbnail = thumbnail }
        } else {
            card = makeCard(record: record, thumbnail: thumbnail, autoCloseSeconds: autoCloseSeconds, actions: actions)
        }
        cards.insert(card, at: 0)
        trim(to: screen)
        if !card.panel.isVisible {
            let corner = QuickAccessStackLayout.frames(count: 1, cardSize: QuickAccessView.size,
                                                       corner: settings.overlayCorner, visibleFrame: screen.visibleFrame)[0]
            card.panel.setFrame(corner, display: false)
            card.panel.orderFrontRegardless()
        }
        cancelPendingRelayout()
        layout(on: screen, animated: sameScreen)
        if card.model.isSettled {
            scheduleClose(card)
        } else {
            card.closeTask?.cancel()
            card.closeTask = nil
        }
    }

    /// Pushes a new record state into the card that shows that record, if any.
    func update(record: CaptureRecord) {
        guard let card = cards.first(where: { $0.id == record.id }) else { return }
        card.model.record = record
        if card.model.isSettled {
            scheduleClose(card)
        } else {
            card.closeTask?.cancel()
            card.closeTask = nil
        }
    }

    /// Tells the card showing `recordID` whether its recording waits for Clop (`Optimizing…`).
    /// Does nothing when no card shows the record.
    func setOptimizing(_ isOptimizing: Bool, for recordID: UUID) {
        guard let model = cards.first(where: { $0.id == recordID })?.model, model.isOptimizing != isOptimizing else { return }
        model.isOptimizing = isOptimizing
    }

    /// Tells the card showing `recordID` its drag-out download's status (`Downloading…` or `Download
    /// failed`), or nil for none. Does nothing when no card shows the record.
    func setDownloading(_ status: DragDownloadStatus?, for recordID: UUID) {
        guard let model = cards.first(where: { $0.id == recordID })?.model, model.dragDownload != status else { return }
        model.dragDownload = status
    }

    /// Tells the card showing `recordID` whether its URL replaced the clipboard (`URL copied`) or
    /// not (`Uploaded`). Does nothing when no card shows the record.
    func setLinkWasCopied(_ linkWasCopied: Bool, for recordID: UUID) {
        guard let model = cards.first(where: { $0.id == recordID })?.model, model.linkWasCopied != linkWasCopied else { return }
        model.linkWasCopied = linkWasCopied
    }

    /// Tells the card showing `recordID` its `Trim…` and `Upload Trimmed` items, and whether a Trim
    /// pass writes its file. Does nothing when no card shows the record.
    func setTrimState(_ trimState: RecordingTrim.MenuState, for recordID: UUID) {
        guard let model = cards.first(where: { $0.id == recordID })?.model, model.trimState != trimState else { return }
        model.trimState = trimState
    }

    /// Shows a new thumbnail on the card showing `recordID`: a trimmed recording's poster, or nil for
    /// the placeholder, as a row with no thumbnail shows. Does nothing when no card shows the record.
    func setThumbnail(_ thumbnail: NSImage?, for recordID: UUID) {
        cards.first { $0.id == recordID }?.model.thumbnail = thumbnail
    }

    /// Hands the card showing `recordID` its staged drag file, or nil while one is being made.
    /// Does nothing when no card shows the record.
    func setDragFile(_ url: URL?, for recordID: UUID) {
        cards.first { $0.id == recordID }?.model.dragFileURL = url
    }

    /// Closes the card that shows `recordID`: `.deleted`, `.editorOpened`, or `.draggedOut` (Task 6).
    func close(recordID: UUID, reason: QuickAccessCloseReason) {
        guard let card = cards.first(where: { $0.id == recordID }) else { return }
        closeCard(card, reason: reason)
        closeGap()
    }

    private func makeCard(record: CaptureRecord, thumbnail: NSImage?, autoCloseSeconds: Double, actions: Actions) -> Card {
        let model = QuickAccessModel(record: record, thumbnail: thumbnail)
        let id = record.id
        model.onCopy = { actions.copy(id) }
        model.onRetry = { actions.retry(id) }
        model.onReveal = { actions.reveal(id) }
        model.onDelete = { actions.delete(id) }
        model.onAnnotate = { actions.annotate(id) }
        model.onPin = { actions.pin(id) }
        model.onSaveAs = { actions.saveAs(id) }
        model.onCopyImage = { actions.copyImage(id) }
        model.onOpen = { actions.open(id) }
        model.onCopyFile = { actions.copyFile(id) }
        model.onTrim = { actions.trim(id) }
        model.onUploadTrimmed = { actions.uploadTrimmed(id) }
        model.onPrepareDrag = { actions.prepareDrag(id) }
        model.onDragEnded = { accepted in actions.dragEnded(id, accepted) }
        model.onDownloadForDrag = { actions.downloadForDrag(id) }
        let card = Card(model: model, autoCloseSeconds: autoCloseSeconds)
        model.onClose = { [weak self, weak card] in
            // After the context menu's tracking, and outside the hosting view's own click.
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    guard let self, let card else { return }
                    self.closeCard(card, reason: .user)
                    self.closeGap()
                }
            }
        }
        return card
    }

    /// Takes `card` off screen and out of the stack and reports it with `reason`. The other cards
    /// stay put.
    private func closeCard(_ card: Card, reason: QuickAccessCloseReason) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: index)
        card.closeTask?.cancel()
        card.closeTask = nil
        card.panel.orderOut(nil)
        onDidClose?(card.id, reason)
    }

    /// Closes the oldest cards until the stack fits `screen` and `settings.overlayMaxCards`.
    private func trim(to screen: NSScreen) {
        let capacity = QuickAccessStackLayout.capacity(cardHeight: QuickAccessView.size.height,
                                                       visibleHeight: screen.visibleFrame.height,
                                                       limit: settings.overlayMaxCards)
        while cards.count > capacity, let oldest = cards.last {
            closeCard(oldest, reason: .pushedOut)
        }
    }

    /// Moves every card to its slot; a card already there is not touched.
    private func layout(on screen: NSScreen, animated: Bool) {
        let frames = QuickAccessStackLayout.frames(count: cards.count, cardSize: QuickAccessView.size,
                                                   corner: settings.overlayCorner, visibleFrame: screen.visibleFrame)
        stackRegion = frames.reduce(CGRect.null) { $0.union($1) }
        let moves = zip(cards, frames).filter { $0.0.panel.frame != $0.1 }
        guard !moves.isEmpty else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                for (card, frame) in moves {
                    card.panel.animator().setFrame(frame, display: true)
                }
            }
        } else {
            for (card, frame) in moves {
                card.panel.setFrame(frame, display: true)
            }
        }
    }

    /// After a close: the cards slide into the gap now, or once the pointer has left the stack.
    private func closeGap() {
        guard !cards.isEmpty, let screen = stackScreen() else {
            cancelPendingRelayout()
            return
        }
        if pointerIsOverStack {
            relayoutPending = true
            watchPointer()
        } else {
            cancelPendingRelayout()
            trim(to: screen)
            layout(on: screen, animated: true)
        }
    }

    private var pointerIsOverStack: Bool {
        let spacing = QuickAccessStackLayout.spacing
        return !stackRegion.isNull && stackRegion.insetBy(dx: -spacing, dy: -spacing).contains(NSEvent.mouseLocation)
    }

    /// Polls every 250 ms while a slide is pending, and runs it once the pointer is outside.
    private func watchPointer() {
        guard pointerWatch == nil else { return }
        pointerWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                guard self.relayoutPending else {
                    self.pointerWatch = nil
                    return
                }
                if !self.pointerIsOverStack {
                    self.pointerWatch = nil
                    self.closeGap()
                    return
                }
            }
        }
    }

    private func cancelPendingRelayout() {
        relayoutPending = false
        pointerWatch?.cancel()
        pointerWatch = nil
    }

    /// The stack's screen, or screen 0 when it is gone.
    private func stackScreen() -> NSScreen? {
        displayID.flatMap(CaptureEngine.screen(forDisplayID:)) ?? NSScreen.screens.first
    }

    /// A display was added, removed or rearranged, or the Dock or menu bar changed the visible
    /// frame: lay the stack out again at once, on its screen or screen 0.
    private func screensDidChange() {
        guard !cards.isEmpty, let screen = stackScreen() else { return }
        displayID = screen.displayID
        cancelPendingRelayout()
        trim(to: screen)
        layout(on: screen, animated: false)
    }

    /// Waits the card's `autoCloseSeconds`; while the pointer is over the card, or a drag-out
    /// from it or its drag-out download runs, the countdown restarts (as `scheduleClose` did for
    /// the one panel).
    private func scheduleClose(_ card: Card) {
        card.closeTask?.cancel()
        card.closeTask = nil
        let seconds = card.autoCloseSeconds
        guard seconds > 0 else { return }
        card.closeTask = Task { [weak self, weak card] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                // The pointer's place now, not the last hover event: a card that slid away or
                // under a still pointer is judged where it is. A card never closes under a
                // running drag-out session or download.
                if let panel = card?.panel, panel.frame.contains(NSEvent.mouseLocation) { continue }
                if let model = card?.model,
                   DragDownloadRule.keepsCardOpen(isDraggingOut: model.isDraggingOut,
                                                  isDownloading: model.isDownloadingForDrag) { continue }
                break
            }
            guard !Task.isCancelled, let self, let card else { return }
            self.closeCard(card, reason: .autoClose)
            self.closeGap()
        }
    }
}

/// What the coordinator asks of the card stack (harness design 2.2): `QuickAccessController` in the
/// app, a fake in the suite. `QuickAccessController.Actions` stays where it is.
protocol QuickAccessCards: AnyObject {
    var windowNumbers: Set<CGWindowID> { get }
    var shownIDs: [UUID] { get }
    var screen: NSScreen? { get }
    var onDidClose: ((UUID, QuickAccessCloseReason) -> Void)? { get set }
    func isShowing(recordID: UUID) -> Bool
    func show(record: CaptureRecord, thumbnail: NSImage?, screen: NSScreen, autoCloseSeconds: Double,
              actions: QuickAccessController.Actions)
    func update(record: CaptureRecord)
    func setOptimizing(_ isOptimizing: Bool, for recordID: UUID)
    func setDownloading(_ status: DragDownloadStatus?, for recordID: UUID)
    func setLinkWasCopied(_ linkWasCopied: Bool, for recordID: UUID)
    func setTrimState(_ trimState: RecordingTrim.MenuState, for recordID: UUID)
    func setThumbnail(_ thumbnail: NSImage?, for recordID: UUID)
    func setDragFile(_ url: URL?, for recordID: UUID)
    func close(recordID: UUID, reason: QuickAccessCloseReason)
}

extension QuickAccessController: QuickAccessCards {}
