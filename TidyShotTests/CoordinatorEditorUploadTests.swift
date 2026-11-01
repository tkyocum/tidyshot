import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The editor's Upload through the editor seam: the local write first, then the live lane over the link's own key or
/// a new one; the window's close is the fake's (`closesWindow`), the controller's `performUpload` does not run.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorEditorUploadTests {
    let world: CoordinatorWorld
    let key = "s/SHOT.png"

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }
    var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
    var all: Set<EditorAction> { Set(EditorAction.allCases) }

    func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

    func openedEditor(_ id: UUID) async throws -> FakeEditor {
        try await eventually { world.editors.editor(for: id) != nil }
        return try #require(world.editors.editor(for: id))
    }

    func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor {
        try await eventually { world.editors.editor(for: id).map { $0 !== first } ?? false }
        return try #require(world.editors.editor(for: id))
    }

    /// The last edit's thumbnail named on the record (+Editor:249-275), so its task does not outlive the test.
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

    /// phase-4a:123 (:176), in part; phase-4b:74 (:102); phase-4b:106 (:150), in part. Upload on a save-folder
    /// capture with a link (a highlight and a pending crop on a white 200 by 100 base at 2x) writes the cropped edit
    /// over the file first, then PUTs those same bytes over the link's own key with `Cache-Control: no-cache`; while
    /// the PUT is held the editor hears `Uploading…` and the row shows the upload, the editor closes once the upload
    /// is enqueued, and the link replaces the clipboard with the cache notice. `curl` and `sips` are the PUT body's
    /// decode. Stays: phase-4a:123, closing with no unsaved-changes sheet (`EDPLACE`: the fake applies
    /// `closesWindow`, the controller's close does not run); the link showing the redaction is the PUT body under
    /// the link's key. phase-4b:106, closing at once (`EDPLACE`).
    @Test func uploadWritesTheFileFirstThenReplacesTheLinksObject() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        defer { destination.releaseUploads() }
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        let id = record.id
        coordinator.history.add(record)

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        let first = try #require(editor.pushes.first)
        #expect(first.status == nil)
        #expect(first.available == all)
        #expect(first.saveCommand == .writeOver)
        editor.model.commitNewShape(try #require(editor.model.makeStroke(.highlighter, points: [CGPoint(x: 50, y: 50),
                                                                                              CGPoint(x: 150, y: 50)])))
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)

        let outcome = await editor.upload()

        #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        #expect(coordinator.editors[id] == nil)
        #expect(!editor.model.hasUnsavedChanges)
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        let expected = try #require(await editor.export()).image.image
        let written = try Data(contentsOf: file)
        let decodedFile = try EditorPixels.decoded(written)
        #expect(decodedFile.image.width == 120)
        #expect(decodedFile.image.height == 60)
        #expect(decodedFile.scale == 2)
        #expect(EditorPixels.rgba(decodedFile.image) == EditorPixels.rgba(expected))
        let held = try #require(coordinator.history.record(id: id))
        #expect(held.pixelWidth == 120)
        #expect(held.pixelHeight == 60)
        #expect(held.priorUpload == PriorUpload(url: link, key: key, location: world.location, isReplace: true))
        #expect(held.isUploading)
        #expect(editor.pushes.last?.status == EditorAvailability.uploadingStatus)
        #expect(editor.pushes.last?.available == [.copy, .saveAs])
        #expect(world.cards.updates(for: id).contains(.uploading(fraction: 0)))
        #expect(world.clipboard.copies.isEmpty)

        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: id)?.isUploading == false }

        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map(\.key) == [key])
        #expect(uploads.first?.cacheControl == "no-cache")
        #expect(uploads.first?.data == (try Data(contentsOf: file)))
        let decoded = try EditorPixels.decoded(try #require(uploads.first?.data))
        try #require(decoded.image.width == 120 && decoded.image.height == 60)
        #expect(decoded.scale == 2)
        #expect(EditorPixels.pixel(decoded.image, x: 60, y: 30)[2] < 180)
        #expect(EditorPixels.pixel(decoded.image, x: 60, y: 2) == [255, 255, 255, 255])
        let after = try #require(coordinator.history.record(id: id))
        #expect(after.uploadState == .uploaded(url: link, key: key))
        #expect(after.uploadIsStale == false)
        #expect(after.priorUpload == nil)
        #expect(after.pixelWidth == 120)
        #expect(after.pixelHeight == 60)
        #expect(world.clipboard.copies == [.url(link)])
        #expect(world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
        #expect(destination.state.withLock { $0.deletedKeys }.isEmpty)
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:124 (:177), in part; phase-4b:75 (:103); phase-4b:108 (:152). An uploaded upload-only capture opens
    /// from its downloaded object (`Opening the capture…`, titled as a capture with no file, first heard with no
    /// file to save over); Upload with a text box and a pending crop writes the edit to a new `pending/<id>.png`
    /// first, then PUTs those bytes over the link's own key with `Cache-Control: no-cache`, the text in the object.
    /// Once it lands the record is upload-only again with its pending file gone, and the link replaces the clipboard.
    /// The link serving and showing the redaction is the PUT body under the same key. Stays: phase-4a:124, the
    /// window closing (`EDPLACE`).
    @Test func uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey() async throws {
        defer { world.removeAll() }
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
        destination.state.withLock { $0.downloadedData = png; $0.holdingUploadsRemaining = 1 }
        defer { destination.releaseUploads() }
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        let id = record.id
        coordinator.history.add(record)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
        #expect(world.notifier.calls.contains(.notice(title: "Opening the capture…", body: "Downloading \(key)")))
        #expect(editor.title == title(of: record))
        #expect(editor.representedURL == nil)
        #expect(editor.model.base.width == 200 && editor.model.scale == 2)
        let first = try #require(editor.pushes.first)
        #expect(first.status == EditorSaveTarget.noFileReason)
        #expect(first.saveCommand == .saveAs)
        #expect(first.available == all)
        let box = try addText(editor.model, "Edit", at: CGPoint(x: 80, y: 50))
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
        let outcome = await editor.upload()
        #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        #expect(coordinator.editors[id] == nil)
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        let expected = try #require(await editor.export()).image.image
        let held = try #require(coordinator.history.record(id: id))
        #expect(held.fileURL == pendingURL(coordinator, id))
        #expect(held.fileIsTemporary == true)
        #expect(held.uploadIsStale == true)
        #expect(held.isUploading)
        let pendingBytes = try Data(contentsOf: pendingURL(coordinator, id))
        let pd = try EditorPixels.decoded(pendingBytes)
        #expect(pd.image.width == 120 && pd.image.height == 60)
        #expect(EditorPixels.rgba(pd.image) == EditorPixels.rgba(expected))
        #expect(world.clipboard.copies.isEmpty)
        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: id)?.isUploading == false }
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map(\.key) == [key])
        #expect(uploads.first?.cacheControl == "no-cache")
        #expect(uploads.first?.data == pendingBytes)
        let d = try EditorPixels.decoded(try #require(uploads.first?.data))
        #expect(d.image.width == 120 && d.image.height == 60 && d.scale == 2)
        #expect(EditorPixels.rgba(d.image) == EditorPixels.rgba(expected))
        #expect(EditorPixels.changedPixels(d.image, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20), from: [255, 255, 255]) > 0)
        let done = try #require(coordinator.history.record(id: id))
        #expect(done.uploadState == .uploaded(url: link, key: key))
        #expect(done.fileURL == nil)
        #expect(done.fileIsTemporary == false)
        #expect(!exists(pendingURL(coordinator, id)))
        #expect(done.uploadIsStale == false)
        #expect(done.pixelWidth == 120 && done.pixelHeight == 60)
        #expect(world.clipboard.copies == [.url(link)])
        #expect(world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
        try await settledEdit(coordinator, id)
    }

    /// coordinator-split:43 (:43), in part; small-tweaks:18 (:21); phase-6b:118 (:144), in part. The capture is set up
    /// as a new "Save and copy image" capture leaves it (the file in the save folder, the card up, its image retained
    /// and on the clipboard); it is the entry to the flow, not a check. Annotate opens the editor at once from the
    /// retained image (no load), titled by the file, and closes the card for good. A box makes the editor unsaved
    /// (`hasUnsavedEditors` stands in for the unsaved dot); Save writes the same file with the box (its decoded pixels
    /// stand in for Quick Look), uploads nothing, records the file's size, clears the unsaved state and puts the edit
    /// on the clipboard in place of the capture's image. Upload then closes the editor, PUTs the file's bytes as a new
    /// object, copies its URL in place of the image and records the uploaded size. Stays: coordinator-split:43, the
    /// unsaved dot and the window closing (`EDPLACE`); the URL showing the stroke is the PUT body, and the real
    /// bucket, by hand. phase-6b:118, reaching `save(_:intent:)` with the after-capture action first (`TARGET`), and
    /// the `action=pin` half (`PINS`).
    @Test func annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        let file = try #require(record.fileURL)
        world.cards.showing.insert(id)
        let image = try CoordinatorWorld.image(width: 4, height: 2)
        coordinator.latestCapture = (id: id, image: ScaledImage(image: image, scale: 1))
        let count = world.clipboard.copy(pngData: original, tiffData: nil)
        coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)

        coordinator.openEditor(recordID: id)
        let editor = try #require(world.editors.editor(for: id))
        #expect(coordinator.openingEditorIDs.isEmpty)
        #expect(editor.model.base === image)
        #expect(editor.model.scale == 1)
        #expect(editor.title == "Shot.png")
        #expect(editor.representedURL == file)
        #expect(editor.presentCount == 1)
        #expect(editor.pushes.first?.record == coordinator.history.record(id: id))
        #expect(editor.pushes.first?.saveCommand == .writeOver)
        #expect(editor.pushes.first?.available == all.subtracting([.uploadAsNew]))
        #expect(world.cards.calls.contains(.close(id, .editorOpened)))
        #expect(world.cards.showing.isEmpty)
        #expect(coordinator.latestCapture == nil)
        #expect(!coordinator.closedOverlays.ids.contains(id))
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)

        editor.draw()
        #expect(coordinator.hasUnsavedEditors)
        #expect(await editor.save())
        let written = try Data(contentsOf: file)
        #expect(written != original)
        let writtenImage = try EditorPixels.decoded(written).image
        try #require(writtenImage.width == 4 && writtenImage.height == 2)
        #expect(EditorPixels.isBlue(try EditorPixels.pixel(written, x: 0, y: 0)))
        #expect(EditorPixels.isBlue(try EditorPixels.pixel(written, x: 3, y: 1)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(coordinator.history.record(id: id)?.uploadState == CaptureRecord.UploadState.none)
        #expect(coordinator.history.record(id: id)?.byteCount == written.count)
        #expect(!coordinator.hasUnsavedEditors)
        #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
        #expect(world.clipboard.pngs.last == written)
        #expect(world.notifier.errors.isEmpty)

        world.date = world.date.addingTimeInterval(1)
        let outcome = await editor.upload()
        #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        #expect(coordinator.editors[id] == nil)
        #expect(world.factory.askedConfigs == [CoordinatorWorld.config])

        try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        #expect(uploads.first?.data == (try Data(contentsOf: file)))
        #expect(EditorPixels.isBlue(try EditorPixels.pixel(try #require(uploads.first?.data), x: 0, y: 0)))
        #expect(uploads.first?.cacheControl == nil)
        let url = publicURL(try #require(uploads.first?.key))
        #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: url, key: try #require(uploads.first?.key)))
        #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF, .pngAndTIFF, .url(url)])
        #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
        #expect(coordinator.history.record(id: id)?.byteCount == uploads.first?.data.count)
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:120 (:173), in part. The capture's own upload is set up as "Also copy image" leaves it (the image
    /// copied and owned, then the upload landing and its URL copied); an editor opened from the card then uploads a
    /// box over the same key, closes while the PUT is held, leaves the clipboard's URL alone during the local write,
    /// and ends with the same link copied again. Stays: the window closing (`EDPLACE`); the capture's own copy is set
    /// up as +Save:30-31, :57-67 leave it (`TARGET`).
    @Test func anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploading(fraction: 0))
        let id = record.id
        let count = world.clipboard.copy(pngData: original, tiffData: nil)
        coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)
        coordinator.startUpload(recordID: id, payload: .data(original), destination: try #require(coordinator.makeDestination()))
        try await eventually { isUploaded(coordinator, id) }
        let k1 = try #require(coordinator.history.record(id: id)?.uploadedKey)
        let url1 = try #require(coordinator.history.record(id: id)?.uploadedURL)
        #expect(world.clipboard.copies == [.pngAndTIFF, .url(url1)])
        coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        defer { destination.releaseUploads() }
        coordinator.openEditor(recordID: id)
        let editor = try #require(world.editors.editor(for: id))
        editor.draw()
        #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        #expect(editor.isClosed)
        #expect(coordinator.editors[id] == nil)
        #expect(world.clipboard.copies == [.pngAndTIFF, .url(url1)])
        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: id)?.isUploading == false }
        #expect(world.clipboard.copies == [.pngAndTIFF, .url(url1), .url(url1)])
        #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: url1, key: k1))
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map(\.key) == [k1, k1])
        #expect(try EditorPixels.isBlue(png: try #require(uploads.last?.data)))
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:119 (:172), in part. The capture is set up as "Upload and copy URL" leaves it with no destination (the
    /// credentials forgotten, the file saved, the image copied and owned). Save takes the clipboard for the edit;
    /// Upload is refused with `Upload not configured` and writes nothing, copies nothing and asks for no
    /// destination, and the editor stays open and unsaved. Stays: the window staying open (`EDPLACE`); the capture's
    /// own copy is set up as +Save:32-34, :57-67 leave it with no destination (`TARGET`).
    @Test func withNoDestinationSaveTakesTheClipboardAndUploadIsRefused() async throws {
        defer { world.removeAll() }
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        let file = try #require(record.fileURL)
        let count = world.clipboard.copy(pngData: original, tiffData: nil)
        coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)
        coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
        coordinator.openEditor(recordID: id)
        let editor = try #require(world.editors.editor(for: id))
        editor.draw()
        #expect(await editor.save())
        try await settledEdit(coordinator, id)
        let saved = try Data(contentsOf: file)
        let afterSave = coordinator.history.record(id: id)
        #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
        #expect(world.clipboard.pngs.last == saved)
        // A second box over the first, so the document is unsaved again before the Upload.
        editor.draw()
        #expect(await editor.upload() == .refused)
        #expect(world.notifier.errors.last?.title == "Upload not configured")
        #expect(world.notifier.errors.last?.message == AppCoordinator.uploadNotConfiguredBody)
        #expect(AppCoordinator.uploadNotConfiguredBody == "Set up a destination in Settings > Upload, then upload again.")
        #expect(try Data(contentsOf: file) == saved)
        #expect(coordinator.history.record(id: id) == afterSave)
        #expect(world.clipboard.copies.count == 2)
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(!editor.isClosed)
        #expect(coordinator.editors[id] === editor)
        #expect(editor.model.hasUnsavedChanges)
    }

    /// phase-4a:127 (:185), in part. A save-folder capture that was never uploaded is first heard without Upload as
    /// New; `upload(asNew: true)` calls the editor's upload action past the window's validation, which would block
    /// ⌥⌘U (design 3.4), to reach the coordinator's write-time refusal: `Not uploaded`, nothing written, the editor
    /// open, no PUT. Upload then writes the file first and makes the capture's first link, copied, with no `New link`
    /// notice. Stays: ⌥⌘U refused by the window's validation, so it does nothing (`EDPLACE`), and its beep (`BEEP`);
    /// the window closing (`EDPLACE`). The refusal's notice is one the window's beep never lets happen.
    @Test func uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        let file = try #require(record.fileURL)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(editor.pushes.first?.available == all.subtracting([.uploadAsNew]))
        editor.draw()
        #expect(await editor.upload(asNew: true) == .refused)
        #expect(world.notifier.errors.last?.title == "Not uploaded")
        #expect(world.notifier.errors.last?.message == "This capture has no link yet. Use Upload.")
        #expect(try Data(contentsOf: file) == original)
        #expect(!editor.isClosed)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: file)))
        try await eventually { isUploaded(coordinator, id) }
        let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
        let done = try #require(coordinator.history.record(id: id))
        #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
        #expect(done.objectLocation == world.location)
        #expect(done.uploadIsStale == false)
        #expect(destination.state.withLock { $0.uploads.count } == 1)
        #expect(world.clipboard.copies == [.url(publicURL(k))])
        #expect(world.notifier.calls.contains(.uploaded(url: publicURL(k), copied: true)))
        #expect(!world.notifier.calls.contains { if case .notice(let t, _, _) = $0 { return t == "New link" } else { return false } })
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:129 (:189). Upload on a capture uploaded before phase 3 (a link with no object location) makes a new
    /// link under a new key with the `New link` notice that the earlier upload stays in the bucket, keeps no prior
    /// upload and nothing to supersede, deletes nothing and copies the new URL. `curl -I` on the old link is the empty
    /// DELETE list.
    @Test func uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key))
        let id = record.id
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        _ = await editor.upload()
        try await eventually { coordinator.history.record(id: id)?.uploadedKey.map { $0 != key } == true }
        #expect(world.notifier.calls.contains(.notice(title: "New link", body: "The earlier upload stays in the bucket.")))
        let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
        #expect(k != key)
        let done = try #require(coordinator.history.record(id: id))
        #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
        #expect(done.objectLocation == world.location)
        #expect(done.priorUpload == nil)
        #expect(done.supersededObjects.isEmpty)
        #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
        #expect(world.clipboard.copies.last == .url(publicURL(k)))
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:130 (:190). With the destination changed while the editor is open, Upload goes to the new bucket as a
    /// new link with the `New link` notice that the destination changed, records the new location, and deletes the
    /// old object at the old bucket (signed for it), leaving nothing superseded. The second bucket is a second fake.
    @Test func uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                            objectLocation: world.location)
        let id = record.id
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        let second = S3DestinationConfig(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                         bucket: "second.tky.io", publicURLTemplate: "https://second.tky.io/{key}")
        let other = FakeDestination()
        world.factory.add(other, at: ObjectLocation(config: second))
        world.settings.s3Config = second
        coordinator.destinationDidChange()
        editor.draw()
        _ = await editor.upload()
        try await eventually { other.state.withLock { $0.uploads.count } == 1 }
        try await eventually { destination.state.withLock { $0.deletedKeys } == [key] }
        try await eventually { coordinator.history.record(id: id)?.supersededObjects.isEmpty == true }
        #expect(world.notifier.calls.contains(.notice(title: "New link", body: "The destination changed, so this uploads as a new link.")))
        let k = try #require(other.state.withLock { $0.uploads.last?.key })
        #expect(k != key)
        let done = try #require(coordinator.history.record(id: id))
        // The fake's public URL is snap.tky.io for every config; the second bucket is pinned by the location.
        #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
        #expect(done.objectLocation == ObjectLocation(config: second))
        #expect(done.priorUpload == nil)
        #expect(destination.state.withLock { $0.uploads.isEmpty })
        #expect(other.state.withLock { $0.deletedKeys.isEmpty })
        #expect(world.factory.askedLocations.contains(world.location))
        try await settledEdit(coordinator, id)
    }

    /// phase-4c:179 (:245). A spotlight and a counter (number 1, 64 px at 2x) uploaded from a saved, never-uploaded
    /// capture are flattened into the file and the object, which carry the same bytes; reopened, the capture has no
    /// annotations left to select and its pixels are the export's: white inside the spotlight's hole, dimmed white
    /// outside it, and the counter's fill.
    @Test func anUploadedCaptureReopensFlatWithItsMarksInThePixels() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)
        let id = record.id
        coordinator.history.add(record)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.model.commitNewShape(try #require(editor.model.makeAnnotation(.spotlight, from: CGPoint(x: 20, y: 20),
                                                                            to: CGPoint(x: 80, y: 60))))
        let counter = try #require(editor.model.makeAnnotation(.counter, from: CGPoint(x: 150, y: 50), to: CGPoint(x: 150, y: 50)))
        editor.model.commitNewShape(counter)
        #expect(editor.model.document.spotlights.count == 1)
        let mark = try #require(counter.counterMark)
        #expect(mark.number == 1)
        #expect(mark.diameter == 64)
        #expect(mark.center == CGPoint(x: 150, y: 50))
        let outcome = await editor.upload()
        let expected = try #require(await editor.export()).image.image
        try await eventually {
            coordinator.history.record(id: id)?.uploadedKey != nil && coordinator.history.record(id: id)?.isUploading == false
        }
        #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        #expect(uploads.first?.data == (try Data(contentsOf: file)))
        #expect(coordinator.history.record(id: id)?.uploadedKey == uploads.first?.key)
        coordinator.openEditor(recordID: id)
        let reopened = try await reopenedEditor(id, after: editor)
        #expect(reopened.model.document.annotations.isEmpty)
        try #require(reopened.model.base.width == 200 && reopened.model.base.height == 100)
        #expect(EditorPixels.rgba(reopened.model.base) == EditorPixels.rgba(expected))
        #expect(EditorPixels.pixel(reopened.model.base, x: 50, y: 40) == [255, 255, 255, 255])
        let dim = EditorPixels.pixel(reopened.model.base, x: 100, y: 90)
        #expect(dim[0...2].allSatisfy { (120...135).contains($0) })
        let fill = EditorPixels.pixel(reopened.model.base, x: 130, y: 50)
        #expect(fill[0] > 230 && fill[1] < 90 && fill[2] < 90)
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:131 (:191), in part. A replace the bucket refuses with a 403 (what a wrong secret gives) closes the
    /// editor, is tried once (a 403 is not retried), and posts `Not uploaded` with the line's body; the record keeps
    /// its link and location, the file holds the edit, and the row still copies the old URL. Annotate reopens the edit
    /// with the stale-copy status, and the next Upload (the right key) replaces the same key and copies the same URL.
    /// Stays: closing and the subtitle as shown (`EDPLACE`). The link serving is the PUT body. The notice's title is
    /// `Not uploaded` (harness D14).
    @Test func aFailedReplaceKeepsTheLinkAndTheEditAndTheRightKeyReplacesIt() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        destination.state.withLock {
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(403, body: "SignatureDoesNotMatch: The request signature we calculated does not match the signature you provided.")
        }
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                            objectLocation: world.location)
        let id = record.id
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        try await eventually {
            world.notifier.calls.contains(.error(title: "Not uploaded", message: "Upload failed. The link still shows the earlier image."))
        }
        #expect(destination.state.withLock { $0.attemptKeys } == [key])
        let failed = try #require(coordinator.history.record(id: id))
        #expect(failed.uploadState == .uploaded(url: link, key: key))
        #expect(failed.objectLocation == world.location)
        #expect(failed.uploadIsStale == true)
        #expect(failed.priorUpload == nil)
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: try #require(record.fileURL))))
        coordinator.copyLinkOrFile(recordID: id)
        #expect(world.clipboard.copies == [.url(link)])
        coordinator.openEditor(recordID: id)
        let reopened = try await reopenedEditor(id, after: editor)
        #expect(world.editors.built.count == 2)
        #expect(EditorPixels.isBlue(reopened.model.base))
        #expect(reopened.pushes.first?.status == EditorSaveTarget.uploadedCopyStaleNotice)
        world.date = world.date.addingTimeInterval(1)
        #expect(await reopened.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        try await eventually { coordinator.history.record(id: id)?.uploadIsStale == false }
        #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))
        #expect(destination.state.withLock { $0.uploads.map(\.key) } == [key])
        #expect(destination.state.withLock { $0.attemptKeys } == [key, key])
        #expect(try EditorPixels.isBlue(png: try #require(destination.state.withLock { $0.uploads.last?.data })))
        #expect(world.clipboard.copies == [.url(link), .url(link)])
        #expect(world.notifier.calls.filter { $0 == .notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote) }.count == 1)
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:133 (:193), in part; phase-4b:112 (:156), in part; phase-4b:113 (:157), in part; phase-4b:114 (:158).
    /// An upload-only capture's failed replace (a 403, tried once) closes the editor and keeps the edit, with its text
    /// and at the cropped size, in `pending/<UUID>.png`, while the record keeps its link. A relaunch (a second
    /// coordinator over the same `history.json`, design 5) reads that state back; the row copies the old URL, Annotate
    /// reopens the pending file's edit with the stale-copy status, and the next Upload replaces the same key, removes
    /// the pending file and leaves the cropped size on the record.
    /// Stays: phase-4a:133, closing and the subtitle as shown (`EDPLACE`). phase-4b:112, the window closing
    /// (`EDPLACE`); the real quit and relaunch, by hand (a second coordinator stands for it); a 403 is not retried and
    /// the title is `Not uploaded`. phase-4b:113, the subtitle as shown (`EDPLACE`).
    @Test func aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload() async throws {
        defer { world.removeAll() }
        let original = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
        destination.state.withLock {
            $0.downloadedData = original
            $0.failuresRemaining = 10
            $0.failure = .httpStatus(403, body: "SignatureDoesNotMatch")
        }
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        let id = record.id
        coordinator.history.add(record)

        // 1
        coordinator.destinationDidChange()
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        let box = try addText(editor.model, "Edit", at: CGPoint(x: 80, y: 50))
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
        #expect(CropGeometry.readout(for: try #require(editor.model.cropDraft)) == "120 × 60")
        let outcome = await editor.upload()
        let expected = try #require(await editor.export()).image.image
        try await eventually {
            world.notifier.calls.contains(.error(title: "Not uploaded", message: EditorUploadPlan.failedReplaceMessage))
        }
        // The edit's thumbnail named (+Editor:217, :249-275): its history save lands before the relaunch reads it.
        try await settledEdit(coordinator, id)

        #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        #expect(coordinator.editors[id] == nil)
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
        #expect(destination.state.withLock { $0.attemptKeys } == [key])
        #expect(destination.state.withLock { $0.uploads.isEmpty })
        #expect(world.notifier.calls.contains(.error(title: "Not uploaded",
                                                     message: "Upload failed. The link still shows the earlier image.")))
        #expect(!world.notifier.errors.contains { $0.title == "Upload failed" })
        let failed = try #require(coordinator.history.record(id: id))
        #expect(failed.uploadState == .uploaded(url: link, key: key))
        #expect(failed.objectLocation == world.location)
        #expect(failed.priorUpload == nil)
        #expect(failed.uploadIsStale == true)
        #expect(failed.fileIsTemporary == true)
        #expect(failed.fileURL == pendingURL(coordinator, id))
        #expect(failed.keepsUnuploadedEdit == true)
        #expect(failed.pixelWidth == 120)
        #expect(failed.pixelHeight == 60)
        #expect(EditorPixels.rgba(try EditorPixels.decoded(Data(contentsOf: pendingURL(coordinator, id))).image)
            == EditorPixels.rgba(expected))

        // 2: the first coordinator is quiescent (no upload running, the edit's thumbnail named); nothing
        // below calls it or runs world.clock.
        try #require(coordinator.history.record(id: id)?.isUploading == false)
        let relaunched = world.makeCoordinator()
        relaunched.history.load()
        let loaded = try #require(relaunched.history.record(id: id))
        #expect(loaded.uploadState == failed.uploadState)
        #expect(loaded.fileURL == failed.fileURL)
        #expect(loaded.fileIsTemporary == failed.fileIsTemporary)
        #expect(loaded.uploadIsStale == failed.uploadIsStale)

        // 3
        relaunched.copyLinkOrFile(recordID: id)
        relaunched.openEditor(recordID: id)
        let reopened = try await reopenedEditor(id, after: editor)
        #expect(world.clipboard.copies == [.url(link)])
        #expect(world.editors.built.count == 2)
        #expect(reopened.title == title(of: record))
        #expect(reopened.representedURL == nil)
        #expect(reopened.model.base.width == 120)
        #expect(reopened.model.base.height == 60)
        #expect(reopened.model.scale == 2)
        #expect(EditorPixels.rgba(reopened.model.base) == EditorPixels.rgba(expected))
        #expect(reopened.model.document == AnnotationDocument(annotations: []))
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
        let reopenPush = try #require(reopened.pushes.first)
        #expect(reopenPush.status == EditorSaveTarget.uploadedCopyStaleNotice)
        #expect(reopenPush.available == all)
        #expect(reopenPush.saveCommand == .writeOver)

        // 4: a later edit, so its thumbnail gets a new name settledEdit can wait for.
        world.date = world.date.addingTimeInterval(1)
        destination.state.withLock { $0.failuresRemaining = 0 }
        relaunched.destinationDidChange()
        let outcome2 = await reopened.upload()
        try await eventually {
            relaunched.history.record(id: id)?.isUploading == false && relaunched.history.record(id: id)?.fileURL == nil
        }
        #expect(outcome2 == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(reopened.isClosed)
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map(\.key) == [key])
        #expect(uploads.first?.cacheControl == "no-cache")
        let decoded = try EditorPixels.decoded(try #require(uploads.first?.data))
        #expect(decoded.image.width == 120)
        #expect(decoded.image.height == 60)
        #expect(decoded.scale == 2)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        #expect(EditorPixels.changedPixels(decoded.image, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20),
                                           from: [255, 255, 255]) > 0)
        #expect(!FileManager.default.fileExists(atPath: pendingURL(relaunched, id).path(percentEncoded: false)))
        let done = try #require(relaunched.history.record(id: id))
        #expect(done.uploadState == .uploaded(url: link, key: key))
        #expect(done.fileURL == nil)
        #expect(done.uploadIsStale == false)
        #expect(done.pixelWidth == 120)
        #expect(done.pixelHeight == 60)
        #expect(done.byteCount == uploads.first?.data.count)
        #expect(world.clipboard.copies == [.url(link), .url(link)])
        #expect(world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
        try await settledEdit(relaunched, id)
    }

    /// phase-4a:132 (:192), in part. With another save folder chosen, a failed replace (a 403) of a capture saved in
    /// the old folder leaves that file unchanged and keeps the edit in `pending/<UUID>.png`; Retry Failed Uploads does
    /// nothing for it (the record is not failed, it keeps its link), and the next Upload replaces the same key with the
    /// edit and removes the pending file. The edit is a drawn box, not a Redact: no test commits an effect (design 5).
    /// Stays: closing (`EDPLACE`). The line's last step is at odds with the code: Retry Failed Uploads does nothing for
    /// this capture; the next ⌘U recovers it (tests-editor.md section 8, Tim's call).
    @Test func aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload() async throws {
        defer { world.removeAll() }
        let folderA = try world.storeSaveFolder()
        let folderB = world.root.appending(path: "Other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folderA, name: "Old.png",
                                                   uploadState: .uploaded(url: link, key: key),
                                                   objectLocation: world.location)
        let id = record.id
        destination.state.withLock {
            $0.downloadedData = original
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(403, body: "SignatureDoesNotMatch")
        }
        try world.saveLocation.store(folderB)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(editor.model.base.width == 4)
        editor.draw()
        _ = await editor.upload()
        try await eventually { world.notifier.errors.contains { $0.title == "Not uploaded" } }
        let old = folderA.appending(path: "Old.png")
        #expect(try Data(contentsOf: old) == original)
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: pendingURL(coordinator, id))))
        let failed = try #require(coordinator.history.record(id: id))
        #expect(failed.fileURL == pendingURL(coordinator, id))
        #expect(failed.fileIsTemporary)
        #expect(failed.uploadIsStale)
        #expect(failed.keepsUnuploadedEdit)
        #expect(failed.uploadState == .uploaded(url: link, key: key))
        #expect(coordinator.history.failedRecords.isEmpty)
        coordinator.retryFailedUploads()
        // Synchronous: a retry would have flipped both at once (startingRetry, startUpload).
        #expect(coordinator.history.record(id: id)?.isUploading == false)
        #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))
        #expect(exists(pendingURL(coordinator, id)))
        coordinator.openEditor(recordID: id)
        let reopened = try await reopenedEditor(id, after: editor)
        #expect(EditorPixels.isBlue(reopened.model.base))
        #expect(reopened.pushes.first?.status == EditorSaveTarget.uploadedCopyStaleNotice)
        world.date = world.date.addingTimeInterval(1)
        #expect(await reopened.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        try await eventually { coordinator.history.record(id: id)?.uploadIsStale == false }
        #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map(\.key) == [key])
        #expect(try EditorPixels.isBlue(png: try #require(uploads.first?.data)))
        #expect(!exists(pendingURL(coordinator, id)))
        #expect(coordinator.history.record(id: id)?.fileURL == nil)
        try world.saveLocation.store(folderA)
        #expect(try Data(contentsOf: old) == original)
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:148 (:215), in part. A new save folder reaches the open editor without any other call: its push gives
    /// `EditorSaveTarget.outsideFolderReason` and ⌘S as Save As…. A Save that reaches the coordinator anyway is refused
    /// with `Not saved` and leaves the file; the fake's `save()` skips the window's validation, so this is the
    /// coordinator's own check (design 3.4). Upload writes the edit to `pending/<UUID>.png` until the PUT lands, never
    /// to the old folder's file. With the first folder chosen again, another capture there is saved over its file.
    /// Stays: ⌘S's panel (`EDSAVEAS`); ⌘W's Save (`CLOSESHEET` and `EDSAVEAS`); the subtitle and closing (`EDPLACE`).
    @Test func aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending() async throws {
        defer { world.removeAll() }
        let folderA = try world.storeSaveFolder()
        let folderB = world.root.appending(path: "Other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        defer { destination.releaseUploads() }
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folderA)
        let (other, _) = try addSavedImage(to: coordinator, in: folderA, name: "Other.png")
        let id = record.id
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(editor.pushes.first?.saveCommand == .writeOver)
        #expect(editor.pushes.first?.status == nil)
        try world.saveLocation.store(folderB)
        try await eventually { editor.pushes.last?.saveFolder == folderB }
        let moved = try #require(editor.pushes.last)
        #expect(moved.status == EditorSaveTarget.outsideFolderReason)
        #expect(moved.saveCommand == .saveAs)
        #expect(moved.available.contains(.save))
        editor.draw()
        #expect(!(await editor.save()))
        #expect(world.notifier.errors.last?.title == "Not saved")
        #expect(world.notifier.errors.last?.message == EditorSaveTarget.outsideFolderReason)
        #expect(try Data(contentsOf: folderA.appending(path: "Shot.png")) == original)
        #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        #expect(try Data(contentsOf: folderA.appending(path: "Shot.png")) == original)
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: pendingURL(coordinator, id))))
        #expect(coordinator.history.record(id: id)?.fileURL == pendingURL(coordinator, id))
        #expect(coordinator.history.record(id: id)?.fileIsTemporary == true)
        destination.releaseUploads()
        try await eventually { isUploaded(coordinator, id) }
        #expect(!exists(pendingURL(coordinator, id)))
        #expect(coordinator.history.record(id: id)?.fileURL == nil)
        let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
        #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: publicURL(k), key: k))
        #expect(try Data(contentsOf: folderA.appending(path: "Shot.png")) == original)
        try world.saveLocation.store(folderA)
        let errorsBefore = world.notifier.errors.count
        coordinator.openEditor(recordID: other.id)
        let second = try await openedEditor(other.id)
        #expect(second.pushes.first?.saveCommand == .writeOver)
        #expect(second.pushes.first?.status == nil)
        second.draw()
        #expect(await second.save())
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: folderA.appending(path: "Other.png"))))
        #expect(world.notifier.errors.count == errorsBefore)
        try await settledEdit(coordinator, id)
        try await settledEdit(coordinator, other.id)
    }

    /// phase-6a:199 (:211), in part: the upload-only half (the "Save and copy image" half is
    /// `CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`). Upload from the editor
    /// on an upload-only capture with a kept drag copy removes `Drag/<record id>` at once. While the PUT is held,
    /// Save As…'s read, Copy Image and a new drag stage give the edit from the pending file; after it, the kept drag
    /// copy and a second Annotate give the edit, and nothing is downloaded. The edit is a drawn box standing for the
    /// arrow.
    /// Stays: the card's Save As… panel (`SAVEAS`); the drop, by hand. The line's "from the card" after an Annotate
    /// cannot happen as written (tests-editor.md section 8), so the test puts the record back in `FakeCards.showing`.
    @Test func uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let id = record.id
        world.cards.showing.insert(id)
        coordinator.retryUpload(recordID: id)
        try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
        let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
        #expect(coordinator.history.record(id: id)?.fileURL == nil)
        #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        defer { destination.releaseUploads() }

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        editor.draw()
        let outcome = await editor.upload()
        #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        #expect(editor.isClosed)
        #expect(!exists(coordinator.dragFiles.folder(for: id)))
        #expect(coordinator.dragFiles.stagedFile(id: id) == nil)
        #expect(world.cards.dragFiles(for: id).last == .some(nil))
        let pending = pendingURL(coordinator, id)
        let current = try #require(coordinator.history.record(id: id))
        #expect(current.fileURL == pending)
        #expect(current.fileIsTemporary)
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: pending)))
        #expect(current.uploadIsStale)
        #expect(current.editedAt == world.date)
        #expect(current.isUploading)

        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        let now = try #require(coordinator.history.record(id: id))
        #expect(try EditorPixels.isBlue(png: try await coordinator.imageData(of: now, downloadTitle: "Saving a copy…")))
        await coordinator.copyImage(recordID: id)
        #expect(try EditorPixels.isBlue(png: try #require(world.clipboard.pngs.last)))
        #expect(world.clipboard.copies.last == .pngAndTIFF)
        world.cards.showing.insert(id)
        coordinator.prepareDragFile(recordID: id)
        try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
        let staged = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: staged)))
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)

        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: id)?.uploadState == .uploaded(url: publicURL(k), key: k) }
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map(\.key) == [k, k])
        #expect(uploads.last?.cacheControl == "no-cache")
        #expect(try EditorPixels.isBlue(png: try #require(uploads.last?.data)))
        let done = try #require(coordinator.history.record(id: id))
        #expect(done.fileURL == nil)
        #expect(!done.uploadIsStale)
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: try #require(coordinator.dragFiles.stagedFile(id: id)))))

        coordinator.openEditor(recordID: id)
        try await eventually { world.editors.built.filter { $0.model.recordID == id }.count == 2 }
        let again = try #require(world.editors.editor(for: id))
        #expect(EditorPixels.isBlue(again.model.base))
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        try await settledEdit(coordinator, id)
    }

    /// phase-6a:199 (:224), in part, the card's Save As… after an editor upload of an upload-only capture (with
    /// `CoordinatorEditorSaveTests.saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal` and CT-2's two tests).
    /// While the editor's PUT is held, Save As… writes the edit from the pending file; after it, from the drag copy
    /// the finished upload kept. Neither reads the bucket or posts `Downloading`.
    /// Stays: the drop, by hand; reaching Save As… after the edit, which only a pin offers (`PINS`). Annotate closes
    /// the card for good, so the test puts the record back in `FakeCards.showing` for the upload's end to keep a drag
    /// copy, as CT-2's test does.
    @Test func saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut() async throws {
        defer { world.removeAll() }
        defer { destination.releaseUploads() }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let id = record.id
        world.cards.showing.insert(id)
        coordinator.retryUpload(recordID: id)
        try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
        let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
        #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        let during = try desktop("During.png")
        let after = try desktop("After.png")
        world.saveAsChooser.answers = [during, after]

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        let outcome = await editor.upload()
        #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        world.cards.showing.insert(id)
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        #expect(coordinator.history.record(id: id)?.fileURL == pendingURL(coordinator, id))

        coordinator.saveAs(recordID: id)
        try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "During.png")) }
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: during)))

        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: id)?.uploadState == .uploaded(url: publicURL(k), key: k) }
        #expect(coordinator.history.record(id: id)?.fileURL == nil)
        #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
        coordinator.saveAs(recordID: id)
        try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "After.png")) }
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: after)))
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        let downloading = world.notifier.calls.contains { call in
            guard case .notice(_, let body, _) = call else { return false }
            return body.hasPrefix("Downloading ")
        }
        #expect(!downloading)
        try await settledEdit(coordinator, id)
    }

    /// phase-7-clop:28 (:30), its editor half (the Retry half is
    /// `CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext`). With Clop on
    /// and running, the editor's Upload over a save-folder capture's link sends Clop's bytes for the edited file over
    /// the link's own key with `Cache-Control: no-cache`, and the link stays; Upload as New of a second edit sends
    /// Clop's bytes for that file under a new key with no `Cache-Control`. Each request is the file the editor wrote.
    /// Real Clop making each object smaller than the file is line 26.
    @Test func anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.optimiseWithClop = true
        world.clop.answers = [.smaller(Data("r1".utf8)), .smaller(Data("n1".utf8))]
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                            objectLocation: world.location)
        let id = record.id
        let file = try #require(record.fileURL)

        coordinator.openEditor(recordID: id)
        let first = try await openedEditor(id)
        first.draw()
        let replaced = await first.upload()
        #expect(replaced == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        try await eventually { coordinator.history.record(id: id)?.isUploading == false }
        let firstFile = try Data(contentsOf: file)
        try await settledEdit(coordinator, id)
        #expect(world.clop.requests == [.png(firstFile)])
        let replace = try #require(destination.state.withLock { $0.uploads }.first)
        #expect(replace.key == key)
        #expect(replace.data == Data("r1".utf8))
        #expect(replace.cacheControl == "no-cache")
        #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))

        world.date = world.date.addingTimeInterval(1)
        coordinator.openEditor(recordID: id)
        let second = try await reopenedEditor(id, after: first)
        second.draw()
        let asNew = await second.upload(asNew: true)
        #expect(asNew == EditorUploadOutcome(wroteLocally: true, enqueued: true))
        try await eventually {
            isUploaded(coordinator, id) && destination.state.withLock { $0.deletedKeys } == [key]
        }
        let secondFile = try Data(contentsOf: file)
        try await settledEdit(coordinator, id)
        #expect(world.clop.requests == [.png(firstFile), .png(secondFile)])
        #expect(world.clop.runningChecks == 2)
        let uploads = destination.state.withLock { $0.uploads }
        try #require(uploads.count == 2)
        #expect(uploads[1].key != key)
        #expect(uploads[1].data == Data("n1".utf8))
        #expect(uploads[1].cacheControl == nil)
    }
}
