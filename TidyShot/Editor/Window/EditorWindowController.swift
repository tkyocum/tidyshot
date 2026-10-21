import AppKit
import Observation

/// What the editor's document actions do, provided by AppCoordinator: the editor never writes
/// files, never touches the pasteboard and never enqueues uploads. For Save, Save Copy and Upload
/// the Bool says whether the edit was written, which is when the editor marks itself saved.
struct EditorActions {
    var save, saveCopy: (ScaledImage) async -> Bool
    var copy: (ScaledImage) async -> Void
    var upload: (ScaledImage, _ asNew: Bool) async -> Bool
}

/// One annotation editor window for one capture record: the window, the two stacked views, the
/// document actions, zoom, and the unsaved-changes sheet.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations {
    let model: EditorModel
    let canvasView: CanvasView
    /// Called from `windowWillClose(_:)`; AppCoordinator drops the editor from its registry.
    var onClose: ((EditorWindowController) -> Void)?

    private let actions: EditorActions
    /// The toolbar's popovers (EditorToolbar.swift), kept so only one is shown at a time.
    var colorPopover: NSPopover?
    var optionsPopover: NSPopover?
    /// One document action at a time; another one beeps until it finishes.
    private var isPerformingAction = false
    /// What the editor may do now. Empty until the coordinator's first push, which presentEditor
    /// sends before the window shows.
    private(set) var available: Set<EditorAction> = []

    #if DEBUG
    private static var loggedMainMenu = false
    #endif

    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, cascadeFrom: NSWindow?) {
        self.model = model
        self.actions = actions
        let baseView = BaseImageView(frame: .zero)
        baseView.image = model.base
        let canvasView = CanvasView(model: model, baseView: baseView)
        self.canvasView = canvasView

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Sizes the window to the capture's natural point size plus chrome, within 640x420 and 90%
    /// of the visible frame of the screen under the mouse, and cascades it 22 pt from
    /// `previous`. No frame autosave. The chrome is measured from the window, so a toolbar
    /// attached before this call is included.
    private func placeWindow(cascadeFrom previous: NSWindow?) {
        guard let window, let content = window.contentView else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let chrome = CGSize(width: window.frame.width - content.frame.width,
                            height: window.frame.height - content.frame.height)
        let contentSize = EditorWindowGeometry.initialContentSize(
            imagePixels: CGSize(width: model.base.width, height: model.base.height), scale: model.scale,
            chrome: chrome, visibleFrame: visible)
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
        if allowed != available {
            available = allowed
            reflectSaveAvailability()
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

    @objc func saveDocument(_ sender: Any?) {
        guard permits(#selector(saveDocument(_:))) else { return }
        runDocumentAction(marksSaved: true) { await self.actions.save($0) }
    }

    @objc func saveDocumentCopy(_ sender: Any?) {
        guard permits(#selector(saveDocumentCopy(_:))) else { return }
        runDocumentAction(marksSaved: true) { await self.actions.saveCopy($0) }
    }

    /// ⌘C. In 4a it copies the flattened image, like ⇧⌘C; 4b gives CanvasView an object copy that
    /// passes this up when nothing is selected.
    @objc func copy(_ sender: Any?) {
        guard permits(#selector(copy(_:))) else { return }
        copyImage(sender)
    }

    @objc func copyImage(_ sender: Any?) {
        guard permits(#selector(copyImage(_:))) else { return }
        runDocumentAction(marksSaved: false) { image in
            await self.actions.copy(image)
            return true
        }
    }

    @objc func uploadDocument(_ sender: Any?) {
        guard permits(#selector(uploadDocument(_:))) else { return }
        runDocumentAction(marksSaved: true) { await self.actions.upload($0, false) }
    }

    @objc func uploadDocumentAsNew(_ sender: Any?) {
        guard permits(#selector(uploadDocumentAsNew(_:))) else { return }
        runDocumentAction(marksSaved: true) { await self.actions.upload($0, true) }
    }

    private func runDocumentAction(marksSaved: Bool, _ deliver: @escaping (ScaledImage) async -> Bool) {
        guard !isPerformingAction else {
            NSSound.beep()
            return
        }
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            _ = await exportAndDeliver(marksSaved: marksSaved, deliver)
        }
    }

    /// Flattens the document as it is now and hands the image over. It is marked saved only when
    /// `deliver` succeeds and nothing was edited meanwhile; an edit made during the save stays
    /// unsaved.
    private func exportAndDeliver(marksSaved: Bool, _ deliver: (ScaledImage) async -> Bool) async -> Bool {
        let exported = model.document
        guard let image = await model.renderExport() else {
            NSLog("Editor: the export of \(model.recordID) failed")
            NSSound.beep()
            return false
        }
        guard await deliver(image) else { return false }
        if marksSaved, model.document == exported {
            model.markSaved()
        }
        return true
    }

    // MARK: Zoom

    @objc func zoomToFit(_ sender: Any?) { canvasView.fitToView() }
    @objc func zoomToActualSize(_ sender: Any?) { canvasView.zoom(to: 1 / model.scale) }
    @objc func zoomIn(_ sender: Any?) { canvasView.zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { canvasView.zoom(by: 1 / 1.25) }

    // MARK: NSUserInterfaceValidations

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if let action = item.action, !permits(action) { return false }
        let limits = CanvasTransform.zoomLimits(captureScale: model.scale)
        switch item.action {
        case #selector(saveDocument(_:)), #selector(saveDocumentCopy(_:)), #selector(copy(_:)),
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
        guard model.hasUnsavedChanges else { return true }
        Task {
            if await askToSaveBeforeClosing() {
                window?.close()
            }
        }
        return false
    }

    /// The unsaved-changes sheet. True when the window may close: nothing to save, Don’t Save, or a
    /// Save that wrote the edit. False for Cancel, a failed save, a sheet already showing or an
    /// action still running. Save becomes Save Copy… when this controller's own validation refuses
    /// Save.
    func askToSaveBeforeClosing() async -> Bool {
        guard model.hasUnsavedChanges else { return true }
        guard let window, window.attachedSheet == nil, !isPerformingAction else {
            NSSound.beep()
            return false
        }
        let canSave = validateUserInterfaceItem(ShortcutItem(action: #selector(saveDocument(_:))))
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(window.title)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: canSave ? "Save" : "Save Copy…")
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
            return await exportAndDeliver(marksSaved: true) { image in
                canSave ? await self.actions.save(image) : await self.actions.saveCopy(image)
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
        onClose?(self)
    }
}
