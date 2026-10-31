import AppKit
import Observation
import UniformTypeIdentifiers

/// The pasteboard as object copy and paste see it (4b). AppCoordinator implements it, because the
/// editor never touches the pasteboard.
struct EditorObjectClipboard {
    var copy: (Data) -> Void
    var paste: () -> Data?
    /// A type check only; validation calls it often.
    var canPaste: () -> Bool
}

/// What the editor's document actions do, provided by AppCoordinator: the editor never writes
/// files, never touches the pasteboard and never enqueues uploads. For Save and Save As… the Bool
/// says whether the edit was written, which is when the editor marks itself saved; Upload reports
/// an `EditorUploadOutcome`, which also says whether the window closes.
struct EditorActions {
    var save: (ScaledImage) async -> Bool
    /// Writes the edit to the URL the save panel returned.
    var saveAs: (ScaledImage, URL) async -> Bool
    /// The save panel's suggested name and folder, read when the panel opens.
    var saveAsSuggestion: () -> EditorNaming.SaveAsSuggestion
    var copy: (ScaledImage) async -> Void
    var objectClipboard: EditorObjectClipboard
    var upload: (ScaledImage, _ asNew: Bool) async -> EditorUploadOutcome
    /// An export that failed for a reason worth telling (`EditorExportFailure.message`), posted as
    /// an error notification under `title`: `Not saved`, `Not uploaded` or `Could not copy image`.
    var exportFailed: (_ message: String, _ title: String) -> Void
    /// The Background popover's `Choose Image…` was given a file that does not decode.
    var unusableBackgroundImage: (_ fileName: String) -> Void
}

/// What the coordinator asks of an open annotation editor (the editor seam): `EditorWindowController`
/// in the app, `FakeEditor` in the suite. Class-bound, so the registry keeps one object per record and
/// `editorDidClose` and the quit review compare by identity (`===`). Construction, and the close
/// callback, are `AppEnvironment.makeEditor`'s.
protocol EditorPresenting: AnyObject {
    /// The editor's document; the coordinator reads `recordID` and `hasUnsavedChanges`.
    var model: EditorModel { get }
    /// Brings the editor forward (activates the app).
    func present()
    /// The coordinator's push (`pushEditorState`): the record as it is now (nil once deleted or
    /// pruned), the save folder, and whether a delete is running.
    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)
    /// The unsaved-changes sheet, for the quit review. True when the editor may go.
    func askToSaveBeforeClosing() async -> Bool
}

