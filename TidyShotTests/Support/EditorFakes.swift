import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// An open editor in the suite: the coordinator's model and actions, every call made on it, the close
/// sheet's answers; no window. The helpers commit a text being typed first, as every document action
/// and the sheet do (EditorWindowController.swift:188, :195, :208, :221, :228, :461), and apply results
/// as the controller does (`exportAndDeliver` :288-296, `performUpload` :268-283); `close()` stands
/// for `windowWillClose`.
final class FakeEditor: EditorPresenting {
    /// One push, and what the controller derives from it (recordDidChange, :165-176).
    struct Push: Equatable {
        var record: CaptureRecord?
        var saveFolder: URL?
        var isDeleting: Bool
        var available: Set<EditorAction> {
            EditorAvailability.actions(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
        }
        var status: String? {
            EditorAvailability.status(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
        }
        var saveCommand: EditorSaveCommand { EditorSaveCommand.forSave(record: record, saveFolder: saveFolder) }
    }
    enum Call: Equatable { case present, askToSave, recordDidChange(Push) }
    /// A close sheet's answer. `Sendable` because `SingleWaiter` carries it.
    nonisolated enum CloseAnswer: Equatable, Sendable {
        case save, dontSave, cancel
        case saveAs(URL)
    }
    let model: EditorModel
    let actions: EditorActions
    let title: String
    let representedURL: URL?
    private let onClose: @MainActor (any EditorPresenting) -> Void
    private(set) var calls: [Call] = []
    private(set) var isClosed = false
    /// The close sheet's answers, in order; Cancel when they run out.
    var closeAnswers: [CloseAnswer] = []
    /// While set, the sheet stays up until `answer(_:)`. Its task cancelled (the test's `defer`) or a
    /// second sheet while one is up: Cancel.
    var holdsCloseSheet = false
    private let sheet = SingleWaiter(cancelled: CloseAnswer.cancel,
                                     secondEntry: "FakeEditor's close sheet was asked for again while it was up")
    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?,
         onClose: @escaping @MainActor (any EditorPresenting) -> Void) {
        self.model = model
        self.actions = actions
        self.title = title
        self.representedURL = representedURL
        self.onClose = onClose
    }
    var presentCount: Int { calls.filter { $0 == .present }.count }
    var pushes: [Push] {
        calls.compactMap { call -> Push? in
            guard case .recordDidChange(let push) = call else { return nil }
            return push
        }
    }
    var isAsking: Bool { sheet.isWaiting }

    // MARK: EditorPresenting
    func present() { calls.append(.present) }
    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) {
        calls.append(.recordDidChange(Push(record: record, saveFolder: saveFolder, isDeleting: isDeleting)))
    }
    /// As the live sheet (:460-492): true with nothing to save, else the answer carried out.
    func askToSaveBeforeClosing() async -> Bool {
        calls.append(.askToSave)
        model.commitTextEditing()
        guard model.hasUnsavedChanges else { return true }
        let answer: CloseAnswer
        if holdsCloseSheet {
            answer = await sheet.wait()
        } else {
            answer = closeAnswers.isEmpty ? .cancel : closeAnswers.removeFirst()
        }
        switch answer {
        case .save:
            // The live first button writes over only when the last push allows Save and ⌘S writes over
            // (:467-468, performSave :247-254); otherwise it is Save As…, or Save opening the panel.
            guard let push = pushes.last, push.available.contains(.save), push.saveCommand == .writeOver else {
                Issue.record("FakeEditor's sheet was answered Save where the live first button opens the save panel")
                return false
            }
            return await save()
        case .saveAs(let url): return await saveAs(to: url)
        case .dontSave: return true
        case .cancel: return false
        }
    }
    func answer(_ answer: CloseAnswer) {
        holdsCloseSheet = false
        sheet.resume(answer)
    }

    // MARK: The user
    /// The window closed: the coordinator's `onClose`, as `windowWillClose(_:)` calls it.
    func close() {
        isClosed = true
        onClose(self)
    }
    /// A blue box over the whole capture, committed as a tool does on mouseUp.
    func draw() {
        let size = CGSize(width: model.base.width, height: model.base.height)
        let box = ShapeBox(id: UUID(), rect: CGRect(origin: .zero, size: size), color: RGBA(red: 0, green: 0, blue: 1),
                           lineWidth: max(size.width, size.height))
        model.commit(model.document.appending(.rectangle(box)), actionName: "Add")
    }
    /// The export and its document: a text being typed committed, then a pending crop and background
    /// draft applied (:301-317).
    func export() async -> (image: ScaledImage, document: AnnotationDocument)? {
        model.commitTextEditing()
        model.applyCrop()
        model.commitBackgroundDraft()
        let document = model.document
        guard let image = try? await model.renderExport() else { return nil }
        return (image, document)
    }
    /// ⌘S writing over; skips the window's validation, so a test reaches the coordinator's own check.
    @discardableResult
    func save() async -> Bool {
        guard let (image, exported) = await export() else { return false }
        guard await actions.save(image) else { return false }
        if model.document == exported { model.markSaved() }
        return true
    }
    @discardableResult
    func saveAs(to url: URL) async -> Bool {
        guard let (image, exported) = await export() else { return false }
        guard await actions.saveAs(image, url) else { return false }
        if model.document == exported { model.markSaved() }
        return true
    }
    /// Copy (⌘C, ⇧⌘C): never marks saved.
    func copy() async {
        guard let (image, _) = await export() else { return }
        await actions.copy(image)
    }
    /// ⌘U, or ⌥⌘U with `asNew`: saved and closed as the outcome says, given whether anything changed.
    @discardableResult
    func upload(asNew: Bool = false) async -> EditorUploadOutcome {
        guard let (image, exported) = await export() else { return .refused }
        let outcome = await actions.upload(image, asNew)
        let unchanged = model.document == exported
        if outcome.marksSaved, unchanged { model.markSaved() }
        if outcome.closesWindow(documentUnchanged: unchanged) { close() }
        return outcome
    }
}

/// `environment.makeEditor` in the suite: every editor built, in order, kept after it closes.
final class FakeEditors {
    private(set) var built: [FakeEditor] = []
    func make(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?,
              onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting {
        let editor = FakeEditor(model: model, actions: actions, title: title, representedURL: representedURL,
                                onClose: onClose)
        built.append(editor)
        return editor
    }
    /// The newest editor built for `id`.
    func editor(for id: UUID) -> FakeEditor? {
        built.last { $0.model.recordID == id }
    }
}

/// A renderer that never produces a tile, standing in for a Core Image failure.
nonisolated struct NoTileRenderer: TileRendering {
    func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage? { nil }
}
