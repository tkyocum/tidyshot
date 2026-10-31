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
        let before = editor.calls.count

        let first = Task { await coordinator.reviewEditorsBeforeQuit() }
        defer { first.cancel() }
        let firstWatch = TaskWatch(first)
        try await eventually { editor.isAsking }
        #expect(Array(editor.calls.dropFirst(before)) == [.present, .askToSave])
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

    /// phase-4a:49 (:59). An uploaded upload-only capture has no local file, so Annotate downloads its object
    /// (`Opening the capture…`, `Downloading s/SHOT.png`) and opens the editor titled `Capture <time>`, with no file
    /// shown, Save as Save As… and the no-file subtitle. With the download failing as it does with Wi-Fi off, no
    /// editor is built and `Could not open the capture` gives the error's own description; the next Annotate
    /// downloads again and opens. The object is 6 by 3, so the size tells the source.
    @Test func anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 6, pixelHeight: 3, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        coordinator.history.add(record)
        let object = try CoordinatorWorld.pngData(width: 6, height: 3)
        destination.state.withLock {
            $0.downloadedData = object
            $0.dataDownloadFailures = [URLError(.notConnectedToInternet)]
        }
        coordinator.openEditor(recordID: record.id)
        try await eventually {
            world.notifier.calls.contains(.error(title: "Could not open the capture",
                                                 message: URLError(.notConnectedToInternet).localizedDescription))
        }
        try await eventually { coordinator.openingEditorIDs.isEmpty }
        #expect(world.editors.built.isEmpty)
        #expect(coordinator.editors.isEmpty)
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        #expect(editor.presentCount == 1)
        #expect(world.cards.calls.contains(.close(record.id, .editorOpened)))
        #expect(editor.title == title(of: record))
        #expect(editor.representedURL == nil)
        #expect(editor.model.base.width == 6)
        #expect(editor.model.base.height == 3)
        #expect(editor.model.scale == 1)
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [key, key])
        #expect(world.notifier.calls.filter { $0 == .notice(title: "Opening the capture…", body: "Downloading s/SHOT.png") }
            .count == 2)
        let first = try #require(editor.pushes.first)
        #expect(first.saveCommand == .saveAs)
        #expect(first.status == EditorSaveTarget.noFileReason)
        #expect(first.available == all)
    }

    /// phase-4a:52 (:65). With the overlay off, a capture in each after-capture mode shows no card and keeps no
    /// image, and Annotate on its record opens the editor: from the save-folder file for Upload and copy URL and
    /// Save and copy image, from `pending/<id>.png` for Upload only while its upload is still held, with
    /// `Uploading…` and only Copy and Save As… offered while either upload runs. Each capture is a record set up as
    /// its mode's `persist` leaves it (+Save:161-174) and handed to `finishSave`; the capture itself is `TARGET`'s.
    @Test(arguments: AfterCaptureAction.allCases)
    func withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor(mode: AfterCaptureAction) async throws {
        defer { world.removeAll() }
        world.settings.showOverlay = false
        let folder = try world.storeSaveFolder()
        if mode.uploads { destination.state.withLock { $0.holdingUploadsRemaining = 1 } }
        defer { destination.releaseUploads() }
        let coordinator = world.makeCoordinator()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let id = UUID()
        let file: URL
        if mode == .uploadOnly {
            file = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        } else {
            file = folder.appending(path: "Shot.png")
            try png.write(to: file)
        }
        let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: mode == .uploadOnly, pixelWidth: 4,
                                   pixelHeight: 2, appName: nil,
                                   uploadState: mode.uploads ? .uploading(fraction: 0) : .none, byteCount: png.count)
        await coordinator.finishSave(record, image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1,
                                     captureDisplayID: 1, notConfiguredWarning: nil, showsCard: true,
                                     upload: mode.uploads ? coordinator.makeDestination() : nil,
                                     payload: { .data(png) }, notification: .none)
        if mode.uploads { try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 } }
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(!world.cards.calls.contains(.show(id)))
        #expect(coordinator.latestCapture == nil)
        #expect(editor.model.base.width == 4)
        #expect(editor.model.base.height == 2)
        #expect(editor.title == (mode == .uploadOnly ? title(of: record) : "Shot.png"))
        #expect(editor.representedURL == (mode == .uploadOnly ? nil : file))
        #expect(world.cards.calls.contains(.close(id, .editorOpened)))
        let first = try #require(editor.pushes.first)
        if mode.uploads {
            #expect(first.status == "Uploading…")
            #expect(first.available == [.copy, .saveAs])
        } else {
            #expect(first.status == nil)
            #expect(first.available == all.subtracting([.uploadAsNew]))
        }
        // Nothing outlives the test: the held PUT finished, the capture's thumbnail named.
        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: id)?.isUploading == false }
        try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != nil }
    }

    /// phase-4c:201 (:273), in part. Ellipse and Large as stored land in the world's defaults under
    /// `editorSpotlightEllipse` and `editorCounterDiameterPoints`, a second `AppSettings` over those defaults reads
    /// them back (the relaunch's read), and an editor opened on the retained capture starts with them: Spotlight
    /// draws an ellipse and the Shape row's value is Ellipse, a new counter is 44 pt (88 px at 2x) and the Size
    /// row's value is 44.
    /// Stays: choosing Ellipse and Large in the popover (`EDDEFAULTS`); the rows as drawn, `defaults read` and the
    /// relaunch, by hand.
    @Test func anEditorOpensWithTheStoredSpotlightShapeAndCounterSize() async throws {
        defer { world.removeAll() }
        world.settings.editorSpotlightEllipse = true
        world.settings.editorCounterDiameterPoints = 44
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil)
        coordinator.history.add(record)
        coordinator.latestCapture = (id: record.id, image: ScaledImage(image: try CoordinatorWorld.image(width: 200, height: 100),
                                                                       scale: 2))
        coordinator.openEditor(recordID: record.id)
        let editor = try #require(world.editors.editor(for: record.id))
        #expect(world.defaults.bool(forKey: "editorSpotlightEllipse") == true)
        #expect(world.defaults.double(forKey: "editorCounterDiameterPoints") == 44)
        let second = AppSettings(defaults: world.defaults)
        #expect(second.editorDefaults.spotlightEllipse == true)
        #expect(second.editorDefaults.counterDiameterPoints == 44)
        #expect(coordinator.openingEditorIDs.isEmpty)
        let model = editor.model
        #expect(model.spotlightEllipse == true)
        #expect(model.counterDiameterPoints == 44)
        model.tool = .spotlight
        #expect(model.spotlightShapeApplies)
        #expect(model.activeSpotlightEllipse == true)
        #expect(model.makeAnnotation(.spotlight, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))?
            .spotlightShape?.isEllipse == true)
        model.tool = .counter
        #expect(model.counterSizeApplies)
        #expect(model.activeCounterDiameterPoints == 44)
        #expect(model.makeAnnotation(.counter, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: 50))?
            .counterMark?.diameter == 88)
    }

    /// phase-4c:214 (:296). A record in the shape the build before 4c wrote (no `byteCount`, `unmutedIntervals` or
    /// `multipart`, and no 4c defaults keys) loads, opens at its size and scale with the registered Spotlight and
    /// Counter defaults, takes a rectangle (a 4a tool) and a spotlight (a 4c tool), and saves over its file as
    /// before: the same size at 144 dpi with the export's pixels, the stroke over the dimmed base, no other file in
    /// the folder, and the record's byte count brought up to date.
    @Test func aCaptureFromBefore4cOpensEditsAndSavesAsBefore() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2)
        let file = folder.appending(path: "Old.png")
        try png.write(to: file)
        let id = UUID()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date(timeIntervalSinceNow: -3600))
        let json = """
        [{"appName": "Safari", "fileIsTemporary": false, "fileURL": "\(file.absoluteString)", "id": "\(id.uuidString)", \
        "mediaKind": "image", "pixelHeight": 100, "pixelWidth": 200, "supersededObjects": [], "timestamp": "\(stamp)", \
        "uploadIsStale": false, "uploadState": {"none": {}}}]
        """
        try Data(json.utf8).write(to: world.historyFileURL)
        coordinator.history.load()
        let record = try #require(coordinator.history.record(id: id))
        #expect(record.byteCount == nil)
        #expect(record.mediaKind == .image)
        #expect(record.unmutedIntervals == [])
        #expect(record.multipart == nil)
        #expect(world.defaults.persistentDomain(forName: world.suiteName)?["editorSpotlightEllipse"] == nil)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        let model = editor.model
        #expect(model.base.width == 200)
        #expect(model.base.height == 100)
        #expect(model.scale == 2)
        #expect(model.spotlightEllipse == false)
        #expect(model.counterDiameterPoints == 32)
        model.commitNewShape(try #require(model.makeAnnotation(.rectangle, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 70))))
        model.commitNewShape(try #require(model.makeAnnotation(.spotlight, from: CGPoint(x: 110, y: 20), to: CGPoint(x: 180, y: 80))))
        #expect(await editor.save())
        let expected = try #require(await editor.export()).image.image
        let written = try Data(contentsOf: file)
        let decoded = try EditorPixels.decoded(written)
        #expect(decoded.image.width == 200)
        #expect(decoded.image.height == 100)
        #expect(decoded.scale == 2)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        #expect(abs(try #require(EditorPixels.dpiWidth(of: written)) - 144) < 0.5)
        // The stroke rgb(255, 59, 48) over the base the spotlight dims: told from the dimmed base by r, and from
        // the undimmed world red [255, 38, 0] by b.
        let stroke = EditorPixels.pixel(decoded.image, x: 20, y: 40)
        #expect(stroke[0] > 200 && stroke[1] < 100 && stroke[2] > 20 && stroke[2] < 100)
        let dimmed = EditorPixels.pixel(decoded.image, x: 100, y: 90)
        #expect((120...135).contains(dimmed[0]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Old.png"])
        #expect(coordinator.history.record(id: id)?.byteCount == written.count)
        try await settledEdit(coordinator, id)
    }

    nonisolated enum Composed: CaseIterable, Sendable { case retained, savedFile }

    /// phase-7c:187 (:230), in part. A window capture composed with a solid background opens flat, from the
    /// retained image (that same image) or from its file: the background is in the base's pixels, the document is
    /// empty with no background, which is what the popover's switch reads as off, and nothing is unsaved.
    /// Stays: producing the window capture (`TARGET`); the popover's switch as its binding shows it (`BGPOP`) and
    /// drawn in the window (`EDPLACE`).
    @Test(arguments: Composed.allCases)
    func aComposedWindowCaptureOpensFlatWithNoBackground(composed kind: Composed) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let composed = try #require(BackgroundCompositor.compose(CoordinatorWorld.image(width: 4, height: 2), style: background,
                                                                 scale: 1, fillImage: nil))
        let file = folder.appending(path: "Window.png")
        try ImageEncoder.pngData(from: composed, scale: 1).write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 20, pixelHeight: 18, appName: nil)
        coordinator.history.add(record)
        if kind == .retained { coordinator.latestCapture = (id: record.id, image: ScaledImage(image: composed, scale: 1)) }
        coordinator.openEditor(recordID: record.id)
        let editor: FakeEditor
        if kind == .retained {
            #expect(coordinator.openingEditorIDs.isEmpty)
            editor = try #require(world.editors.editor(for: record.id))
            #expect(editor.model.base === composed)
        } else {
            editor = try await openedEditor(record.id)
        }
        let m = editor.model
        #expect(m.base.width == 20 && m.base.height == 18)
        #expect(EditorPixels.pixel(m.base, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.pixel(m.base, x: 8, y: 8) == (try EditorPixels.worldRed()))
        #expect(m.document == AnnotationDocument())
        #expect(m.document.background == nil)
        #expect(!m.hasUnsavedChanges)
    }

    /// phase-6a:131 (:133), in part; phase-6a:152 (:155); phase-6a:158 (:161), with
    /// `CoordinatorOverlayTests.aCardWhoseDeleteIsUnderWayIsNotRestorable`; coordinator-split:44 (:44), in part.
    /// Deleting the middle card's capture and Annotating another from its card (`openEditorAfterMenuTracking`, which
    /// the pin menu's Annotate also calls) closes each, `.deleted` and `.editorOpened`, and neither is restorable,
    /// so `Restore Closed Overlay` is disabled. A card the user closed is restorable until the editor opens on its
    /// capture from Recent Captures (`openEditor`); then it is not.
    /// Stays: phase-6a:131, the gap in the stack closing (`QASTACK`). coordinator-split:44, the pin, the second
    /// click and `Close Pinned Screenshots` (`PINS`, `SCREENS`), and the pin's Save As… panel (`SAVEAS`); its Copy
    /// Image is already `CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject`.
    @Test func annotateFromACardOrRecentCapturesLeavesNothingToRestore() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let a = try addPendingImage(to: coordinator)
        let b = try addPendingImage(to: coordinator)
        let c = try addPendingImage(to: coordinator)
        world.cards.showing = [a.id, b.id, c.id]
        await coordinator.deleteCapture(recordID: b.id)
        coordinator.openEditorAfterMenuTracking(recordID: c.id)
        _ = try await openedEditor(c.id)
        #expect(world.cards.closes == [.deleted, .editorOpened])
        #expect(world.cards.calls.contains(.close(b.id, .deleted)))
        #expect(world.cards.calls.contains(.close(c.id, .editorOpened)))
        #expect(world.cards.showing == [a.id])
        #expect(coordinator.closedOverlays.ids.isEmpty)
        #expect(!coordinator.canRestoreClosedOverlay)
        #expect(world.editors.editor(for: c.id)?.presentCount == 1)
        let d = try addPendingImage(to: coordinator)
        world.cards.showing.insert(d.id)
        world.cards.close(recordID: d.id, reason: .user)
        #expect(coordinator.closedOverlays.ids == [d.id])
        #expect(coordinator.canRestoreClosedOverlay)
        coordinator.openEditor(recordID: d.id)
        _ = try await openedEditor(d.id)
        #expect(coordinator.closedOverlays.ids.isEmpty)
        #expect(!coordinator.canRestoreClosedOverlay)
    }

    nonisolated enum Restored: CaseIterable, Sendable { case savedFile, pendingFile, uploadedUploadOnly, uploadedUploadOnlyStaged }

    /// phase-6a:164 (:172), in part. A showing card with no retained image stands for a restored one. Its Annotate
    /// (`openEditorAfterMenuTracking`) opens the editor from the save-folder file, from `pending/<id>.png`, or for
    /// an uploaded upload-only capture from the bucket (`Downloading s/SHOT.png`); once the restore's quiet download
    /// into the drag folder has landed (`prepareDragFile`, +Overlay:101), from that copy, with no second GET and no
    /// `Downloading` notice. The card closes as `.editorOpened` and is not on the restore list.
    /// Stays: the restore itself, which reads the screens (`SCREENS`). The quiet download's naming is
    /// `CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey`.
    @Test(arguments: Restored.allCases)
    func aRestoredCardsAnnotateOpensFromTheFileOrTheBucket(restored kind: Restored) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record: CaptureRecord
        switch kind {
        case .savedFile: record = try addSavedImage(to: coordinator, in: folder).record
        case .pendingFile: record = try addPendingImage(to: coordinator)
        case .uploadedUploadOnly, .uploadedUploadOnlyStaged:
            let object = try CoordinatorWorld.pngData(width: 6, height: 3)
            destination.state.withLock { $0.downloadedData = object }
            record = CaptureRecord(fileURL: nil, pixelWidth: 6, pixelHeight: 3, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
            coordinator.history.add(record)
        }
        let id = record.id
        world.cards.showing.insert(id)
        if kind == .uploadedUploadOnlyStaged {
            // The restore's last step (+Overlay:101): the quiet download into the drag folder, landed.
            coordinator.prepareDragFile(recordID: id)
            try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
        }
        coordinator.openEditorAfterMenuTracking(recordID: id)
        let editor = try await openedEditor(id)
        try await eventually { coordinator.openingEditorIDs.isEmpty }
        switch kind {
        case .savedFile:
            #expect(editor.title == "Shot.png")
            #expect(editor.representedURL == record.fileURL)
            #expect(editor.model.base.width == 4)
            #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        case .pendingFile:
            #expect(editor.title == title(of: record))
            #expect(editor.representedURL == nil)
            #expect(editor.model.base.width == 4)
            #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        case .uploadedUploadOnly:
            #expect(editor.title == title(of: record))
            #expect(editor.representedURL == nil)
            #expect(editor.model.base.width == 6)
            #expect(destination.state.withLock { $0.dataDownloadKeys } == ["s/SHOT.png"])
            #expect(world.notifier.calls.contains(.notice(title: "Opening the capture…", body: "Downloading s/SHOT.png")))
        case .uploadedUploadOnlyStaged:
            #expect(editor.title == title(of: record))
            #expect(editor.representedURL == nil)
            #expect(editor.model.base.width == 6)
            #expect(destination.state.withLock { $0.dataDownloadKeys } == ["s/SHOT.png"])
            #expect(!world.notifier.calls.contains { if case .notice(_, let body, _) = $0 { return body.hasPrefix("Downloading ") } else { return false } })
        }
        #expect(EditorPixels.pixel(editor.model.base, x: 0, y: 0) == (try EditorPixels.worldRed()))
        #expect(editor.model.scale == 1)
        #expect(editor.presentCount == 1)
        #expect(editor.pushes.first?.record == coordinator.history.record(id: id))
        #expect(world.cards.calls.contains(.close(id, .editorOpened)))
        #expect(!coordinator.closedOverlays.ids.contains(id))
        #expect(world.notifier.errors.isEmpty)
    }

    /// phase-6a:198 (:210), in part. After an upload-only capture's upload, with its card showing, Copy Image, the
    /// read Save As… makes after its panel (`imageData(of:downloadTitle:)`) and Annotate all read the drag copy: the
    /// pending bytes, no GET and no `Downloading` notice. Annotate closes the card, and 60 seconds later on the
    /// world's clock the record's drag folder is gone.
    /// Stays: the card's Save As… panel (`SAVEAS`); Slack reading the file in that minute, by hand. The drag folder
    /// taking the pending file's place and no `fileURL` are already
    /// `CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard`.
    @Test func anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let id = record.id
        let png = try Data(contentsOf: try #require(record.fileURL))
        world.cards.showing.insert(id)
        coordinator.retryUpload(recordID: id)
        try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
        let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
        let current = try #require(coordinator.history.record(id: id))
        #expect(current.fileURL == nil)
        #expect(try Data(contentsOf: try #require(coordinator.dragFiles.stagedFile(id: id))) == png)
        #expect(world.clipboard.copies == [.url(publicURL(k))])
        await coordinator.copyImage(recordID: id)
        #expect(world.clipboard.copies == [.url(publicURL(k)), .pngAndTIFF])
        #expect(world.clipboard.pngs == [png])
        #expect(world.notifier.calls.contains(.notice(title: "Image copied", body: k)))
        #expect(try await coordinator.imageData(of: current, downloadTitle: "Saving a copy…") == png)
        coordinator.openEditorAfterMenuTracking(recordID: id)
        let editor = try await openedEditor(id)
        #expect(EditorPixels.pixel(editor.model.base, x: 0, y: 0) == (try EditorPixels.worldRed()))
        #expect(editor.model.base.width == 4)
        #expect(world.cards.calls.contains(.close(id, .editorOpened)))
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        #expect(!world.notifier.calls.contains { if case .notice(_, let body, _) = $0 { return body.hasPrefix("Downloading ") } else { return false } })
        try await world.clock.run(for: .seconds(60))
        try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
    }
}