/// One annotation editor window for one capture record: the window, the two stacked views, the
/// document actions, zoom, and the unsaved-changes sheet.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations {
    let model: EditorModel
    let canvasView: CanvasView
    private let baseView: BaseImageView
    /// Called from `windowWillClose(_:)`; AppCoordinator drops the editor from its registry.
    var onClose: ((EditorWindowController) -> Void)?

    private let actions: EditorActions
    /// The toolbar's popovers (EditorToolbar.swift), kept so only one is shown at a time.
    var colorPopover: NSPopover?
    var optionsPopover: NSPopover?
    var backgroundPopover: NSPopover?
    /// One document action at a time; another one beeps until it finishes.
    private var isPerformingAction = false
    /// What the editor may do now. Empty until the coordinator's first push, which presentEditor
    /// sends before the window shows.
    private(set) var available: Set<EditorAction> = []
    /// What ⌘S does now: write over the record's file, or open the save panel.
    private(set) var saveCommand: EditorSaveCommand = .saveAs
    /// What the background preview's fill was last rendered for, and the render under way.
    private var renderedFill: BackgroundFillKey?
    private var fillTask: Task<Void, Never>?
    /// The last desktop picture or custom image read, so a slider drag only redraws the fill.
    private var fillSource: (key: BackgroundFillKey, image: CGImage?)?
    /// Watches for a Space change, which can show another wallpaper; removed when the window closes.
    private var spaceObserver: NSObjectProtocol?

    #if DEBUG
    private static var loggedMainMenu = false
    #endif

    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, cascadeFrom: NSWindow?) {
        self.model = model
        self.actions = actions
        let baseView = BaseImageView(frame: .zero)
        baseView.image = model.base
        self.baseView = baseView
        let canvasView = CanvasView(model: model, baseView: baseView)
        self.canvasView = canvasView
        canvasView.objectClipboard = actions.objectClipboard

        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: true)
        window.toolbarStyle = .unified
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.title = title
        window.representedURL = representedURL
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        for view in [baseView, canvasView] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        window.contentView = container
        window.canvasView = canvasView
        window.initialFirstResponder = canvasView
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        installToolbar()
        placeWindow(cascadeFrom: cascadeFrom)
        observeEdited()
        observeBackgroundFill()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDesktopPicture() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Sizes the window to the capture's natural point size plus chrome, at least the toolbar's
    /// width (and 640x420) and within 90% of the visible frame of the screen under the mouse, and
    /// cascades it 22 pt from `previous`. The content never gets narrower than the toolbar, so no
    /// item moves into the overflow menu. No frame autosave. The chrome is measured from the
    /// window, so a toolbar attached before this call is included.
    private func placeWindow(cascadeFrom previous: NSWindow?) {
        guard let window, let content = window.contentView else { return }
        let minimumWidth = minimumToolbarContentWidth()
        window.contentMinSize.width = minimumWidth
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let chrome = CGSize(width: window.frame.width - content.frame.width,
                            height: window.frame.height - content.frame.height)
        let contentSize = EditorWindowGeometry.initialContentSize(
            imagePixels: CGSize(width: model.base.width, height: model.base.height), scale: model.scale,
            chrome: chrome, visibleFrame: visible, minimumWidth: minimumWidth)
        let size = CGSize(width: contentSize.width + chrome.width, height: contentSize.height + chrome.height)
        window.setFrame(EditorWindowGeometry.cascaded(from: previous?.frame, size: size, visibleFrame: visible),
                        display: false)
    }

    /// `isDocumentEdited` mirrors `hasUnsavedChanges`, re-registering on each change.
    private func observeEdited() {
        let edited = withObservationTracking {
            model.hasUnsavedChanges
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeEdited() }
        }
        window?.isDocumentEdited = edited
    }

    /// The codebase's activation idiom: a plain `activate()` is refused when called from the
    /// non-activating overlay.
    func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            window?.orderFrontRegardless()
        }
        #if DEBUG
        if !Self.loggedMainMenu {
            Self.loggedMainMenu = true
            NSLog("Editor: main menu items \(NSApp.mainMenu?.items.map(\.title) ?? [])")
        }
        #endif
    }

    // MARK: Record state

    /// The coordinator's push (`pushEditorState`): the record as it is now (nil once deleted or
    /// pruned), the save folder, and whether a delete is running.
    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) {
        let allowed = EditorAvailability.actions(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
        saveCommand = EditorSaveCommand.forSave(record: record, saveFolder: saveFolder)
        if allowed != available {
            available = allowed
            window?.toolbar?.validateVisibleItems()
        }
        let status = EditorAvailability.status(record: record, saveFolder: saveFolder, isDeleting: isDeleting) ?? ""
        if window?.subtitle != status {
            window?.subtitle = status
        }
    }

    /// The second guard: an action whose EditorAction is not available returns at once, whatever
    /// sent it (a menu, a toolbar item, or a shortcut that got past validation).
    private func permits(_ selector: Selector) -> Bool {
        EditorCommandGate.permits(NSStringFromSelector(selector), available: available)
    }

    // MARK: Document actions

    /// ⌘S: writes over the record's file, or runs Save As… when there is none to write over.
    @objc func saveDocument(_ sender: Any?) {
        canvasView.commitTextEditing()
        guard permits(#selector(saveDocument(_:))) else { return }
        runDocumentTask { await self.performSave() }
    }

    /// ⇧⌘S: always available, also while the record uploads or is deleted.
    @objc func saveDocumentAs(_ sender: Any?) {
        canvasView.commitTextEditing()
        guard permits(#selector(saveDocumentAs(_:))) else { return }
        runDocumentTask { await self.performSaveAs() }
    }

    /// ⌘C with nothing selected: copies the flattened image, like ⇧⌘C. With a selection CanvasView
    /// takes copy: first (object copy) and this is not reached.
    @objc func copy(_ sender: Any?) {
        guard permits(#selector(copy(_:))) else { return }
        copyImage(sender)
    }

    @objc func copyImage(_ sender: Any?) {
        canvasView.commitTextEditing()
        guard permits(#selector(copyImage(_:))) else { return }
        runDocumentTask {
            await self.exportAndDeliver(marksSaved: false, failureTitle: "Could not copy image") { image in
                await self.actions.copy(image)
                return true
            }
        }
    }

    /// ⌘U: uploads the edit at once. Once the upload is enqueued the window closes; the link
    /// reaches the clipboard when the upload finishes.
    @objc func uploadDocument(_ sender: Any?) {
        canvasView.commitTextEditing()
        guard permits(#selector(uploadDocument(_:))) else { return }
        runDocumentTask { await self.performUpload(asNew: false) }
    }

    /// ⌥⌘U, a shortcut only: as ⌘U, under a new link.
    @objc func uploadDocumentAsNew(_ sender: Any?) {
        canvasView.commitTextEditing()
        guard permits(#selector(uploadDocumentAsNew(_:))) else { return }
        runDocumentTask { await self.performUpload(asNew: true) }
    }

    /// One document action at a time: another one beeps until `work` finishes.
    private func runDocumentTask(_ work: @escaping () async -> Bool) {
        guard !isPerformingAction else {
            NSSound.beep()
            return
        }
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            _ = await work()
        }
    }

    /// ⌘S as `saveCommand` decides. True when the edit was written.
    private func performSave() async -> Bool {
        switch saveCommand {
        case .writeOver:
            await exportAndDeliver(marksSaved: true, failureTitle: "Not saved") { await self.actions.save($0) }
        case .saveAs:
            await performSaveAs()
        }
    }

    /// Save As…: an `NSSavePanel` sheet for a PNG, named and placed by the coordinator's
    /// suggestion. The document is flattened after the panel closes, so it is what was confirmed.
    /// False for Cancel or a failed write; the editor then stays as it was.
    private func performSaveAs() async -> Bool {
        guard let window else { return false }
        let panel = EditorNaming.savePanel(for: actions.saveAsSuggestion())
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return false }
        return await exportAndDeliver(marksSaved: true, failureTitle: "Not saved") { await self.actions.saveAs($0, url) }
    }

    /// Upload and Upload as New. The window closes without the unsaved-changes sheet when the
    /// outcome says so; a refusal keeps it open, and the coordinator's notification says why.
    private func performUpload(asNew: Bool) async -> Bool {
        guard let (image, exported) = await export(failureTitle: "Not uploaded") else { return false }
        let outcome = await actions.upload(image, asNew)
        let unchanged = model.document == exported
        if outcome.marksSaved, unchanged {
            model.markSaved()
        }
        if outcome.closesWindow(documentUnchanged: unchanged) {
            window?.close()
        } else if outcome.enqueued {
            // Edited while the upload started: the window stays open on purpose, with the newer
            // edit unsaved.
            NSSound.beep()
        }
        return outcome.enqueued
    }

    /// Flattens the document as it is now and hands the image over. It is marked saved only when
    /// `deliver` succeeds and nothing was edited meanwhile; an edit made during the save stays
    /// unsaved.
    private func exportAndDeliver(marksSaved: Bool, failureTitle: String,
                                  _ deliver: (ScaledImage) async -> Bool) async -> Bool {
        guard let (image, exported) = await export(failureTitle: failureTitle) else { return false }
        guard await deliver(image) else { return false }
        if marksSaved, model.document == exported {
            model.markSaved()
        }
        return true
    }

    /// The flattened image and the document it was made from, or nil (with a beep) when the
    /// export failed. A background that could not be drawn is also posted as `failureTitle`
    /// (`Not saved`, `Not uploaded`), so the editor stays dirty and says why.
    private func export(failureTitle: String) async -> (ScaledImage, AnnotationDocument)? {
        // A crop still being edited is what the window shows, so it is applied (one undo step) first.
        model.applyCrop()
        // A slider drag cut short by the popover closing is what the window shows, too.
        model.commitBackgroundDraft()
        let exported = model.document
        do throws(EditorExportFailure) {
            return (try await model.renderExport(displayID: displayID), exported)
        } catch {
            NSLog("Editor: the export of \(model.recordID) failed (\(error))")
            if let message = error.message {
                actions.exportFailed(message, failureTitle)
            }
            NSSound.beep()
            return nil
        }
    }

    /// The display under the editor window, whose wallpaper a desktop-picture background uses;
    /// nil (the main display) while the window is off screen.
    var displayID: CGDirectDisplayID? {
        (window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    // MARK: Background preview

    /// What the preview's fill depends on: the fill, its size (the canvas, which the style and the
    /// crop decide), the display for a desktop picture, and the stored image for a custom one.
    struct BackgroundFillKey: Equatable {
        var fill: BackgroundFill
        var size: CGSize
        var displayID: CGDirectDisplayID?
        var customRevision: Int
    }

    /// Nil while no background is shown.
    private var backgroundFillKey: BackgroundFillKey? {
        guard let shown = model.shownBackground else { return nil }
        let fill = shown.style.fill
        return BackgroundFillKey(fill: fill, size: shown.previewFillSize,
                                 displayID: fill == .desktopPicture ? displayID : nil,
                                 customRevision: fill == .customImage ? CustomBackgroundRevision.shared.count : 0)
    }

    /// Renders the fill again whenever its key changes, re-registering on each change as
    /// `observeEdited` does. The display is not observable; `windowDidChangeScreen` covers it.
    private func observeBackgroundFill() {
        let key = withObservationTracking {
            backgroundFillKey
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBackgroundFill() }
        }
        renderBackgroundFill(for: key)
    }

    /// The fill for `key`, rendered off the main actor at most 2,048 px on its long side, then
    /// handed to `BaseImageView`; the latest key wins. With no background the layer is hidden and
    /// keeps its last fill.
    private func renderBackgroundFill(for key: BackgroundFillKey?) {
        guard key != renderedFill else { return }
        renderedFill = key
        fillTask?.cancel()
        guard let key else { return }
        fillTask = Task { [weak self] in
            guard let self else { return }
            let source = await fillSourceImage(for: key)
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                BackgroundCompositor.fill(key.fill, size: key.size, fillImage: source)
            }.value
            guard !Task.isCancelled else { return }
            baseView.backgroundFill = image
        }
    }

    /// Reads the wallpaper again and re-renders the fill, while a desktop-picture background shows.
    /// The cached source is keyed by display, so a new wallpaper or Space would not change the key.
    private func refreshDesktopPicture() {
        guard let key = backgroundFillKey, key.fill == .desktopPicture else { return }
        fillSource = nil
        renderedFill = nil
        renderBackgroundFill(for: key)
    }

    /// The desktop picture or the custom image for `key` (nil for a gradient or a colour), read
    /// again only when the fill, the display or the stored image changed.
    private func fillSourceImage(for key: BackgroundFillKey) async -> CGImage? {
        switch key.fill {
        case .gradient, .solid:
            return nil
        case .desktopPicture, .customImage:
            var sourceKey = key
            sourceKey.size = .zero
            if let fillSource, fillSource.key == sourceKey { return fillSource.image }
            let image = await BackgroundFillSource.fillImage(for: key.fill, displayID: key.displayID)
            // A refresh cancelled this render and cleared the cache; its image may be the old wallpaper.
            if !Task.isCancelled { fillSource = (sourceKey, image) }
            return image
        }
    }

    // MARK: Zoom

    @objc func zoomToFit(_ sender: Any?) {
        canvasView.commitTextEditing()
        canvasView.fitToView()
    }

    @objc func zoomToActualSize(_ sender: Any?) {
        canvasView.commitTextEditing()
        canvasView.zoom(to: 1 / model.scale)
    }

    @objc func zoomIn(_ sender: Any?) {
        canvasView.commitTextEditing()
        canvasView.zoom(by: 1.25)
    }

    @objc func zoomOut(_ sender: Any?) {
        canvasView.commitTextEditing()
        canvasView.zoom(by: 1 / 1.25)
    }

    // MARK: NSUserInterfaceValidations

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, !permits(action) { return false }
        let limits = CanvasTransform.zoomLimits(captureScale: model.scale)
        switch item.action {
        case #selector(saveDocument(_:)), #selector(saveDocumentAs(_:)), #selector(copy(_:)),
             #selector(copyImage(_:)), #selector(uploadDocument(_:)), #selector(uploadDocumentAsNew(_:)):
            return !isPerformingAction
        case #selector(zoomIn(_:)):
            return model.transform.zoom < limits.upperBound * 0.999
        case #selector(zoomOut(_:)):
            return model.transform.zoom > limits.lowerBound * 1.001
        default:
            return true
        }
    }

    // MARK: Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvasView.commitTextEditing()
        guard model.hasUnsavedChanges else { return true }
        Task {
            if await askToSaveBeforeClosing() {
                window?.close()
            }
        }
        return false
    }

    /// The unsaved-changes sheet. True when the window may close: nothing to save, Don’t Save, or a
    /// Save that wrote the edit. False for Cancel, a failed save, a cancelled save panel, a sheet
    /// already showing or an action still running. Save runs ⌘S (which opens the save panel when
    /// there is nothing to write over); it becomes Save As… when this controller's own validation
    /// refuses Save.
    func askToSaveBeforeClosing() async -> Bool {
        canvasView.commitTextEditing()
        guard model.hasUnsavedChanges else { return true }
        guard let window, window.attachedSheet == nil, !isPerformingAction else {
            NSSound.beep()
            return false
        }
        let canSave = validateUserInterfaceItem(ShortcutItem(action: #selector(saveDocument(_:))))
        let saveButton = EditorSaveCommand.closeSheetButton(available: canSave ? [.save] : [])
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(window.title)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: saveButton.title)
        alert.addButton(withTitle: "Cancel")
        let dontSave = alert.addButton(withTitle: "Don’t Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        // Held from the moment the sheet shows until its choice is carried out, so a shortcut that
        // reaches this window behind the sheet is refused and no other action clears the flag early.
        isPerformingAction = true
        defer { isPerformingAction = false }
        switch await alert.beginSheetModal(for: window) {
        case .alertFirstButtonReturn:
            switch saveButton {
            case .save: return await performSave()
            case .saveAs: return await performSaveAs()
            }
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        model.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        onClose?(self)
    }

    /// A desktop-picture background follows the display under the window, and its wallpaper is read
    /// again, since the new screen may show another one.
    func windowDidChangeScreen(_ notification: Notification) {
        refreshDesktopPicture()
    }

    /// The Background popover's `Choose Image…` was given a file that does not decode.
    func reportUnusableBackgroundImage(named fileName: String) {
        actions.unusableBackgroundImage(fileName)
    }

    /// Space's key-up goes elsewhere once the window is not key, so the pan key is let go here.
    func windowDidResignKey(_ notification: Notification) {
        canvasView.endSpacePan()
    }
}

extension EditorWindowController: EditorPresenting {}
