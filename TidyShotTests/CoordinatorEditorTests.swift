import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The editor bridge on a built coordinator (`AppCoordinator+Editor`): `loadImage(for:)`, an Annotate whose
/// load fails, and an open editor: its opening, the card, what it hears while things happen, and the quit
/// review. Presenting goes through `environment.makeEditor`, which here builds a `FakeEditor`
/// (`world.editors`) and no window, so nothing in this suite reads the screens.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorEditorTests {
    let world: CoordinatorWorld
    let key = "s/SHOT.png"

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }
    var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
    var all: Set<EditorAction> { Set(EditorAction.allCases) }
    var green: RGBA { RGBA(red: 0, green: 1, blue: 0) }
    var background: BackgroundStyle {
        BackgroundStyle(fill: .solid(green), padding: 8, cornerRadius: 0, shadow: false, aspect: .auto)
    }

    func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

    func openedEditor(_ id: UUID) async throws -> FakeEditor {
        try await eventually { world.editors.editor(for: id) != nil }
        return try #require(world.editors.editor(for: id))
    }

    func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor {
        try await eventually { world.editors.editor(for: id).map { $0 !== first } ?? false }
        return try #require(world.editors.editor(for: id))
    }

    /// The last edit's thumbnail named on the record (`replaceThumbnail(for:from:editedAt:)` in
    /// `AppCoordinator+Editor`), so its task does not outlive the test.
    func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws {
        try await eventually {
            coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
        }
    }

    func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png",
                       uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil,
                       uploadIsStale: Bool = false, timestamp: Date = Date(),
                       scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data) {
        let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: scale)
        let file = folder.appending(path: name)
        try original.write(to: file)
        let record = CaptureRecord(timestamp: timestamp, fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: uploadState, objectLocation: objectLocation,
                                   uploadIsStale: uploadIsStale, byteCount: original.count)
        coordinator.history.add(record)
        return (record, original)
    }

    func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord {
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                   byteCount: png.count)
        coordinator.history.add(record)
        return record
    }

    func desktop(_ name: String) throws -> URL {
        let folder = world.root.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL {
        coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).png")
    }

    func addUploadOnly(to coordinator: AppCoordinator) throws -> CaptureRecord {
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        destination.state.withLock { $0.downloadedData = png }
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        coordinator.history.add(record)
        return record
    }

    func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
        if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
        return false
    }

    func title(of record: CaptureRecord) -> String {
        "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    func crop(_ model: EditorModel, to rect: CGRect, apply: Bool) {
        model.tool = .crop
        model.cropDraft = rect
        if apply { model.applyCrop() }
    }

    func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox {
        model.beginTextEditing(at: point, existing: nil)
        model.updateEditingText(string)
        model.commitTextEditing()
        for annotation in model.document.annotations {
            if case .text(let box) = annotation { return box }
        }
        throw CoordinatorWorldError.noFile
    }

    nonisolated enum Kept: CaseIterable, Sendable {
        /// Saved, never uploaded: the file in the save folder.
        case savedFile
        /// Uploaded, its file kept in the save folder.
        case uploadedWithItsFile
        /// Upload only, the upload failed: `pending/<id>.png`.
        case pendingFile
        /// Uploaded, its file renamed in Finder: the object.
        case renamedUploadedFile
    }

    /// phase-4a :46, phase-4a :47, phase-4a :48, phase-4a :51. The editor's pixels come from the save-folder file
    /// of a saved capture and of an uploaded one, from `pending/<id>.png` of a failed upload-only capture, and
    /// from the downloaded object when an uploaded capture's file was renamed. The object is a 6 by 3 PNG, so
    /// the size tells the source.
    @Test(arguments: Kept.allCases)
    func loadImageReadsTheLocalFileOrDownloadsTheObject(record kept: Kept) async throws {
        defer { world.removeAll() }
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let object = try CoordinatorWorld.pngData(width: 6, height: 3)
        destination.state.withLock { $0.downloadedData = object }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let saved = folder.appending(path: "Shot.png")
        let record: CaptureRecord
        switch kept {
        case .savedFile:
            try png.write(to: saved)
            record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil)
        case .uploadedWithItsFile:
            try png.write(to: saved)
            record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        case .pendingFile:
            let pending = try coordinator.pendingFiles.write(png, id: id, ext: "png")
            record = CaptureRecord(id: id, fileURL: pending, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."))
        case .renamedUploadedFile:
            record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        }
        coordinator.history.add(record)

        let image = try #require(await coordinator.loadImage(for: record))

        let downloads = kept == .renamedUploadedFile
        #expect(image.image.width == (downloads ? 6 : 4))
        #expect(image.image.height == (downloads ? 3 : 2))
        #expect(destination.state.withLock { $0.dataDownloadKeys } == (downloads ? [key] : []))
        #expect(world.notifier.errors.isEmpty)
    }

    /// phase-4a :50. Annotate on a capture from before Phase 3 whose file was moved out of the save folder opens no
    /// window and posts `Could not open the capture` with `The local file could not be read.`
    @Test func annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: folder.appending(path: "Moved.png"), pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .uploaded(url: link, key: key))
        coordinator.history.add(record)

        coordinator.openEditor(recordID: record.id)
        try await eventually {
            world.notifier.calls.contains(.error(title: "Could not open the capture",
                                                 message: "The local file could not be read."))
        }
        try await eventually { coordinator.openingEditorIDs.isEmpty }

        #expect(coordinator.editors.isEmpty)
        #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
    }

    /// phase-4a:39 (:43), in part. A second Annotate while the capture's image loads opens nothing more
    /// (`openingEditorIDs`): the upload-only capture is downloaded once. Once the editor is open, Annotate on the
    /// same capture calls `present()` on the registered editor again, builds no second one, pushes no second
    /// state and closes the card only once.
    /// Stays: the window coming forward, by hand. It is `present()`'s own body in `EditorWindowController`,
    /// which the fake records and does not run; ordering a window front is barred in the suite, so no seam
    /// reaches it.
    @Test func annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = try addUploadOnly(to: coordinator)
        let id = record.id
        coordinator.openEditor(recordID: id)
        coordinator.openEditor(recordID: id)
        #expect(coordinator.openingEditorIDs == [id])
        #expect(world.editors.built.isEmpty)
        let editor = try await openedEditor(id)
        try await eventually { coordinator.openingEditorIDs.isEmpty }
        #expect(world.editors.built.count == 1)
        #expect(editor.presentCount == 1)
        #expect(coordinator.editors[id] === editor)
        coordinator.openEditor(recordID: id)
        #expect(world.editors.built.count == 1)
        #expect(editor.presentCount == 2)
        #expect(editor.calls.last == .present)
        #expect(editor.pushes.count == 1)
        #expect(world.cards.calls.filter { $0 == .close(id, .editorOpened) }.count == 1)
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
    }

    /// phase-4a:155 (:223), in part. The quit holds only while an editor has unsaved changes, and the quit
    /// review asks only the changed editor: it comes forward and shows its sheet. Cancel stops the quit and
    /// leaves the editor registered and changed; a second review answered Don't Save lets the quit go,
    /// leaves the pending file as it was and closes nothing. The clean editor is never asked.
    /// Stays: the sheet itself (`CLOSESHEET`); the real quit's reply (`APPDELEGATE`).
    @Test func quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let changed = try addPendingImage(to: coordinator)
        let clean = try addPendingImage(to: coordinator)
        let pending = try #require(changed.fileURL)
        let original = try Data(contentsOf: pending)
        coordinator.openEditor(recordID: changed.id)
        coordinator.openEditor(recordID: clean.id)
        let editor = try await openedEditor(changed.id)
        let other = try await openedEditor(clean.id)
        #expect(!coordinator.quitNeedsHold)
        editor.draw()
        #expect(coordinator.quitNeedsHold)
        editor.holdsCloseSheet = true

        let first = Task { await coordinator.reviewEditorsBeforeQuit() }
        defer { first.cancel() }
        let firstWatch = TaskWatch(first)
        try await eventually { editor.isAsking }
        #expect(Array(editor.calls.suffix(2)) == [.present, .askToSave])
        editor.answer(.cancel)
        try await eventually { firstWatch.hasReturned }
        let proceeded = await first.value

        #expect(!proceeded)
        #expect(coordinator.editors[changed.id] === editor)
        #expect(editor.model.hasUnsavedChanges)
        #expect(!other.calls.contains(.askToSave))

        editor.closeAnswers = [.dontSave]
        let second = Task { await coordinator.reviewEditorsBeforeQuit() }
        defer { second.cancel() }
        let secondWatch = TaskWatch(second)
        try await eventually { secondWatch.hasReturned }
        let quits = await second.value

        #expect(quits)
        #expect(editor.calls.filter { $0 == .askToSave }.count == 2)
        #expect(try Data(contentsOf: pending) == original)
        #expect(editor.model.hasUnsavedChanges)
        #expect(!editor.isClosed)
        #expect(coordinator.editors[changed.id] === editor)
        #expect(coordinator.editors[clean.id] === other)
        #expect(!other.calls.contains(.askToSave))
    }
}
