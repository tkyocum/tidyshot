import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The capture save path on a built coordinator over a value origin (capture seams design 2.1, `TARGET`):
/// `save(_:from:intent:)` and what it runs, `persist`, `writeFile`, `writePendingFile`, `copyOnly` and
/// `withWindowBackground`. Images and origins come from `CaptureSamples`; no ScreenCaptureKit object is made.
/// Every save passes an explicit intent (the forwarder's `.standard` reads `AppSettings.shared`) and stores a
/// folder first unless it is upload-only, so no folder panel is built, even by a copy-only save that regresses. Overlay is off, since a
/// card on screen reads the screens. A test that saves a record waits for its thumbnail before it ends, so a
/// late write cannot recreate a folder in the removed root. The one held fake is the destination's upload,
/// released in a `defer` declared right after `removeAll()`'s.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorCaptureSaveTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
        world.settings.showOverlay = false
    }

    private var destination: FakeDestination { world.factory.standard }

    @discardableResult
    private func save(_ coordinator: AppCoordinator, _ image: ScaledImage, _ origin: CaptureOrigin,
                      _ intent: CaptureIntent) async -> CaptureRecord? {
        await coordinator.save(image, from: origin, intent: intent)
    }

    private func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
        coordinator.history.record(id: id)?.uploadedURL != nil
    }

    private func thumbnailLanded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
        coordinator.history.record(id: id)?.thumbnailFileName != nil
    }

    private func exists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func fileSize(_ url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int
    }

    private func openedEditor(_ id: UUID) async throws -> FakeEditor {
        try await eventually { world.editors.editor(for: id) != nil }
        return try #require(world.editors.editor(for: id))
    }

    /// T1, phase-1:36 (:38), full. Three captures under the template `Shot`, two on one coordinator and one on a
    /// second over the same folder and history (a relaunch), are `Shot.png`, `Shot 2.png` and `Shot 3.png` in the
    /// chosen folder, each with its `Screenshot saved`. The template's date tokens are `FileNamerTests`'.
    @Test func capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        let counter = world.settings.currentCounter
        let intent = CaptureIntent(action: .save)
        let first = world.makeCoordinator()
        let a = try #require(await save(first, try CaptureSamples.image(width: 40, height: 30), CaptureSamples.area(), intent))
        let b = try #require(await save(first, try CaptureSamples.image(width: 40, height: 30), CaptureSamples.area(), intent))
        let second = world.makeCoordinator()
        second.history.load()
        let c = try #require(await save(second, try CaptureSamples.image(width: 40, height: 30), CaptureSamples.area(), intent))

        #expect(a.fileURL?.lastPathComponent == "Shot.png")
        #expect(b.fileURL?.lastPathComponent == "Shot 2.png")
        #expect(c.fileURL?.lastPathComponent == "Shot 3.png")
        #expect(world.settings.currentCounter == counter)
        #expect(CaptureSamples.fileNames(in: folder) == ["Shot 2.png", "Shot 3.png", "Shot.png"])
        #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png"),
                                         .saved(title: "Screenshot saved", file: "Shot 2.png"),
                                         .saved(title: "Screenshot saved", file: "Shot 3.png")])
        #expect(first.lastCaptureURL == b.fileURL)
        #expect(second.lastCaptureURL == c.fileURL)
        #expect(second.history.records.count == 3)
        #expect(world.logLines.isEmpty)
        try await eventually { thumbnailLanded(first, a.id) && thumbnailLanded(first, b.id) && thumbnailLanded(second, c.id) }
    }

    /// T2, phase-2:30 (:47) and phase-3:49 (:90), full; phase-4a:120 (:215), in part: the capture's own clipboard
    /// copy and owner, which the editor's upload then replaces. With Also copy image on, the image is on the
    /// clipboard while the upload is held, then the link replaces it. What stays of phase-4a:120 is the editor
    /// closing at once (`EDPLACE`).
    @Test func withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink() async throws {
        defer { world.removeAll() }
        defer { destination.releaseUploads() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        world.settings.alsoCopyImageWhenUploading = true
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.display, CaptureIntent(action: .upload)))
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

        let file = folder.appending(path: "Shot.png")
        #expect(coordinator.history.record(id: record.id)?.uploadState == .uploading(fraction: 0))
        #expect(world.clipboard.copies == [.pngAndTIFF])
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: 1))
        #expect(destination.state.withLock { $0.uploads }.isEmpty)
        #expect(record.fileURL == file)
        #expect(record.fileIsTemporary == false)
        #expect(world.shutterCount == 1)
        #expect(world.notifier.calls.isEmpty)
        #expect(world.factory.askedConfigs.count == 1)

        destination.releaseUploads()
        try await eventually { isUploaded(coordinator, record.id) }
        let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
        #expect(world.clipboard.copies == [.pngAndTIFF, .url(link)])
        #expect(link.absoluteString.hasPrefix("https://snap.tky.io/"))
        #expect(coordinator.history.record(id: record.id)?.uploadedKey?.hasSuffix(".png") == true)
        #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        #expect(uploads.first?.data == (try Data(contentsOf: file)))
        #expect(uploads.first?.contentType == "image/png")
        #expect(coordinator.history.record(id: record.id)?.byteCount == uploads.first?.data.count)
        let decoded = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
        #expect(decoded.image.width == 40)
        #expect(decoded.image.height == 30)
        #expect(decoded.scale == 2)
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T3, phase-7c:179 (:233), in part. A 400 x 300 px window capture at scale 2 with Add background on and the
    /// Ocean gradient (padding 48 pt, so 96 px a side) is 592 x 492 px in the file, on the clipboard, in the
    /// upload and in the record, with the window in the middle and the gradient at the corner, and logs nothing.
    /// What stays is the card's thumbnail drawn on screen (`SCREENS`); `sips` is this test's decode.
    @Test func aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        world.settings.windowBackground = true
        world.settings.backgroundStyle = BackgroundStyle(fill: .gradient(1), padding: 48)
        world.settings.alsoCopyImageWhenUploading = true
        #expect(BackgroundPresets.gradients[1].name == "Ocean")
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                             CaptureSamples.window, CaptureIntent(action: .upload)))
        try await eventually { isUploaded(coordinator, record.id) }

        let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
        let file = folder.appending(path: "Shot.png")
        #expect(record.fileURL == file)
        let saved = try Data(contentsOf: file)
        let uploads = destination.state.withLock { $0.uploads }
        try #require(uploads.count == 1)
        let copied = try #require(world.clipboard.pngs.first)
        for png in [saved, copied, uploads[0].data] {
            let decoded = try EditorPixels.decoded(png)
            #expect(decoded.image.width == 592)
            #expect(decoded.image.height == 492)
            #expect(decoded.scale == 2)
        }
        #expect(record.pixelWidth == 592)
        #expect(record.pixelHeight == 492)
        let red = try EditorPixels.worldRed()
        #expect(try EditorPixels.pixel(saved, x: 296, y: 246) == red)
        let corner = try EditorPixels.pixel(saved, x: 1, y: 1)
        #expect(corner != red)
        #expect(corner[3] == 255)
        #expect(coordinator.history.record(id: record.id)?.byteCount == uploads[0].data.count)
        #expect(try fileSize(file) == uploads[0].data.count)
        #expect(world.logLines.isEmpty)
        #expect(world.clipboard.copies == [.pngAndTIFF, .url(link)])
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T4, phase-6b:117 (:143), full. `action=copy` puts the image on the clipboard and nothing else: no file in the
    /// save folder or `pending`, no card, no record, no upload; the shutter follows Play sound; `Image copied`
    /// names the pixel size and `From <sender>`, and with Show notification off nothing posts. The newest card's
    /// capture and clipboard owner stay, so its Annotate still opens its own capture. The shutter heard stays by
    /// hand for good.
    @Test(arguments: [true, false])
    func copyOnlyPutsTheImageOnTheClipboardAndNothingElse(showNotification: Bool) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.showNotification = showNotification
        let coordinator = world.makeCoordinator()
        let previous = UUID()
        coordinator.latestCapture = (id: previous, image: try CaptureSamples.image(width: 4, height: 2))
        let owner = EditorClipboard.Owner(recordID: previous, changeCount: 0)
        coordinator.clipboardOwner = owner

        let record = await save(coordinator, try CaptureSamples.image(width: 400, height: 300), CaptureSamples.area(),
                                CaptureIntent(action: .save, copyOnly: true, sender: "Shortcuts"))

        #expect(record == nil)
        #expect(world.clipboard.copies == [.pngAndTIFF])
        let decoded = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
        #expect(decoded.image.width == 400)
        #expect(decoded.image.height == 300)
        #expect(world.shutterCount == 1)
        if showNotification {
            #expect(world.notifier.calls == [.notice(title: "Image copied", body: "400 × 300 px", subtitle: "From Shortcuts")])
        } else {
            #expect(world.notifier.calls.isEmpty)
        }
        #expect(coordinator.history.records.isEmpty)
        #expect(CaptureSamples.fileNames(in: folder).isEmpty)
        #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory).isEmpty)
        #expect(world.cards.calls.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(coordinator.latestCapture?.id == previous)
        #expect(coordinator.clipboardOwner == owner)
        #expect(world.logLines.isEmpty)
    }

    /// T5. coordinator-split:36 (:36), in part; phase-2:32 (:51), phase-6b:116 (:142, the second argument) and
    /// small-tweaks:13 (:16), full. An area capture under `Save and copy image`, and `action=save` under
    /// `Upload only`, saves `Shot.png` in the folder, copies the same PNG, asks for no destination, posts
    /// `Screenshot saved`, enables Reveal Last Capture (`lastCaptureURL`), keeps the area for a pin, and records
    /// the file's own size with no upload state. What stays of coordinator-split:36: the ⌃⇧4 drag and the area's
    /// width times the display scale (`CAPSRC`), the card with its thumbnail and `Saved` (`SCREENS`), `Reveal Last
    /// Capture` selecting the file in Finder (`WORKSPACE`), and the audible shutter (by hand for good).
    /// small-tweaks:13's row text is `RecentCaptureFormattingTests`'; Finder's figure on screen stays by hand.
    @Test(arguments: [CaptureIntent(action: .save), CaptureIntent(urlAction: .save, setting: .uploadOnly)])
    func aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination(intent: CaptureIntent) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        let coordinator = world.makeCoordinator()
        let rect = CGRect(x: 100, y: 80, width: 200, height: 150)

        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.area(rect), intent))

        let file = folder.appending(path: "Shot.png")
        #expect(CaptureSamples.fileNames(in: folder) == ["Shot.png"])
        #expect(record.fileURL == file)
        #expect(record.fileIsTemporary == false)
        let saved = try Data(contentsOf: file)
        let decoded = try EditorPixels.decoded(saved)
        #expect(decoded.image.width == 40)
        #expect(decoded.image.height == 30)
        #expect(decoded.scale == 2)
        #expect(world.clipboard.copies == [.pngAndTIFF])
        #expect(world.clipboard.pngs == [saved])
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(record.uploadState == .none)
        #expect(world.shutterCount == 1)
        #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")])
        #expect(coordinator.lastCaptureURL == record.fileURL)
        #expect(coordinator.latestCaptureArea?.id == record.id)
        #expect(coordinator.latestCaptureArea?.rect == rect)
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: 1))
        #expect(try fileSize(file) == record.byteCount)
        #expect(record.byteCount == saved.count)
        #expect(coordinator.history.records.map(\.id) == [record.id])
        #expect(coordinator.latestCapture?.id == nil)
        #expect(world.logLines.isEmpty)
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T6, phase-1:45 (:48), full. A folder stored between two captures (where Settings > General's Choose… lands,
    /// `SaveLocation.store`) takes the next capture; the first stays in the old folder. The Choose… panel itself
    /// stays by hand (`SaveLocationStoreTests` pins the store).
    @Test func theNextCaptureLandsInTheNewlyStoredFolder() async throws {
        defer { world.removeAll() }
        let a = try world.storeSaveFolder()
        let b = world.root.appending(path: "B", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        world.settings.fileNameTemplate = "Shot"
        let coordinator = world.makeCoordinator()
        let intent = CaptureIntent(action: .save)

        let first = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                            CaptureSamples.display, intent))
        try world.saveLocation.store(b)
        let second = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.display, intent))

        #expect(first.fileURL == a.appending(path: "Shot.png"))
        #expect(second.fileURL == b.appending(path: "Shot.png"))
        #expect(CaptureSamples.fileNames(in: a) == ["Shot.png"])
        #expect(CaptureSamples.fileNames(in: b) == ["Shot.png"])
        #expect(world.saveLocation.currentURL?.standardizedFileURL == b.standardizedFileURL)
        try await eventually { thumbnailLanded(coordinator, first.id) && thumbnailLanded(coordinator, second.id) }
    }

    /// T7, phase-2:25 (:40), in part. `Upload and copy URL` with Also copy image off leaves the clipboard empty and
    /// posts nothing while the upload is held, then puts the link there alone; the file is saved too. What stays:
    /// the link pasted into Slack opening a working page (the real bucket, by hand for good) and the overlay's
    /// checkmark (`SCREENS`); the URL's shape is `S3DestinationConfigTests`' and `ObjectKeyNamerTests`'.
    @Test func uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink() async throws {
        defer { world.removeAll() }
        defer { destination.releaseUploads() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.display, CaptureIntent(action: .upload)))
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

        #expect(world.clipboard.copies.isEmpty)
        #expect(coordinator.clipboardOwner == nil)
        #expect(world.notifier.calls.isEmpty)

        destination.releaseUploads()
        try await eventually { isUploaded(coordinator, record.id) }
        let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
        let file = folder.appending(path: "Shot.png")
        #expect(world.clipboard.copies == [.url(link)])
        #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
        #expect(record.fileURL == file)
        #expect(exists(file))
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T8. coordinator-split:42 (:42), in part (`.uploadOnly`); phase-2:33 (:52), in part (`.upload`); phase-3:48
    /// (:89), full (`.uploadOnly`, with T21 for the retry); phase-4a:119 (:210), in part (`.upload`: the capture's
    /// own clipboard copy and owner). With no credentials two captures ask for no destination, copy the image each
    /// time and post one `Upload not configured` in all. `Upload and copy URL` saves both files with no upload
    /// state; `Upload only` keeps both in `pending` as failed. What stays: the cards saying `Upload failed`
    /// (`SCREENS`) and the menu's `Retry Failed Uploads` (`STATUSMENU`) for coordinator-split:42, whose Retry half
    /// is `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem`; Settings >
    /// Upload's empty fields and no keychain error (`UPLOADFORM`) for phase-2:33; the editor staying open
    /// (`EDPLACE`) for phase-4a:119.
    @Test(arguments: [AfterCaptureAction.upload, .uploadOnly])
    func withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice(action: AfterCaptureAction) async throws {
        defer { world.removeAll() }
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        let coordinator = world.makeCoordinator()
        let intent = CaptureIntent(action: action)

        let first = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                            CaptureSamples.display, intent))
        let second = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.display, intent))

        #expect(world.factory.askedConfigs.isEmpty)
        #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: second.id, changeCount: 2))
        #expect(world.notifier.errors.filter { $0.title == "Upload not configured" }.count == 1)
        #expect(world.shutterCount == 2)
        #expect(world.logLines.isEmpty)
        switch action {
        case .upload:
            #expect(first.uploadState == .none)
            #expect(second.uploadState == .none)
            #expect(CaptureSamples.fileNames(in: folder) == ["Shot 2.png", "Shot.png"])
            #expect(world.notifier.calls == [
                .error(title: "Upload not configured",
                       message: "Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard."),
                .saved(title: "Screenshot saved", file: "Shot.png"),
                .saved(title: "Screenshot saved", file: "Shot 2.png")])
            #expect(coordinator.history.failedRecords.isEmpty)
        case .uploadOnly:
            for record in [first, second] {
                #expect(record.uploadState == .failed(message: "No upload destination is configured."))
                #expect(record.fileIsTemporary)
                #expect(record.fileURL == coordinator.pendingFiles.directory.appending(path: "\(record.id.uuidString).png"))
                #expect(exists(record.fileURL))
                #expect(world.cards.updates(for: record.id).isEmpty)
            }
            #expect(CaptureSamples.fileNames(in: folder).isEmpty)
            #expect(world.notifier.calls == [
                .error(title: "Upload not configured",
                       message: "Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard.")])
            #expect(coordinator.history.failedRecords.count == 2)
        case .save:
            Issue.record("T8 drives the two upload actions only")
        }
        try await eventually { thumbnailLanded(coordinator, first.id) && thumbnailLanded(coordinator, second.id) }
    }

    /// T9's two failures: a refused upload (403, not retried) and an offline one (no HTTP response, three attempts),
    /// the stand-in for Wi-Fi off.
    nonisolated enum UploadFailureCause: Sendable {
        case denied
        case offline

        var error: UploadError {
            switch self {
            case .denied: .httpStatus(403, body: "AccessDenied: Access Denied")
            case .offline: .noHTTPResponse
            }
        }

        var attempts: Int {
            switch self {
            case .denied: 1
            case .offline: 3
            }
        }

        var message: String {
            switch self {
            case .denied: "Server returned HTTP 403: AccessDenied: Access Denied"
            case .offline: "No HTTP response."
            }
        }
    }

    /// T9, phase-2:48 (:77), in part. An upload that fails keeps the saved file, fails the record with the error's
    /// text, tells the card and posts `Upload failed`, and leaves nothing on the clipboard unless Also copy image is
    /// on. What stays: the card drawn with Retry (`SCREENS`; the `.failed` update is pinned) and Wi-Fi off for real
    /// (by hand for good; the offline cause stands in). The row's `Upload failed` is
    /// `RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState`'.
    @Test(arguments: [(UploadFailureCause.denied, false), (.denied, true), (.offline, false)])
    func aFailingUploadKeepsTheFileAndFailsTheRecord(cause: UploadFailureCause, alsoCopy: Bool) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        world.settings.alsoCopyImageWhenUploading = alsoCopy
        destination.state.withLock {
            $0.failuresRemaining = cause.attempts
            $0.failure = cause.error
        }
        let coordinator = world.makeCoordinator()

        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.display, CaptureIntent(action: .upload)))
        try await eventually { coordinator.history.record(id: record.id)?.isFailed == true }

        let file = folder.appending(path: "Shot.png")
        let stored = try #require(coordinator.history.record(id: record.id))
        #expect(stored.uploadState == .failed(message: cause.message))
        #expect(destination.state.withLock { $0.uploadAttempts } == cause.attempts)
        #expect(world.notifier.calls == [.error(title: "Upload failed", message: cause.message)])
        #expect(world.cards.updates(for: record.id).last == .failed(message: cause.message))
        #expect(exists(file))
        #expect(record.fileURL == file)
        #expect(stored.fileURL == file)
        #expect(world.clipboard.copies == (alsoCopy ? [.pngAndTIFF] : []))
        #expect(coordinator.history.failedRecords.map(\.id) == [record.id])
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T10. phase-5:179 (:191) and small-tweaks:16 (:22), full with T21 (the failed upload and the retry);
    /// phase-6b:66 (:81), in part. An upload-only capture of any origin writes nothing in the save folder, keeps
    /// `pending/<id>.png` at its PNG's size while the upload is held, then drops the file and takes the uploaded
    /// size, with the link alone on the clipboard. With a card showing, the file moves to the card's drag folder
    /// under the key's name instead of being deleted. What stays of phase-6b:66: the Quick Access stack and Recent
    /// Captures on screen (`SCREENS`), and that All-in-One builds these captures (`CAPSRC`).
    @Test(arguments: [(CaptureSamples.display, false), (CaptureSamples.window, false), (CaptureSamples.area(), false),
                      (CaptureSamples.area(), true)])
    func anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded(origin: CaptureOrigin, cardShows: Bool) async throws {
        defer { world.removeAll() }
        defer { destination.releaseUploads() }
        let folder = try world.storeSaveFolder()
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()

        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30), origin,
                                             CaptureIntent(action: .uploadOnly)))
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

        let pending = coordinator.pendingFiles.directory.appending(path: "\(record.id.uuidString).png")
        #expect(CaptureSamples.fileNames(in: folder).isEmpty)
        #expect(record.fileURL == pending)
        #expect(exists(pending))
        #expect(record.fileIsTemporary)
        #expect(try fileSize(pending) == record.byteCount)
        #expect(coordinator.history.record(id: record.id)?.uploadState == .uploading(fraction: 0))
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.notifier.calls.isEmpty)
        #expect(coordinator.lastCaptureURL == nil)
        #expect(coordinator.latestCaptureArea?.id == origin.areaRect.map { _ in record.id })
        #expect(coordinator.latestCaptureArea?.rect == origin.areaRect)

        if cardShows {
            world.cards.showing.insert(record.id)
        }
        destination.releaseUploads()
        try await eventually { isUploaded(coordinator, record.id) }

        let uploaded = try #require(coordinator.history.record(id: record.id))
        let link = try #require(uploaded.uploadedURL)
        let key = try #require(uploaded.uploadedKey)
        let uploads = destination.state.withLock { $0.uploads }
        try #require(uploads.count == 1)
        #expect(!exists(pending))
        #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory).isEmpty)
        #expect(uploaded.fileURL == nil)
        #expect(!uploaded.fileIsTemporary)
        #expect(uploaded.byteCount == uploads[0].data.count)
        #expect(world.clipboard.copies == [.url(link)])
        #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
        if cardShows {
            let name = try #require(key.split(separator: "/").last.map(String.init))
            let kept = coordinator.dragFiles.folder(for: record.id).appending(path: name)
            #expect(exists(kept))
            let decoded = try EditorPixels.decoded(try Data(contentsOf: kept))
            #expect(decoded.image.width == 40)
            #expect(decoded.image.height == 30)
            #expect(world.cards.dragFiles(for: record.id).last == .some(kept))
        } else {
            #expect(world.cards.dragFiles(for: record.id).isEmpty)
        }
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    // MARK: Window backgrounds, Annotate and the upload actions (T11 to T21)

    /// The PNG at `url`, decoded: its pixels and the scale its DPI gives.
    private func pngAt(_ url: URL?) throws -> (image: CGImage, scale: CGFloat) {
        try EditorPixels.decoded(try Data(contentsOf: try #require(url)))
    }

    /// The Capture tab's background on, with the Ocean gradient at the default 48 pt padding.
    private func turnOceanBackgroundOn() {
        #expect(BackgroundPresets.gradients[1].name == "Ocean")
        world.settings.windowBackground = true
        world.settings.backgroundStyle = BackgroundStyle(fill: .gradient(1), padding: 48)
    }

    /// T11, phase-6b:115 (:141). `action=upload` under each After capture setting: with `Save and copy image` the capture
    /// is saved and uploaded and the clipboard holds the link alone (Also copy image is off); with `Upload only, keep
    /// no local file` nothing lands in the save folder and the pending file is gone once the upload ends. The capture
    /// is a window's, with the background off, so the intent's mapping is shown to hold there too. Stays: the URL
    /// parsing and the `t` command (`CaptureIntentTests.uploadUploadsUnderEverySetting`, the URL command suites).
    @Test(arguments: [AfterCaptureAction.save, .uploadOnly])
    func actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting(setting: AfterCaptureAction) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.window, CaptureIntent(urlAction: .upload, setting: setting)))
        try await eventually { isUploaded(coordinator, record.id) }

        let stored = try #require(coordinator.history.record(id: record.id))
        let link = try #require(stored.uploadedURL)
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        #expect(world.clipboard.copies == [.url(link)])
        #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
        #expect(world.factory.askedConfigs.count == 1)
        if setting == .save {
            let file = folder.appending(path: "Shot.png")
            #expect(record.fileURL == file)
            #expect(stored.fileURL == file)
            #expect(exists(file))
            #expect(CaptureSamples.fileNames(in: folder) == ["Shot.png"])
        } else {
            #expect(record.fileIsTemporary)
            #expect(stored.fileURL == nil)
            #expect(CaptureSamples.fileNames(in: folder) == [])
            #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [])
        }
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T12, phase-5:202 (:218). A stitched capture's size is the whole image's: an 8 by 20,000 px capture (a scrolling
    /// result is an area) keeps both numbers in the record, in `history.json` after a relaunch, and in the file, and
    /// the image is copied once (above 16,384 px there is no TIFF; `FakeClipboard` records both forms as `.pngAndTIFF`). Stays: the row's subtitle, which
    /// `RecentCaptureFormattingTests` already pins.
    @Test func aTallCaptureKeepsItsFullPixelSizeInHistory() async throws {
        defer { world.removeAll() }
        try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 8, height: 20_000),
                                             CaptureSamples.area(), CaptureIntent(action: .save)))
        try await eventually { thumbnailLanded(coordinator, record.id) }

        #expect(record.pixelWidth == 8)
        #expect(record.pixelHeight == 20_000)
        #expect(coordinator.history.record(id: record.id)?.pixelWidth == 8)
        #expect(coordinator.history.record(id: record.id)?.pixelHeight == 20_000)
        let relaunched = world.makeCoordinator()
        relaunched.history.load()
        #expect(relaunched.history.record(id: record.id)?.pixelWidth == 8)
        #expect(relaunched.history.record(id: record.id)?.pixelHeight == 20_000)
        let file = try pngAt(record.fileURL)
        #expect(file.image.width == 8)
        #expect(file.image.height == 20_000)
        #expect(world.clipboard.copies == [.pngAndTIFF])
        #expect(world.logLines.isEmpty)
    }

    /// T13, phase-6b:118 (:144), in part (it extends the CT-2 mark). `action=annotate`: the after-capture action runs (the
    /// file is saved and `Screenshot saved` posts), then the editor opens on the new capture and its card closes as
    /// `.editorOpened`. Stays: the `action=pin` half, a pin opening with the card staying (`PINS`).
    @Test func annotateRunsTheActionThenOpensTheEditorOnTheNewCapture() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.area(), CaptureIntent(action: .save, then: .annotate)))
        let editor = try await openedEditor(record.id)

        #expect(exists(folder.appending(path: "Shot.png")))
        #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")])
        #expect(editor.representedURL == record.fileURL)
        #expect(editor.title == "Shot.png")
        #expect(editor.model.base.width == 40)
        #expect(editor.model.base.height == 30)
        #expect(world.cards.calls.contains(.close(record.id, .editorOpened)))
        #expect(world.editors.built.count == 1)
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T14, phase-7c:182 (:236), in part. With Add background to window captures on, an area and a fullscreen capture are
    /// saved as they are: the file, the record and the clipboard keep the capture's size and scale, and its first
    /// pixel is the capture's own, with no fill. Stays: which origin Previous Area, a scrolling capture and an
    /// All-in-One drag build (`CAPSRC`, and `SCROLL` for the scrolling capture); the rule that an area or a
    /// display origin is plain is pinned here.
    @Test(arguments: [CaptureSamples.display, CaptureSamples.area()])
    func areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn(origin: CaptureOrigin) async throws {
        defer { world.removeAll() }
        try world.storeSaveFolder()
        turnOceanBackgroundOn()
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300), origin,
                                             CaptureIntent(action: .save)))
        try await eventually { thumbnailLanded(coordinator, record.id) }

        let file = try pngAt(record.fileURL)
        #expect(file.image.width == 400)
        #expect(file.image.height == 300)
        #expect(file.scale == 2)
        #expect(EditorPixels.pixel(file.image, x: 1, y: 1) == (try EditorPixels.worldRed()))
        #expect(record.pixelWidth == 400)
        #expect(record.pixelHeight == 300)
        let copied = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
        #expect(copied.image.width == 400)
        #expect(copied.image.height == 300)
        #expect(copied.scale == 2)
        #expect(world.logLines.isEmpty)
    }

    /// The Capture tab's canvases for T15: the window's pixels at scale 2, the style, and the canvas size the
    /// layout gives (`BackgroundLayout.make`: padding times the scale on each side, then the aspect ratio grows the
    /// short side and rounds up; a portrait capture takes the ratio's terms the other way round).
    nonisolated enum Canvas: CaseIterable, Sendable {
        case padding0, padding160, radius0, radius40, shadowOff, square, fourThree, threeTwo, sixteenTen
        case sixteenNine, portrait, auto

        var content: (width: Int, height: Int) { self == .portrait ? (300, 400) : (400, 300) }

        var style: BackgroundStyle {
            let ocean = BackgroundFill.gradient(1)
            return switch self {
            case .padding0: BackgroundStyle(fill: ocean, padding: 0)
            case .padding160: BackgroundStyle(fill: ocean, padding: 160)
            case .radius0: BackgroundStyle(fill: ocean, padding: 48, cornerRadius: 0)
            case .radius40: BackgroundStyle(fill: ocean, padding: 48, cornerRadius: 40)
            case .shadowOff: BackgroundStyle(fill: ocean, padding: 48, shadow: false)
            case .square: BackgroundStyle(fill: ocean, padding: 48, aspect: .square)
            case .fourThree: BackgroundStyle(fill: ocean, padding: 48, aspect: .fourThree)
            case .threeTwo: BackgroundStyle(fill: ocean, padding: 48, aspect: .threeTwo)
            case .sixteenTen: BackgroundStyle(fill: ocean, padding: 48, aspect: .sixteenTen)
            case .sixteenNine, .portrait: BackgroundStyle(fill: ocean, padding: 48, aspect: .sixteenNine)
            case .auto: BackgroundStyle(fill: ocean, padding: 48, aspect: .auto)
            }
        }

        var canvas: (width: Int, height: Int) {
            switch self {
            case .padding0: (400, 300)
            case .padding160: (1040, 940)
            case .radius0, .radius40, .shadowOff, .auto: (592, 492)
            case .square: (592, 592)
            case .fourThree: (656, 492)
            case .threeTwo: (738, 492)
            case .sixteenTen: (788, 492)
            case .sixteenNine: (875, 492)
            case .portrait: (492, 875)
            }
        }
    }

    /// T15, phase-7c:184 (:238) and phase-7c:185 (:239). A window capture with padding 0 and 160, corner radius 0 and 40,
    /// shadow off and each aspect ratio is saved at the size the arithmetic gives, in the file and in the record, at
    /// the capture's scale; a portrait window with 16:9 gets a portrait canvas. Stays: how radius and shadow look
    /// (`BackgroundCompositorTests`) and the arithmetic itself (`BackgroundLayoutTests`,
    /// `.portraitContentInvertsTheRatio`).
    @Test(arguments: Canvas.allCases)
    func aWindowCanvasFollowsTheStyle(canvas: Canvas) async throws {
        defer { world.removeAll() }
        try world.storeSaveFolder()
        world.settings.windowBackground = true
        world.settings.backgroundStyle = canvas.style
        let coordinator = world.makeCoordinator()
        let content = canvas.content
        let record = try #require(await save(coordinator,
                                             try CaptureSamples.image(width: content.width, height: content.height),
                                             CaptureSamples.window, CaptureIntent(action: .save)))
        try await eventually { thumbnailLanded(coordinator, record.id) }

        let expected = CGSize(width: canvas.canvas.width, height: canvas.canvas.height)
        let layout = try #require(BackgroundLayout.make(contentSize: CGSize(width: content.width, height: content.height),
                                                        style: canvas.style, scale: 2))
        #expect(layout.canvasSize == expected)
        let file = try pngAt(record.fileURL)
        #expect(file.image.width == canvas.canvas.width)
        #expect(file.image.height == canvas.canvas.height)
        #expect(file.scale == 2)
        #expect(record.pixelWidth == canvas.canvas.width)
        #expect(record.pixelHeight == canvas.canvas.height)
        #expect(coordinator.history.record(id: record.id)?.pixelWidth == canvas.canvas.width)
        #expect(coordinator.history.record(id: record.id)?.pixelHeight == canvas.canvas.height)
        #expect(world.logLines.isEmpty)
    }

    /// T16, phase-7c:186 (:240) and phase-7c:197 (:254). The setting is read at each save: on, a window capture is
    /// composed (592 by 492); turned off, the next window capture and an area capture are plain (400 by 300, the
    /// capture's own first pixel) at once, with no relaunch between. Stays: the editor's own background switch and an
    /// edit's Save (`EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore`).
    @Test func withTheBackgroundOffEveryCaptureIsPlainAtOnce() async throws {
        defer { world.removeAll() }
        try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        turnOceanBackgroundOn()
        let coordinator = world.makeCoordinator()
        let intent = CaptureIntent(action: .save)
        let composed = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                               CaptureSamples.window, intent))
        world.settings.windowBackground = false
        let plainWindow = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                                  CaptureSamples.window, intent))
        let plainArea = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                                CaptureSamples.area(), intent))
        try await eventually {
            thumbnailLanded(coordinator, composed.id) && thumbnailLanded(coordinator, plainWindow.id)
                && thumbnailLanded(coordinator, plainArea.id)
        }

        #expect(composed.fileURL?.lastPathComponent == "Shot.png")
        #expect(plainWindow.fileURL?.lastPathComponent == "Shot 2.png")
        #expect(plainArea.fileURL?.lastPathComponent == "Shot 3.png")
        let first = try pngAt(composed.fileURL)
        #expect(first.image.width == 592)
        #expect(first.image.height == 492)
        for plain in [plainWindow, plainArea] {
            let file = try pngAt(plain.fileURL)
            #expect(file.image.width == 400)
            #expect(file.image.height == 300)
            #expect(EditorPixels.pixel(file.image, x: 1, y: 1) == (try EditorPixels.worldRed()))
            #expect(plain.pixelWidth == 400)
            #expect(plain.pixelHeight == 300)
        }
        #expect(composed.pixelWidth == 592)
        #expect(composed.pixelHeight == 492)
        #expect(world.logLines.isEmpty)
    }

    /// T17, phase-7c:187 (:241), in part (it extends the CT-2 mark). A window capture with the background on, opened in the
    /// editor with Annotate: the editor's image is the composed one (592 by 492, the capture in the middle and the
    /// fill at the corner) and its document carries no background, which is what the popover's switch reads. Stays:
    /// the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`); the editor half is
    /// `CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground`.
    @Test func aComposedWindowCaptureOpensInTheEditorComposed() async throws {
        defer { world.removeAll() }
        try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        turnOceanBackgroundOn()
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                             CaptureSamples.window, CaptureIntent(action: .save, then: .annotate)))
        let editor = try await openedEditor(record.id)

        let model = editor.model
        #expect(model.base.width == 592)
        #expect(model.base.height == 492)
        #expect(EditorPixels.pixel(model.base, x: 296, y: 246) == (try EditorPixels.worldRed()))
        #expect(EditorPixels.pixel(model.base, x: 1, y: 1) != (try EditorPixels.worldRed()))
        #expect(model.document == AnnotationDocument())
        #expect(model.document.background == nil)
        #expect(!model.hasUnsavedChanges)
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T18, phase-7c:188 (:244). `action=copy` on a window with the background on puts the composed image on the clipboard
    /// and nothing else: no file, no card, no history row and no destination asked for, and `Image copied` names the
    /// composed size. `action=upload` then sends the composed image: the upload, the file and the record are all
    /// 592 by 492. Stays: the URL parsing (already covered) and the window click, which is the user's selection.
    @Test func copyAndUploadOfAWindowCarryTheComposedImage() async throws {
        defer { world.removeAll() }
        turnOceanBackgroundOn()
        let coordinator = world.makeCoordinator()

        let copied = await save(coordinator, try CaptureSamples.image(width: 400, height: 300), CaptureSamples.window,
                                CaptureIntent(action: .save, copyOnly: true))
        #expect(copied == nil)
        let png = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
        #expect(png.image.width == 592)
        #expect(png.image.height == 492)
        #expect(world.clipboard.copies == [.pngAndTIFF])
        #expect(world.notifier.calls == [.notice(title: "Image copied", body: "592 × 492 px", subtitle: nil)])
        #expect(coordinator.history.records.isEmpty)
        #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [])
        #expect(world.cards.calls.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)

        let folder = try world.storeSaveFolder()
        #expect(CaptureSamples.fileNames(in: folder) == [])
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                             CaptureSamples.window, CaptureIntent(urlAction: .upload, setting: .save)))
        try await eventually { isUploaded(coordinator, record.id) }
        let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.count == 1)
        let sent = try EditorPixels.decoded(try #require(uploads.first?.data))
        #expect(sent.image.width == 592)
        #expect(sent.image.height == 492)
        #expect(sent.scale == 2)
        let file = try pngAt(record.fileURL)
        #expect(file.image.width == 592)
        #expect(file.image.height == 492)
        #expect(record.pixelWidth == 592)
        #expect(record.pixelHeight == 492)
        #expect(world.clipboard.copies.last == .url(link))
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }

    /// T19, phase-7c:189 (:245), in part. A window too large for a background (16,385 px, one over the limit) is saved
    /// as it is: one `Background: the window is too large for a background, keeping the window capture` line, the
    /// `Screenshot saved` notice and no error, the file and the record at the capture's own size. Stays: `no bitmap
    /// could be made`, which no input forces while the layout fits, so it is checked by code reading as the line says.
    @Test func aWindowTooLargeForABackgroundIsSavedPlainWithOneLine() async throws {
        defer { world.removeAll() }
        try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        turnOceanBackgroundOn()
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 16_385, height: 2, scale: 1),
                                             CaptureSamples.window, CaptureIntent(action: .save)))
        try await eventually { thumbnailLanded(coordinator, record.id) }

        #expect(world.logLines == ["Background: the window is too large for a background, keeping the window capture"])
        #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")])
        let file = try pngAt(record.fileURL)
        #expect(file.image.width == 16_385)
        #expect(file.image.height == 2)
        #expect(record.pixelWidth == 16_385)
        #expect(record.pixelHeight == 2)
        #expect(world.clipboard.copies == [.pngAndTIFF])
    }

    /// T20, phase-7c:190 (:246). Two window captures started together, the second before the first has finished: both get
    /// the background, each in its own file (`Shot.png` and `Shot 2.png`, in either order), and the files do not mix:
    /// the red 400 by 300 capture is 592 by 492 with red in the middle, the white 200 by 100 capture is 392 by 292
    /// with white in the middle. Stays: the second capture's card not yet showing (`SCREENS`).
    @Test func twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile() async throws {
        defer { world.removeAll() }
        try world.storeSaveFolder()
        world.settings.fileNameTemplate = "Shot"
        turnOceanBackgroundOn()
        let coordinator = world.makeCoordinator()
        let red = try CaptureSamples.image(width: 400, height: 300)
        let white = try CaptureSamples.image(width: 200, height: 100, white: true)
        let intent = CaptureIntent(action: .save)
        let redSave = Task { await save(coordinator, red, CaptureSamples.window, intent) }
        let whiteSave = Task { await save(coordinator, white, CaptureSamples.window, intent) }
        defer {
            redSave.cancel()
            whiteSave.cancel()
        }
        let redWatch = TaskWatch(redSave)
        let whiteWatch = TaskWatch(whiteSave)
        try await eventually { redWatch.hasReturned && whiteWatch.hasReturned }
        let redRecord = try #require(await redSave.value)
        let whiteRecord = try #require(await whiteSave.value)
        try await eventually { thumbnailLanded(coordinator, redRecord.id) && thumbnailLanded(coordinator, whiteRecord.id) }

        #expect(redRecord.id != whiteRecord.id)
        let names = [redRecord, whiteRecord].map { $0.fileURL?.lastPathComponent }
        #expect(Set(names) == ["Shot.png", "Shot 2.png"])
        let redFile = try pngAt(redRecord.fileURL)
        #expect(redFile.image.width == 592)
        #expect(redFile.image.height == 492)
        #expect(EditorPixels.pixel(redFile.image, x: 296, y: 246) == (try EditorPixels.worldRed()))
        let whiteFile = try pngAt(whiteRecord.fileURL)
        #expect(whiteFile.image.width == 392)
        #expect(whiteFile.image.height == 292)
        #expect(EditorPixels.pixel(whiteFile.image, x: 196, y: 146) == [255, 255, 255, 255])
        #expect(redRecord.pixelWidth == 592)
        #expect(redRecord.pixelHeight == 492)
        #expect(whiteRecord.pixelWidth == 392)
        #expect(whiteRecord.pixelHeight == 292)
        #expect(world.notifier.calls.count == 2)
        #expect(world.notifier.calls.allSatisfy { if case .saved = $0 { true } else { false } })
        #expect(world.logLines.isEmpty)
    }

    /// T21, phase-5:179 (:191), its Wi-Fi-off clause (T10 has the rest); phase-3:48 (:89), its Retry leg (T8 has the
    /// rest); small-tweaks:16 (:22), the size kept until the retry (T10 has the first half). An upload-only capture
    /// whose upload fails keeps `pending/<id>.png` at the PNG's size, with nothing in the save folder, nothing on the
    /// clipboard and one `Upload failed` notice; Retry Failed Uploads sends those same bytes, the pending file is
    /// removed, the row takes the uploaded size and the link is copied. Stays: Wi-Fi off for real (a failing
    /// destination stands in); the Retry half of phase-3:48 is also
    /// `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem`.
    @Test func anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let message = "Server returned HTTP 403: AccessDenied: Access Denied"
        destination.state.withLock {
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
        }
        let coordinator = world.makeCoordinator()
        let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                             CaptureSamples.area(), CaptureIntent(action: .uploadOnly)))
        try await eventually { coordinator.history.record(id: record.id)?.isFailed == true }

        let failed = try #require(coordinator.history.record(id: record.id))
        #expect(failed.uploadState == .failed(message: message))
        let pending = try #require(failed.fileURL)
        #expect(failed.fileIsTemporary)
        #expect(exists(pending))
        let kept = try Data(contentsOf: pending)
        #expect(failed.byteCount == kept.count)
        #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [pending.lastPathComponent])
        #expect(CaptureSamples.fileNames(in: folder) == [])
        #expect(world.notifier.calls == [.error(title: "Upload failed", message: message)])
        #expect(world.clipboard.copies.isEmpty)
        #expect(coordinator.history.failedRecords.map(\.id) == [record.id])
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)

        coordinator.retryFailedUploads()
        try await eventually { isUploaded(coordinator, record.id) }

        let uploaded = try #require(coordinator.history.record(id: record.id))
        let link = try #require(uploaded.uploadedURL)
        let uploads = destination.state.withLock { $0.uploads }
        #expect(destination.state.withLock { $0.uploadAttempts } == 2)
        #expect(uploads.count == 1)
        #expect(uploads.first?.data == kept)
        #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [])
        #expect(uploaded.fileURL == nil)
        #expect(uploaded.byteCount == uploads.first?.data.count)
        #expect(world.clipboard.copies == [.url(link)])
        #expect(world.notifier.calls.last == .uploaded(url: link, copied: true))
        try await eventually { thumbnailLanded(coordinator, record.id) }
    }
}
