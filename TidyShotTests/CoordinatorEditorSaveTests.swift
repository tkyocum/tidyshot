import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The editor's Save, Save As… and Copy through the editor seam: `openEditor` builds a `FakeEditor`, and each
/// test plays the user through the `EditorActions` the coordinator handed it. No window, sheet or panel is built.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorEditorSaveTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    let key = "s/SHOT.png"
    var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
    var destination: FakeDestination { world.factory.standard }
    var all: Set<EditorAction> { Set(EditorAction.allCases) }

    /// The public URL of a template key (the world's `publicURLTemplate`).
    func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

    /// The newest editor built for `id`, once `openEditor`'s load has built one.
    func openedEditor(_ id: UUID) async throws -> FakeEditor {
        try await eventually { world.editors.editor(for: id) != nil }
        return try #require(world.editors.editor(for: id))
    }

    /// The editor built for `id` after `first`, once a second `openEditor` has built it.
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

    /// A red 4 by 2 capture written to `folder/name` and added to history.
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

    /// An upload-only capture in `pending/` whose upload failed, added to history.
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

    /// `<root>/Desktop/<name>`, its folder made: the URL a save panel would return.
    func desktop(_ name: String) throws -> URL {
        let folder = world.root.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    /// The record's `pending/<id>.png` (PendingFileStore.swift:21-23).
    func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL {
        coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).png")
    }

    /// An uploaded capture with no local file, whose object downloads as a red 4 by 2 PNG.
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

    /// The title `presentEditor` gives a record with no save-folder file (+Editor:77-79).
    func title(of record: CaptureRecord) -> String {
        "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// The Crop tool with `rect` drawn; `apply` is Return. Without it the action's export applies the draft.
    func crop(_ model: EditorModel, to rect: CGRect, apply: Bool) {
        model.tool = .crop
        model.cropDraft = rect
        if apply { model.applyCrop() }
    }

    /// A text typed at `point` and committed, as the Text tool does; returns its box.
    func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox {
        model.beginTextEditing(at: point, existing: nil)
        model.updateEditingText(string)
        model.commitTextEditing()
        for annotation in model.document.annotations {
            if case .text(let box) = annotation { return box }
        }
        throw CoordinatorWorldError.noFile
    }

    /// The editor's document rendered again after the action, which already applied any pending crop.
    func expected(_ editor: FakeEditor) async throws -> CGImage {
        try #require(await editor.export()).image.image
    }

    var green: RGBA { RGBA(red: 0, green: 1, blue: 0) }
    var background: BackgroundStyle {
        BackgroundStyle(fill: .solid(green), padding: 8, cornerRadius: 0, shadow: false, aspect: .auto)
    }

    /// phase-4a:94 (:143), in part; small-tweaks:18 (:21), full with
    /// `CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL`, this
    /// test its Save half; phase-7c:170 (:213), in part, the save-over path with no background.
    /// Save on a save-folder capture writes over that file and makes no other, records the written size, renames the
    /// thumbnail to the edit's and draws the edit into it, leaves the editors clean, and uploads nothing.
    /// Stays: phase-4a:94, the unsaved dot clearing (`EDPLACE`) and the menu drawing the row's thumbnail, by hand;
    /// Quick Look is the file's decode, and the new thumbnail's decode is the row's thumbnail. phase-7c:170, the clean
    /// state as the window shows it (`EDPLACE`) and the thumbnail as drawn, by hand.
    @Test func saveWritesOverTheSaveFolderFileAndUploadsNothing() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let original = try CoordinatorWorld.pngData(width: 4, height: 2)
        let file = folder.appending(path: "Shot.png")
        try original.write(to: file)
        let id = UUID()
        let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
        coordinator.history.add(CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 4,
                                              pixelHeight: 2, appName: nil, byteCount: original.count))

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)

        #expect(editor.title == "Shot.png")
        #expect(editor.representedURL == file)
        #expect(editor.presentCount == 1)
        #expect(editor.pushes.first?.saveCommand == .writeOver)
        #expect(editor.pushes.first?.available == all.subtracting([.uploadAsNew]))
        #expect(world.cards.calls.contains(.close(id, .editorOpened)))
        editor.draw()
        #expect(coordinator.hasUnsavedEditors)

        let saved = await editor.save()

        #expect(saved)
        let written = try Data(contentsOf: file)
        #expect(written != original)
        #expect(try EditorPixels.isBlue(png: written))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        #expect(coordinator.history.record(id: id)?.byteCount == written.count)
        try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != thumbnail }
        #expect(!coordinator.hasUnsavedEditors)
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(world.notifier.errors.isEmpty)
        let record = try #require(coordinator.history.record(id: id))
        #expect(record.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date))
        #expect(record.thumbnailFileName == "\(id.uuidString)-1778307200000.png")
        #expect(record.editedAt == world.date)
        #expect(!FileManager.default.fileExists(atPath: coordinator.thumbnails.url(forFileName: thumbnail)
            .path(percentEncoded: false)))
        #expect(record.uploadState == .none)
        #expect(record.uploadIsStale == false)
        // The new thumbnail shows the edit.
        let newThumbnail = try #require(record.thumbnailFileName)
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: coordinator.thumbnails.url(forFileName: newThumbnail))))
    }

    /// An uploaded capture's link, made after Phase 3 (with an object location) or before it (without one).
    nonisolated enum Link: CaseIterable, Sendable { case afterPhase3, beforePhase3 }

    /// phase-4a:95 (:144), in part (`.afterPhase3`); phase-4a:96 (:145), in part (`.beforePhase3`).
    /// Save on an uploaded save-folder capture rewrites the file only: the record keeps its link and location and
    /// is marked stale, the editor hears the stale notice, and nothing is PUT or copied.
    /// Stays: phase-4a:95, the subtitle as shown (`EDPLACE`); the link still showing the original is the absence of a
    /// PUT. phase-4a:96, the subtitle as shown (`EDPLACE`).
    @Test(arguments: Link.allCases)
    func saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link kind: Link) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let location = kind == .afterPhase3 ? world.location : nil
        let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                            objectLocation: location)
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        let first = try #require(editor.pushes.first)
        #expect(first.status == nil)
        #expect(first.available == all)
        #expect(first.saveCommand == .writeOver)
        editor.draw()
        #expect(await editor.save())
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: try #require(record.fileURL))))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        let after = try #require(coordinator.history.record(id: record.id))
        #expect(after.uploadIsStale == true)
        #expect(after.uploadState == .uploaded(url: link, key: key))
        #expect(after.objectLocation == location)
        #expect(editor.pushes.last?.status == EditorSaveTarget.uploadedCopyStaleNotice)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(destination.state.withLock { $0.uploads.isEmpty })
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(world.clipboard.copies.isEmpty)
        try await settledEdit(coordinator, record.id)
    }

    /// phase-4a:99 (:148), in part.
    /// Save over a file whose write fails posts `Not saved` with the reason first, leaves the file and the record as
    /// they were, puts the edit on the clipboard with the editor as its owner, and marks nothing saved.
    /// Stays: the dot staying (`EDPLACE`); Finder's Locked is the immutable flag.
    @Test func saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let file = try #require(record.fileURL)
        let id = record.id
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path(percentEncoded: false)) }
        editor.draw()
        #expect(!(await editor.save()))
        #expect(try Data(contentsOf: file) == original)
        let error = try #require(world.notifier.errors.last)
        #expect(error.title == "Not saved")
        #expect(error.message.hasSuffix(" The edited image is on the clipboard."))
        #expect(error.message.count > " The edited image is on the clipboard.".count)
        #expect(world.clipboard.copies == [.image])
        #expect(try EditorPixels.isBlue(png: try #require(world.clipboard.pngs.first)))
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
        #expect(coordinator.history.record(id: id)?.editedAt == nil)
        #expect(world.logLines.contains { $0.hasPrefix("Save over failed: ") })
        #expect(editor.model.hasUnsavedChanges)
    }

    /// phase-4a:98 (:147), full; phase-4b:107 (:151), full.
    /// Save on an upload-only capture whose upload failed rewrites `pending/<UUID>.png` in place with the stroke and
    /// uploads nothing; Retry Failed Uploads then PUTs exactly those bytes, the record takes the link, the pending file
    /// goes, and the link is copied and announced.
    /// Stays: nothing. Wi-Fi off is the record's failed state; Wi-Fi on and the bucket are the fake.
    @Test func saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
        let id = UUID()
        let pending = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        let record = CaptureRecord(id: id, fileURL: pending, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."), byteCount: png.count)
        coordinator.history.add(record)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(editor.representedURL == nil)
        #expect(editor.title == title(of: record))
        let first = try #require(editor.pushes.first)
        #expect(first.saveCommand == .writeOver)
        #expect(first.status == nil)
        #expect(first.available == [.save, .saveAs, .copy, .upload])
        editor.model.commitNewShape(try #require(editor.model.makeStroke(.pencil, points: [CGPoint(x: 20, y: 20),
                                     CGPoint(x: 100, y: 60), CGPoint(x: 180, y: 20)])))
        #expect(await editor.save())
        let expected = try #require(await editor.export()).image.image
        let written = try Data(contentsOf: pending)
        #expect(written != png)
        let decoded = try EditorPixels.decoded(written)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        let p = EditorPixels.pixel(decoded.image, x: 100, y: 60)
        #expect(p[0] > 200 && p[1] < 100 && p[2] < 100)
        #expect(try FileManager.default.contentsOfDirectory(atPath: coordinator.pendingFiles.directory.path(percentEncoded: false))
            == ["\(id.uuidString).png"])
        let saved = try #require(coordinator.history.record(id: id))
        #expect(saved.uploadState == .failed(message: "Upload was interrupted."))
        #expect(saved.fileURL == pending)
        #expect(saved.uploadIsStale == false)
        #expect(saved.byteCount == written.count)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        coordinator.retryFailedUploads()
        try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        #expect(uploads.first?.data == written)
        #expect(uploads.first?.contentType == "image/png")
        let k = try #require(uploads.first?.key)
        let done = try #require(coordinator.history.record(id: id))
        #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
        #expect(done.fileURL == nil)
        #expect(!exists(pending))
        #expect(world.clipboard.copies == [.url(publicURL(k))])
        #expect(world.notifier.calls.contains(.uploaded(url: publicURL(k), copied: true)))
        try await settledEdit(coordinator, id)
    }

    /// phase-4b:71 (:99), full; phase-4b:73 (:101), full.
    /// A crop read out as 800 × 400, applied with Return and saved, writes that pixel size into the same file at the
    /// capture's scale (DPI 72 × scale) with exactly the cropped picture, and the record takes the size; Annotate again
    /// opens the cropped file at its new size with no crop pending, and Crop starts from the whole picture.
    /// Stays: nothing. `sips` is the decode and the DPI read; Quick Look is the pixel comparison; the Retina display is
    /// the scale argument.
    @Test(arguments: [CGFloat(1), CGFloat(2)])
    func saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale: CGFloat) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 1000, height: 600, scale: scale)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let id = UUID()
        coordinator.history.add(CaptureRecord(id: id, fileURL: file, pixelWidth: 1000, pixelHeight: 600, appName: nil,
                                              byteCount: png.count))

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        let first = try #require(editor.pushes.first)
        #expect(first.saveCommand == .writeOver)
        #expect(first.available == all.subtracting([.uploadAsNew]))
        #expect(first.status == nil)
        crop(editor.model, to: CGRect(x: 100, y: 100, width: 800, height: 400), apply: false)
        #expect(CropGeometry.readout(for: try #require(editor.model.cropDraft)) == "800 × 400")
        editor.model.applyCrop()
        #expect(editor.model.document.crop == CGRect(x: 100, y: 100, width: 800, height: 400))
        #expect(editor.model.tool == .redact)

        let saved = await editor.save()
        let expected = try await expected(editor)

        #expect(saved)
        let written = try Data(contentsOf: file)
        let decoded = try EditorPixels.decoded(written)
        #expect(decoded.image.width == 800)
        #expect(decoded.image.height == 400)
        #expect(decoded.scale == scale)
        #expect(abs(try #require(EditorPixels.dpiWidth(of: written)) - 72 * scale) < 0.5)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        let record = try #require(coordinator.history.record(id: id))
        #expect(record.pixelWidth == 800)
        #expect(record.pixelHeight == 400)
        #expect(record.byteCount == written.count)
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(world.notifier.errors.isEmpty)

        editor.close()
        #expect(coordinator.editors[id] == nil)
        coordinator.openEditor(recordID: id)
        let reopened = try await reopenedEditor(id, after: editor)

        #expect(world.editors.built.count == 2)
        #expect(reopened.model.base.width == 800)
        #expect(reopened.model.base.height == 400)
        #expect(reopened.model.scale == scale)
        #expect(reopened.model.document == AnnotationDocument(annotations: []))
        #expect(!reopened.model.hasUnsavedChanges)
        #expect(reopened.model.cropDraft == nil)
        reopened.model.tool = .crop
        #expect(reopened.model.cropDraft == CGRect(x: 0, y: 0, width: 800, height: 400))
        #expect(reopened.title == "Shot.png")
        try await settledEdit(coordinator, id)
    }

    /// phase-4b:105 (:149), full.
    /// On a saved capture never uploaded, a text, an ellipse and a crop saved with ⌘S land in the same file: it is
    /// the cropped size at the capture's scale, its pixels are the editor's render, and the ellipse's stroke and the
    /// text are in them. The row's Annotate is menu UI that calls `openEditor`, where the test starts.
    /// Stays: nothing.
    @Test func saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 400, height: 200, scale: 2, white: true)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 400, pixelHeight: 200, appName: nil, byteCount: png.count)
        coordinator.history.add(record)
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        let box = try addText(editor.model, "Hello", at: CGPoint(x: 110, y: 70))
        editor.model.commitNewShape(try #require(editor.model.makeAnnotation(.ellipse, from: CGPoint(x: 220, y: 40),
                                                                            to: CGPoint(x: 340, y: 140))))
        #expect(editor.model.document.annotations.count == 2)
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 320, height: 160), apply: true)
        #expect(editor.title == "Shot.png")
        #expect(editor.representedURL == file)
        #expect(await editor.save())
        let expected = try #require(await editor.export()).image.image
        let decoded = try EditorPixels.decoded(Data(contentsOf: file))
        #expect(decoded.image.width == 320)
        #expect(decoded.image.height == 160)
        #expect(decoded.scale == 2)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        let e = EditorPixels.pixel(decoded.image, x: 240, y: 24)
        #expect(e[0] > 200 && e[1] < 100 && e[2] < 100)
        #expect(EditorPixels.changedPixels(decoded.image, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20),
                                           from: [255, 255, 255]) > 0)
        #expect(coordinator.history.record(id: record.id)?.pixelWidth == 320)
        #expect(world.factory.askedConfigs.isEmpty)
        try await settledEdit(coordinator, record.id)
    }

    /// phase-7c:170 (:213), in part, the composed canvas, the record's size and the thumbnail; phase-7c:171 (:214), in
    /// part.
    /// Save with a background writes the composed canvas over the file, leaves the editor clean, gives the record the
    /// canvas's size, and draws the background into the renamed thumbnail; Annotate again opens that file flat, with no
    /// background on the document (the switch's getter reads off), and a background set again goes around the first.
    /// Stays: phase-7c:170, the clean state as the window shows it (`EDPLACE`) and the thumbnail as drawn, by hand.
    /// phase-7c:171, the popover's switch turned on, whose setter reads `AppSettings.shared.backgroundStyle` (`BGPOP`),
    /// and the switch drawn in the window (`EDPLACE`); whether a second background is expected is Tim's call.
    @Test func saveWithABackgroundWritesTheComposedCanvasAndReopensFlat() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: 1)
        let file = folder.appending(path: "Shot.png")
        try original.write(to: file)
        let id = UUID()
        let thumb = try coordinator.thumbnails.write(Data("png".utf8), id: id)
        #expect(thumb == "\(id.uuidString).png")
        coordinator.history.add(CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumb, pixelWidth: 4, pixelHeight: 2,
                                              appName: nil, byteCount: original.count))
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        editor.model.setBackground(background)
        #expect(await editor.save())
        let written = try Data(contentsOf: file)
        let decoded = try EditorPixels.decoded(written)
        try #require(decoded.image.width == 20 && decoded.image.height == 18)
        #expect(decoded.scale == 1)
        for (x, y) in [(0, 0), (7, 7), (19, 17)] { #expect(EditorPixels.pixel(decoded.image, x: x, y: y) == [0, 255, 0, 255]) }
        #expect(EditorPixels.isBlue(EditorPixels.pixel(decoded.image, x: 8, y: 8)))
        #expect(EditorPixels.isBlue(EditorPixels.pixel(decoded.image, x: 11, y: 9)))
        #expect(!editor.model.hasUnsavedChanges)
        let rec = try #require(coordinator.history.record(id: id))
        #expect(rec.pixelWidth == 20)
        #expect(rec.pixelHeight == 18)
        #expect(rec.byteCount == written.count)
        #expect(rec.editedAt == world.date)
        try await eventually {
            coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
        }
        #expect(!exists(coordinator.thumbnails.url(forFileName: thumb)))
        let thumbURL = coordinator.thumbnails.url(forFileName: coordinator.thumbnails.fileName(for: id, editedAt: world.date))
        let t = try EditorPixels.decoded(Data(contentsOf: thumbURL))
        try #require(t.image.width == 20 && t.image.height == 18)
        #expect(EditorPixels.pixel(t.image, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.isBlue(EditorPixels.pixel(t.image, x: 8, y: 8)))
        editor.close()
        #expect(coordinator.editors[id] == nil)
        coordinator.openEditor(recordID: id)
        let second = try await reopenedEditor(id, after: editor)
        try #require(second.model.base.width == 20 && second.model.base.height == 18)
        #expect(EditorPixels.pixel(second.model.base, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.isBlue(EditorPixels.pixel(second.model.base, x: 8, y: 8)))
        #expect(second.model.document == AnnotationDocument())
        #expect(second.model.document.background == nil)
        #expect(!second.model.hasUnsavedChanges)
        second.model.setBackground(background)
        let export = try #require(await second.export())
        #expect(export.image.image.width == 36)
        #expect(export.image.image.height == 34)
        #expect(EditorPixels.pixel(export.image.image, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.pixel(export.image.image, x: 8, y: 8) == [0, 255, 0, 255])
        #expect(EditorPixels.isBlue(EditorPixels.pixel(export.image.image, x: 16, y: 16)))
    }

    /// phase-6a:199 (:211), in part, the "Save and copy image" half (the line's last sentence, with ⌘S); the other
    /// half is `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`.
    /// Save over the file removes the capture's `Drag/<record id>` folder and the card's drag file at once; after it
    /// the image read, Copy Image, a new press on the card (which stages the edit again) and Annotate all give the
    /// edit, read from the file and never from the bucket.
    /// Stays: the card's Save As… panel (`SAVEAS`); the drop, by hand. The line's "from the card" after an Annotate
    /// cannot happen as written, since Annotate closes the card (tests-editor.md section 8).
    @Test func saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        let file = try #require(record.fileURL)
        world.cards.showing.insert(id)
        coordinator.prepareDragFile(recordID: id)
        try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
        let staged = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
        #expect(try Data(contentsOf: staged) == original)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(world.cards.calls.contains(.close(id, .editorOpened)))
        editor.draw()
        #expect(await editor.save())
        #expect(!exists(coordinator.dragFiles.folder(for: id)))
        #expect(coordinator.dragFiles.stagedFile(id: id) == nil)
        #expect(world.cards.dragFiles(for: id).last == .some(nil))
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: file)))
        let current = try #require(coordinator.history.record(id: id))
        #expect(try EditorPixels.isBlue(png: await coordinator.imageData(of: current)))
        await coordinator.copyImage(recordID: id)
        #expect(try EditorPixels.isBlue(png: try #require(world.clipboard.pngs.last)))
        world.cards.showing.insert(id)
        let before = world.cards.dragFiles(for: id).count
        coordinator.prepareDragFile(recordID: id)
        try await eventually { world.cards.dragFiles(for: id).count > before && world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
        let again = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
        #expect(try Data(contentsOf: again) == Data(contentsOf: file))
        editor.close()
        #expect(coordinator.editors[id] == nil)
        coordinator.openEditor(recordID: id)
        try await eventually { world.editors.built.count == 2 }
        #expect(EditorPixels.isBlue(try #require(world.editors.editor(for: id)).model.base))
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
        try await settledEdit(coordinator, id)
    }

    /// phase-6a:199 (:224), in part, the card's Save As… after an edit saved over the file (the line's last
    /// sentence; with `CoordinatorEditorUploadTests.saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut`
    /// and CT-2's two tests). After the edit is saved over the save-folder file, which removes the capture's drag copy,
    /// Save As… (`saveAs(recordID:)`, the panel `world.saveAsChooser`) suggests the capture's own name and writes the
    /// edited image to the chosen file, never the one before the edit, read from the file and not from the bucket.
    /// Stays: the drop, by hand; reaching Save As… after the edit, which only a pin offers (`PINS`; Recent Captures
    /// has no Save As…, RecentCapturesMenu.swift:110-121).
    @Test func saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        world.cards.showing.insert(id)
        coordinator.prepareDragFile(recordID: id)
        try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
        let staged = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
        #expect(try Data(contentsOf: staged) == original)
        let copy = try desktop("Edited.png")
        world.saveAsChooser.answers = [copy]

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        #expect(await editor.save())
        #expect(!exists(coordinator.dragFiles.folder(for: id)))

        coordinator.saveAs(recordID: id)
        try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Edited.png")) }
        #expect(world.saveAsChooser.asked.map(\.fileName) == ["Shot.png"])
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: copy)))
        #expect(try Data(contentsOf: copy) != original)
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
        try await settledEdit(coordinator, id)
    }

    /// phase-4a:97 (:146), in part.
    /// An upload-only capture has no file to write over, so Save stays on and ⌘S runs Save As… (the first push's
    /// `saveCommand` is `.saveAs` and its status `EditorSaveTarget.noFileReason`, EST:16). The suggestion, read through
    /// `editor.actions.saveAsSuggestion()` as the panel reads it when it opens, is the file name template's name with
    /// the current counter in the save folder, and no counter is drawn (+RecordActions:321-330). Save As… writes the
    /// PNG, posts `Saved` and touches no record, so nothing uploads and no link goes on the clipboard
    /// (+Editor:283-304, +RecordActions:291-297).
    /// Stays: the sheet, its name and folder (`EDSAVEAS`); "Save is on" as the toolbar shows it, and the dot
    /// (`EDPLACE`). The first push's `available` is the rule.
    @Test func saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "shot-{counter}"
        _ = world.settings.nextCounter()
        let coordinator = world.makeCoordinator()
        let record = try addUploadOnly(to: coordinator)
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        editor.draw()
        let first = try #require(editor.pushes.first)
        #expect(first.available.contains(.save))
        #expect(first.saveCommand == .saveAs)
        #expect(first.status == EditorSaveTarget.noFileReason)
        let suggestion = editor.actions.saveAsSuggestion()
        #expect(suggestion == EditorNaming.SaveAsSuggestion(fileName: "shot-1.png", directory: folder, mediaKind: .image))
        let target = folder.appending(path: "shot-1.png")
        #expect(await editor.saveAs(to: target))
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: target)))
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "shot-1.png")))
        #expect(!editor.model.hasUnsavedChanges)
        #expect(coordinator.history.records.count == 1)
        #expect(coordinator.history.record(id: record.id) == record)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.settings.currentCounter == 1)
    }

    /// phase-4a:102 (:151), in part.
    /// Save As… elsewhere on a 2x capture writes the edit at 144 dpi (`sips` is the DPI read, here `dpiWidth`) and
    /// leaves the capture alone: its file and its record are unchanged, so the editor keeps its title; no record and no
    /// card are added, no shutter plays and nothing uploads (+Editor:283-304, +RecordActions:291-297). The suggestion,
    /// read through `editor.actions.saveAsSuggestion()` as the panel reads it, is the capture's own file name in the
    /// save folder (+RecordActions:321-330).
    /// Stays: the panel's suggestion and the choice (`EDSAVEAS`); the dot (`EDPLACE`).
    @Test func saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder, scale: 2)
        let id = record.id
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(editor.model.scale == 2)
        editor.draw()
        #expect(editor.actions.saveAsSuggestion() == EditorNaming.SaveAsSuggestion(fileName: "Shot.png", directory: folder,
                                                                                   mediaKind: .image))
        let target = try desktop("Edited.png")
        #expect(await editor.saveAs(to: target))
        let written = try Data(contentsOf: target)
        #expect(try EditorPixels.isBlue(png: written))
        #expect(abs(try #require(EditorPixels.dpiWidth(of: written)) - 144) < 0.5)
        #expect(try Data(contentsOf: try #require(record.fileURL)) == original)
        #expect(coordinator.history.records.count == 1)
        #expect(coordinator.history.record(id: id) == record)
        #expect(world.cards.calls == [.close(id, .editorOpened)])
        #expect(world.shutterCount == 0)
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Edited.png")))
        #expect(world.editors.built.count == 1)
        #expect(!editor.model.hasUnsavedChanges)
    }

    /// phase-4a:106 (:157), in part.
    /// Save As… onto the capture's own file is a Save (`EditorSaveTarget.saveAsWritesOverOwnFile`, EST:50-56;
    /// +Editor:286-290): the file holds the edit, the folder holds no second file, the thumbnail is named for the edit,
    /// `editedAt` is set and no `Saved` notice is posted, as after ⌘S. On an uploaded capture the record turns stale
    /// and the last push's status is `EditorSaveTarget.uploadedCopyStaleNotice`; on a never-uploaded one neither.
    /// Nothing uploads.
    /// Stays: the Replace confirmation (`EDSAVEAS`); the subtitle as shown (`EDPLACE`).
    @Test(arguments: [false, true])
    func saveAsOntoItsOwnFileIsASave(uploaded: Bool) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder,
                                            uploadState: uploaded ? .uploaded(url: link, key: key) : .none,
                                            objectLocation: uploaded ? world.location : nil)
        let id = record.id
        let file = try #require(record.fileURL)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        #expect(await editor.saveAs(to: file))
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: file)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        try await eventually {
            coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
        }
        #expect(coordinator.history.record(id: id)?.editedAt == world.date)
        #expect(!world.notifier.calls.contains { if case .saved = $0 { return true } else { return false } })
        #expect(coordinator.history.record(id: id)?.uploadIsStale == uploaded)
        #expect(editor.pushes.last?.status == (uploaded ? EditorSaveTarget.uploadedCopyStaleNotice : nil))
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
    }

    /// phase-4b:76 (:104).
    /// Save As… with a crop draft still open writes a copy at the cropped pixel size and the capture's scale, pixel for
    /// pixel the export (which applies the draft first, as the window's export does, EWC:302-303), and leaves the
    /// capture's file, its folder and its record unchanged (+Editor:283-304, +RecordActions:291-297).
    @Test func saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)
        coordinator.history.add(record)
        let url = try desktop("Crop.png")
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
        #expect(await editor.saveAs(to: url))
        let expected = try #require(await editor.export()).image.image
        let decoded = try EditorPixels.decoded(Data(contentsOf: url))
        #expect(decoded.image.width == 120)
        #expect(decoded.image.height == 60)
        #expect(decoded.scale == 2)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        #expect(try Data(contentsOf: file) == png)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        #expect(coordinator.history.record(id: record.id) == record)
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Crop.png")))
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// phase-7c:172 (:215), in part.
    /// Save As… with a solid background writes the composed image: the fill around the edit, 20 by 18 for a 4 by 2
    /// capture with padding 8. The capture is left alone: its record, its file, its folder and its thumbnail are
    /// unchanged, and with no clipboard owner the clipboard is untouched (+Editor:283-304, :436-446).
    /// Stays: the panel (`EDSAVEAS`).
    @Test func saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: 1)
        let file = folder.appending(path: "Shot.png")
        try original.write(to: file)
        let id = UUID()
        let thumb = try coordinator.thumbnails.write(Data("png".utf8), id: id)
        coordinator.history.add(CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumb, pixelWidth: 4, pixelHeight: 2,
                                              appName: nil, byteCount: original.count))
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        editor.model.setBackground(background)
        let before = coordinator.history.record(id: id)
        let target = try desktop("Composed.png")
        #expect(await editor.saveAs(to: target))
        let d = try EditorPixels.decoded(Data(contentsOf: target))
        try #require(d.image.width == 20 && d.image.height == 18)
        #expect(EditorPixels.pixel(d.image, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.isBlue(EditorPixels.pixel(d.image, x: 8, y: 8)))
        #expect(coordinator.history.record(id: id) == before)
        #expect(try Data(contentsOf: file) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        #expect(coordinator.history.record(id: id)?.thumbnailFileName == "\(id.uuidString).png")
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Composed.png")))
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// phase-4a:112 (:165).
    /// With "Show notification" off, Copy puts the edit on the clipboard and owns it for the capture, and posts
    /// nothing (+Editor:451-466). The retained capture opens the editor at once, and the editor stays open and changed.
    @Test func copyWithShowNotificationOffPostsNothing() async throws {
        defer { world.removeAll() }
        world.settings.showNotification = false
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil)
        coordinator.history.add(record)
        coordinator.latestCapture = (id: record.id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
        coordinator.openEditor(recordID: record.id)
        let editor = try #require(world.editors.editor(for: record.id))
        #expect(coordinator.openingEditorIDs.isEmpty)
        editor.draw()
        await editor.copy()
        #expect(world.clipboard.copies == [.pngAndTIFF])
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: world.clipboard.changeCount))
        #expect(world.notifier.calls.isEmpty)
        #expect(editor.model.hasUnsavedChanges)
        #expect(!editor.isClosed)
        #expect(try EditorPixels.isBlue(png: try #require(world.clipboard.pngs.first)))
    }

    /// phase-4b:77 (:105); phase-4b:92 (:132), in part.
    /// Copy with nothing selected and a crop draft open puts the cropped image on the clipboard at the capture's
    /// scale, 144 dpi for a 2x capture, so its point size is half its pixels (Preview is the `pngs` decode). It says
    /// `Image copied` with the file's name, owns the clipboard, and leaves the file, the record and the window alone
    /// (+Editor:451-466). Then `editor.actions.objectClipboard.copy`, which the canvas's ⌘C calls with an object
    /// selected (EWC:75), copies the object and leaves the image's owner and the notices alone (+Editor:111-116).
    /// Stays: phase-4b:92, which command reaches the copy: ⌘C with and without a selection, ⇧⌘C, the toolbar button
    /// (`EDPLACE`).
    @Test func copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)
        let id = record.id
        coordinator.history.add(record)

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.model.commitNewShape(try #require(editor.model.makeAnnotation(.rectangle, from: CGPoint(x: 50, y: 30),
                                                                            to: CGPoint(x: 110, y: 70))))
        editor.model.selection = nil
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
        await editor.copy()
        let expected = try await expected(editor)
        editor.actions.objectClipboard.copy(Data("clip".utf8))

        #expect(world.clipboard.copies.first == .pngAndTIFF)
        let copied = try #require(world.clipboard.pngs.first)
        #expect(world.clipboard.pngs.count == 1)
        let decoded = try EditorPixels.decoded(copied)
        #expect(decoded.image.width == 120)
        #expect(decoded.image.height == 60)
        #expect(decoded.scale == 2)
        #expect(abs(try #require(EditorPixels.dpiWidth(of: copied)) - 144) < 0.5)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
        #expect(world.notifier.calls == [.notice(title: "Image copied", body: "Shot.png")])
        #expect(try Data(contentsOf: file) == png)
        #expect(coordinator.history.record(id: id) == record)
        #expect(!editor.isClosed)
        #expect(world.clipboard.copies == [.pngAndTIFF, .annotationClip(Data("clip".utf8))])
        #expect(world.clipboard.copies.last == .annotationClip(Data("clip".utf8)))
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
        #expect(world.notifier.calls.count == 1)
    }

    /// phase-7c:169 (:212), in part.
    /// Copy with a solid background puts the composed canvas on the clipboard (Preview is the `pngs` decode): 20 by 18
    /// at scale 1, the fill at both corners and the edit inside. It says `Image copied` with the file's name, owns the
    /// clipboard, and leaves the edit unsaved, since Copy never marks saved (+Editor:451-466).
    /// Stays: the window's routing to `copyImage` (`EDPLACE`).
    @Test func copyWithABackgroundPutsTheComposedCanvasOnTheClipboard() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder)
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        editor.draw()
        editor.model.setBackground(background)
        await editor.copy()
        #expect(world.clipboard.copies == [.pngAndTIFF])
        let copied = try #require(world.clipboard.pngs.first)
        #expect(world.clipboard.pngs.count == 1)
        let d = try EditorPixels.decoded(copied)
        try #require(d.image.width == 20 && d.image.height == 18)
        #expect(d.scale == 1)
        #expect(EditorPixels.pixel(d.image, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.pixel(d.image, x: 19, y: 17) == [0, 255, 0, 255])
        #expect(EditorPixels.isBlue(EditorPixels.pixel(d.image, x: 8, y: 8)))
        #expect(EditorPixels.isBlue(EditorPixels.pixel(d.image, x: 11, y: 9)))
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: world.clipboard.changeCount))
        #expect(world.notifier.calls.contains(.notice(title: "Image copied", body: "Shot.png")))
        #expect(editor.model.hasUnsavedChanges)
    }

    nonisolated enum Write: CaseIterable, Sendable { case save, saveAs }

    /// phase-4a:115 (:168) `(.save, false)`; phase-4a:116 (:169) `(.saveAs, false)`; phase-4a:117 (:170)
    /// `(.saveAs, true)`; phase-4a:118 (:171) `(.save, true)`.
    /// The clipboard rule after Save and Save As…: while the clipboard still holds what TidyShot put there for the
    /// capture, the edit replaces it and TidyShot owns it at the new count; once something else was copied since
    /// (TextEdit's text), it is left alone (+Editor:218, :302, :436-446; the rule is `EditorClipboardTests`',
    /// EC:15-18). Preview is the `pngs` decode. The capture's own copy and owner are set up as +Save:57-67 leaves
    /// them; that step is in `save(_:intent:)` (`TARGET`), and no test pins it today.
    @Test(arguments: Write.allCases, [false, true])
    func aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write: Write, userCopied: Bool) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
        let count = world.clipboard.copy(pngData: original, tiffData: nil)
        coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)
        if userCopied { world.clipboard.setString("From TextEdit") }
        coordinator.openEditor(recordID: id)
        let editor = try #require(world.editors.editor(for: id))
        editor.draw()
        let writtenURL: URL
        switch write {
        case .save:
            #expect(await editor.save())
            writtenURL = try #require(record.fileURL)
        case .saveAs:
            writtenURL = try desktop("Shot.png")
            #expect(await editor.saveAs(to: writtenURL))
        }
        let written = try Data(contentsOf: writtenURL)
        #expect(try EditorPixels.isBlue(png: written))
        if userCopied {
            #expect(world.clipboard.copies == [.pngAndTIFF, .string("From TextEdit")])
            #expect(world.clipboard.pngs.count == 1)
            #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
            #expect(world.clipboard.changeCount == 2)
        } else {
            #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
            #expect(world.clipboard.pngs.last == written)
            #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 2))
        }
        if write == .save { try await settledEdit(coordinator, id) }
    }

    /// Review 2026-11-06, finding 2. Copy Image from the card (`copyImage(recordID:)`) after the capture's own copy
    /// takes the clipboard for the capture, so a redaction saved from the editor replaces the original there; once
    /// another app copied since (TextEdit's text), the save leaves it alone. The capture's copy and owner are set up
    /// as +Save leaves them, as in `aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture`.
    @Test(arguments: [false, true])
    func aSaveAfterCopyImageReplacesTheClipboardUnlessAnotherAppCopiedSince(otherAppCopied: Bool) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
        let count = world.clipboard.copy(pngData: original, tiffData: nil)
        coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)

        await coordinator.copyImage(recordID: id)
        #expect(world.clipboard.pngs == [original, original])
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 2))
        if otherAppCopied { world.clipboard.changeCount += 1 }

        coordinator.openEditor(recordID: id)
        let editor = try #require(world.editors.editor(for: id))
        editor.draw()
        #expect(await editor.save())
        let written = try Data(contentsOf: try #require(record.fileURL))
        #expect(try EditorPixels.isBlue(png: written))
        if otherAppCopied {
            #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
            #expect(world.clipboard.pngs.last == original)
            #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 2))
            #expect(world.clipboard.changeCount == 3)
        } else {
            #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF, .pngAndTIFF])
            #expect(world.clipboard.pngs.last == written)
            #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 3))
        }
        try await settledEdit(coordinator, id)
    }
}
