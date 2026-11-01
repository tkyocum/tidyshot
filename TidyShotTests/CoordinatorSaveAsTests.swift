import Foundation
import Testing
@testable import TidyShot

/// A card's Save As… on a built coordinator (`saveAs(recordID:)` and `saveVideoCopy(recordID:)`): what the panel is
/// asked, what is written where, and what is posted. The panel is `environment.chooseSaveAsURL`, here
/// `world.saveAsChooser`; no panel is built and the app is never activated. `saveAs` runs its work in a task it does
/// not return (`afterMenuTracking`), so a test gates on what it asks, writes or posts (`eventually`); a recording's
/// `saveVideoCopy` runs in the test's own task, watched with `TaskWatch` and cancelled in a `defer`. A held panel is
/// answered Cancel in a `defer` declared right after the world's, which is what ends it if the test throws.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorSaveAsTests {
    let world: CoordinatorWorld
    let key = "s/SHOT.png"
    let videoKey = "s/2026/rec.mp4"

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }
    var chooser: FakeSaveAsChooser { world.saveAsChooser }

    /// The public URL of a key (`FakeDestination.publicURL(for:)`).
    func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    /// `<root>/Desktop/<name>`, its folder made: the URL a save panel would return.
    func desktop(_ name: String) throws -> URL {
        let folder = world.root.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: name)
    }

    /// The notifier's calls after the first `count`.
    func notices(after count: Int) -> [FakeNotifier.Call] {
        Array(world.notifier.calls.dropFirst(count))
    }

    /// Whether any notice so far said `Downloading <key>`.
    var postedDownloading: Bool {
        world.notifier.calls.contains {
            if case .notice(_, let body, _) = $0 { return body.hasPrefix("Downloading ") } else { return false }
        }
    }

    /// A PNG of `width` by 2 pixels named `name` in `folder`, never uploaded, added to history.
    func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png",
                       width: Int = 4) throws -> (record: CaptureRecord, original: Data) {
        let original = try CoordinatorWorld.pngData(width: width, height: 2)
        let file = folder.appending(path: name)
        try original.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: width, pixelHeight: 2, appName: nil,
                                   byteCount: original.count)
        coordinator.history.add(record)
        return (record, original)
    }

    /// A PNG of `width` by 2 pixels in `pending/` whose upload failed (`Retry  Save As…`), added to history.
    func addPendingImage(to coordinator: AppCoordinator, width: Int = 4) throws -> CaptureRecord {
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: width, height: 2)
        let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: width, pixelHeight: 2,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                   byteCount: png.count)
        coordinator.history.add(record)
        return record
    }

    /// An uploaded upload-only image under `key` with no local file and no drag copy, at the world's
    /// location; its download gives `bytes`.
    func addUploadOnly(to coordinator: AppCoordinator, bytes: Data) -> CaptureRecord {
        destination.state.withLock { $0.downloadedData = bytes }
        let record = CaptureRecord(fileURL: nil, pixelWidth: 6, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: publicURL(key), key: key), objectLocation: world.location)
        coordinator.history.add(record)
        return record
    }

    /// An upload-only capture uploaded while its card shows: the pending file has moved to `Drag/<id>/` and the
    /// record has no `fileURL` (`keepForDragOut`). The record as it is now, its key and its bytes.
    func uploadWithItsCardShowing(_ coordinator: AppCoordinator) async throws
        -> (record: CaptureRecord, key: String, png: Data) {
        let record = try addPendingImage(to: coordinator)
        let id = record.id
        let png = try Data(contentsOf: try #require(record.fileURL))
        world.cards.showing.insert(id)
        coordinator.retryUpload(recordID: id)
        try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
        let current = try #require(coordinator.history.record(id: id))
        #expect(current.fileURL == nil)
        #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
        return (current, try #require(current.uploadedKey), png)
    }

    /// An uploaded recording of `kind` under `videoKey` with no local file, at the world's location (the record
    /// `CoordinatorDragOutTests.showingUploadedRecording` builds).
    func addUploadedRecording(to coordinator: AppCoordinator, kind: MediaKind = .video) -> CaptureRecord {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                   uploadState: .uploaded(url: publicURL(videoKey), key: videoKey),
                                   objectLocation: world.location, mediaKind: kind, durationSeconds: 10,
                                   byteCount: 1_000)
        coordinator.history.add(record)
        return record
    }

    /// phase-6a:170 (:189), in part; phase-6a:174 (:193), full; coordinator-split:44 (:48), in part, the pin menu's
    /// `Save As…` item (the suggestion and Cancel); recording-r1:340 (:397) and recording-r2:670 (:750), full, the
    /// Save As… verb (the other verbs are the existing tests tests-small.md SAVEAS.4 names).
    /// Save As… on a capture in the save folder suggests its own name, PNG, in the save folder; Cancel writes, posts
    /// and logs nothing. Saved elsewhere, the copy is the original's bytes (no re-encode) and `Saved` names it;
    /// saved over the original, the original is unchanged; with notifications off the file is still written and
    /// nothing is posted. The card, the record and its link, Recent Captures, `history.json`, Reveal Last Capture
    /// and the clipboard are as they were. `saveAs(recordID:)` is what the pin's menu item calls too.
    /// Stays: phase-6a:170, `shasum`, the click on `Saved` revealing the copy (the notifier's) and the panel's
    /// Replace prompt (AppKit's), by hand with no seam. coordinator-split:44, the pin over the spot, its second
    /// click, `Close Pinned Screenshots` and reaching the item through the pin's menu (`PINS`, `SCREENS`), and the
    /// panel itself.
    @Test func saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        let file = try #require(record.fileURL)
        world.cards.showing.insert(id)
        coordinator.lastCaptureURL = file
        let records = coordinator.history.records
        let historyFile = try Data(contentsOf: world.historyFileURL)
        let cardCalls = world.cards.calls
        let copy = try desktop("Copy.png")
        let quiet = try desktop("Quiet.png")
        chooser.answers = [nil, copy, file, quiet]

        coordinator.saveAs(recordID: id)
        try await eventually { chooser.asked.count == 1 }
        let suggestion = try #require(chooser.asked.first)
        #expect(suggestion.fileName == "Shot.png")
        #expect(suggestion.directory == world.saveLocation.currentURL)
        #expect(suggestion.mediaKind == .image)
        #expect(world.notifier.calls.isEmpty)
        #expect(world.logLines.isEmpty)

        coordinator.saveAs(recordID: id)
        try await eventually { world.notifier.calls == [.saved(title: "Saved", file: "Copy.png")] }
        #expect(try Data(contentsOf: copy) == original)

        coordinator.saveAs(recordID: id)
        try await eventually { world.notifier.calls.count == 2 }
        #expect(world.notifier.calls.last == .saved(title: "Saved", file: "Shot.png"))
        #expect(try Data(contentsOf: file) == original)

        // Last, so no earlier save is still to read the setting.
        world.settings.showNotification = false
        coordinator.saveAs(recordID: id)
        try await eventually { exists(quiet) }
        #expect(try Data(contentsOf: quiet) == original)

        #expect(chooser.asked == Array(repeating: suggestion, count: 4))
        #expect(world.notifier.calls.count == 2)
        #expect(coordinator.history.records == records)
        #expect(try Data(contentsOf: world.historyFileURL) == historyFile)
        #expect(world.cards.calls == cardCalls)
        #expect(world.cards.showing == [id])
        #expect(coordinator.lastCaptureURL == file)
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.logLines.isEmpty)
    }

    /// phase-6a:171 (:190), in part. An upload-only capture's suggestion is the file name template's name with the
    /// counter as it stands, none drawn, and no folder when none is set (the panel opens where it last was). After a
    /// failed upload (`Retry  Save As…`) the copy is the pending file, `pending/<id>.png`; while its retry's upload
    /// is held (`Uploading…`) the copy is the pending file too, nothing is downloaded, and the upload goes on.
    /// Stays: where the panel last was (the panel's own, AppKit's), by hand with no seam. The suggestion with a save
    /// folder is `EditorNamingTests.uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName` and
    /// `.counterUsesTheCurrentValue`.
    @Test func anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile() async throws {
        defer { world.removeAll() }
        defer { destination.releaseUploads() }
        world.settings.fileNameTemplate = "shot-{counter}"
        _ = world.settings.nextCounter()
        _ = world.settings.nextCounter()
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let id = record.id
        let png = try Data(contentsOf: try #require(record.fileURL))
        let failed = try desktop("Failed.png")
        let uploading = try desktop("Uploading.png")
        chooser.answers = [failed, uploading]

        coordinator.saveAs(recordID: id)
        try await eventually { world.notifier.calls == [.saved(title: "Saved", file: "Failed.png")] }
        #expect(chooser.asked == [EditorNaming.SaveAsSuggestion(fileName: "shot-2.png", directory: nil,
                                                                 mediaKind: .image)])
        #expect(world.settings.currentCounter == 2)
        #expect(try Data(contentsOf: failed) == png)

        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        coordinator.retryUpload(recordID: id)
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        #expect(coordinator.history.record(id: id)?.isUploading == true)
        coordinator.saveAs(recordID: id)
        try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Uploading.png")) }
        let counter = world.settings.currentCounter
        #expect(chooser.asked.last == EditorNaming.SaveAsSuggestion(fileName: "shot-\(counter).png", directory: nil,
                                                                     mediaKind: .image))
        #expect(try Data(contentsOf: uploading) == png)
        #expect(coordinator.history.record(id: id)?.isUploading == true)
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)

        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
    }

    /// phase-6a:172 (:191), in part; phase-6a:198 (:220), in part, the Save As… part of "need no download".
    /// After an upload-only capture's upload on a card that showed through it, Save As… writes the card's kept drag
    /// copy, with no GET and no `Downloading` notice. On an upload-only card with no drag copy (a restored card
    /// before its quiet download has landed) the panel comes first and nothing is posted or fetched while it is up;
    /// after Save `Saving a copy…` with `Downloading <key>` is posted, the object is written and `Saved` follows.
    /// Offline, the failure is posted as `Not saved`, nothing is written and nothing is logged.
    /// Stays: phase-6a:172, the restore itself (`SCREENS`: `restoreClosedOverlay` reads `overlayScreen`), `curl`
    /// against the bucket and the slow profile, by hand. phase-6a:198, Slack reading the file in that minute, by hand
    /// with no seam; its Copy Image, Annotate and 60 s clean-up are CT-2's tests.
    @Test func anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel() async throws {
        defer { world.removeAll() }
        defer { chooser.answer(nil) }
        let coordinator = world.makeCoordinator()
        let (kept, _, png) = try await uploadWithItsCardShowing(coordinator)
        let fromDrag = try desktop("Kept.png")
        chooser.answers = [fromDrag]

        coordinator.saveAs(recordID: kept.id)
        try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Kept.png")) }
        #expect(try Data(contentsOf: fromDrag) == png)
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        #expect(!postedDownloading)

        let object = try CoordinatorWorld.pngData(width: 6, height: 2)
        // A fixed template: the default one's {time} could tick between the coordinator's read and ours.
        world.settings.fileNameTemplate = "shot-{counter}"
        let restored = addUploadOnly(to: coordinator, bytes: object)
        world.cards.showing.insert(restored.id)
        let downloaded = try desktop("Restored.png")
        chooser.holds = true
        let beforePanel = world.notifier.calls.count

        coordinator.saveAs(recordID: restored.id)
        try await eventually { chooser.isWaiting }
        #expect(chooser.asked.last == EditorNaming.SaveAsSuggestion(
            fileName: "shot-\(world.settings.currentCounter).png", directory: nil, mediaKind: .image))
        #expect(notices(after: beforePanel).isEmpty)
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        chooser.answer(downloaded)
        try await eventually { notices(after: beforePanel).count == 2 }
        #expect(notices(after: beforePanel) == [.notice(title: "Saving a copy…", body: "Downloading \(key)"),
                                               .saved(title: "Saved", file: "Restored.png")])
        #expect(try Data(contentsOf: downloaded) == object)
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])

        let offline = URLError(.notConnectedToInternet)
        destination.state.withLock { $0.dataDownloadFailures = [offline] }
        let notSaved = try desktop("Offline.png")
        chooser.answers = [notSaved]
        let beforeOffline = world.notifier.calls.count
        coordinator.saveAs(recordID: restored.id)
        try await eventually { notices(after: beforeOffline).count == 2 }
        #expect(notices(after: beforeOffline) == [.notice(title: "Saving a copy…", body: "Downloading \(key)"),
                                                 .error(title: "Not saved", message: offline.localizedDescription)])
        #expect(!exists(notSaved))
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [key, key])
        #expect(chooser.asked.count == 3)
        #expect(world.logLines.isEmpty)
    }

    /// recording-r4:277 (:294), full. Save As… on an uploaded recording while its drag-out download runs: after the
    /// panel it waits for the download, then copies the landed file to the chosen place. One GET in all, the drag-out
    /// download's, no `download(key:to:)` and no `download(key:)`; `Saved` names the copy and nothing says
    /// `Downloading`. The suggestion is an MP4's.
    /// Stays: nothing the line checks; "one GET in the log" is the fake's `downloads` count here.
    @Test func aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile() async throws {
        defer { world.removeAll() }
        defer { destination.releaseDownloads() }
        let coordinator = world.makeCoordinator()
        let record = addUploadedRecording(to: coordinator)
        let id = record.id
        world.cards.showing.insert(id)
        destination.state.withLock {
            $0.holdsDownloads = true
            $0.downloadOutcome = .lands(bytes: 1_000)
        }
        coordinator.downloadDragFile(recordID: id)
        try await eventually { destination.state.withLock { $0.downloads.count } == 1 }
        let target = try desktop("Copy.mp4")
        chooser.answers = [target]

        let save = Task { await coordinator.saveVideoCopy(recordID: id) }
        defer { save.cancel() }
        let watch = TaskWatch(save)
        try await eventually { chooser.asked.count == 1 }
        let suggestion = try #require(chooser.asked.first)
        #expect(suggestion.mediaKind == .video)
        #expect(suggestion.fileName.hasSuffix(".mp4"))
        #expect(!watch.hasReturned)
        #expect(!exists(target))

        destination.releaseDownloads()
        try await eventually { watch.hasReturned }
        let landed = try #require(coordinator.dragFiles.stagedFile(id: id))
        #expect(try Data(contentsOf: target) == Data(contentsOf: landed))
        #expect(try Data(contentsOf: target) == Data(count: 1_000))
        #expect(destination.state.withLock { $0.downloads.count } == 1)
        #expect(destination.state.withLock { $0.fileDownloads.isEmpty })
        #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
        #expect(world.notifier.calls == [.saved(title: "Saved", file: "Copy.mp4")])
    }

    /// phase-6a:175 (:194), in part. The panel held open while the card's auto-close runs out and the drag folder's
    /// minute passes: the card closes as `.autoClose` (restorable), its drag copy goes, the panel is still up, and
    /// when it is answered the capture is saved: an upload-only capture whose drag copy is gone by then, so it is
    /// downloaded (`Saving a copy…`, `Downloading <key>`) and `Saved` follows. One panel in all.
    /// Stays: the card's own timer (`QuickAccessController.scheduleClose`, which `FakeCards.close` stands for) and
    /// the panel window staying usable as the card goes (AppKit's), by hand with no seam.
    @Test func aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves() async throws {
        defer { world.removeAll() }
        defer { chooser.answer(nil) }
        let coordinator = world.makeCoordinator()
        let (record, k, _) = try await uploadWithItsCardShowing(coordinator)
        let id = record.id
        let object = Data("object".utf8)
        destination.state.withLock { $0.downloadedData = object }
        let target = try desktop("Copy.png")
        chooser.holds = true

        coordinator.saveAs(recordID: id)
        try await eventually { chooser.isWaiting }
        world.cards.close(recordID: id, reason: .autoClose)
        #expect(world.cards.closes == [.autoClose])
        #expect(coordinator.closedOverlays.ids.contains(id))
        try await world.clock.run(for: .seconds(60))
        try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
        #expect(chooser.isWaiting)
        let beforeAnswer = world.notifier.calls.count

        chooser.answer(target)
        try await eventually { notices(after: beforeAnswer).count == 2 }
        #expect(notices(after: beforeAnswer) == [.notice(title: "Saving a copy…", body: "Downloading \(k)"),
                                                .saved(title: "Saved", file: "Copy.png")])
        #expect(try Data(contentsOf: target) == object)
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [k])
        #expect(chooser.asked.count == 1)
    }

    /// phase-6a:176 (:195), in part. Save As… from a card in the middle of the stack, and from the oldest (a showing
    /// card stands for a restored one: Save As does not look at the card), writes that card's capture and asks with
    /// that card's suggestion.
    /// Stays: the restore itself (`SCREENS`); the button and the context menu both calling `onSaveAs`
    /// (QuickAccessView.swift:101, :138), by eye.
    @Test func saveAsFromAnyCardWritesThatCardsCapture() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let oldest = try addSavedImage(to: coordinator, in: folder, name: "Oldest.png", width: 4)
        let middle = try addSavedImage(to: coordinator, in: folder, name: "Middle.png", width: 5)
        let newest = try addSavedImage(to: coordinator, in: folder, name: "Newest.png", width: 6)
        world.cards.showing = [oldest.record.id, middle.record.id, newest.record.id]
        let fromMiddle = try desktop("FromMiddle.png")
        let fromOldest = try desktop("FromOldest.png")
        chooser.answers = [fromMiddle, fromOldest]

        coordinator.saveAs(recordID: middle.record.id)
        try await eventually { world.notifier.calls.count == 1 }
        coordinator.saveAs(recordID: oldest.record.id)
        try await eventually { world.notifier.calls.count == 2 }

        #expect(chooser.asked.map(\.fileName) == ["Middle.png", "Oldest.png"])
        #expect(try Data(contentsOf: fromMiddle) == middle.original)
        #expect(try Data(contentsOf: fromOldest) == oldest.original)
        #expect(world.notifier.calls == [.saved(title: "Saved", file: "FromMiddle.png"),
                                         .saved(title: "Saved", file: "FromOldest.png")])
    }

    /// recording-r1:313 (:353), in part, its last sentence. Save As… on an uploaded upload-only video whose drag folder
    /// is gone downloads the object to the chosen file (`download(key:to:)`) after `Saving a copy…` with
    /// `Downloading <key>`, then posts `Saved`; no drag-out download starts.
    /// Stays: restoring the card starting no download (`SCREENS`), and Activity Monitor, by hand; a drag downloading
    /// first is `CoordinatorDragOutTests`.
    @Test func anUploadOnlyVideosSaveAsDownloadsToTheChosenFile() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = addUploadedRecording(to: coordinator)
        world.cards.showing.insert(record.id)
        let movie = Data(repeating: 7, count: 32)
        destination.state.withLock { $0.downloadedData = movie }
        let target = try desktop("Chosen.mp4")
        chooser.answers = [target]

        let save = Task { await coordinator.saveVideoCopy(recordID: record.id) }
        defer { save.cancel() }
        let watch = TaskWatch(save)
        try await eventually { watch.hasReturned }

        #expect(try Data(contentsOf: target) == movie)
        #expect(destination.state.withLock { $0.fileDownloads.map(\.key) } == [videoKey])
        #expect(destination.state.withLock { $0.fileDownloads.map(\.file) } == [target])
        #expect(destination.state.withLock { $0.downloads }.isEmpty)
        #expect(world.notifier.calls == [.notice(title: "Saving a copy…", body: "Downloading \(videoKey)"),
                                         .saved(title: "Saved", file: "Chosen.mp4")])
    }

    /// recording-r2:264 (:278), in part, the Save As… part. A GIF's Save As… asks for a `.gif` (the panel's one type
    /// follows the suggestion's kind) and copies the local GIF to the chosen file, over an existing one too, and the
    /// source stays as it was.
    /// Stays: the thumbnail click opening the GIF (`WORKSPACE`); `/Volumes/RecOff`, the hover preview and dragging
    /// into Finder and Slack, by hand. The panel's `com.compuserve.gif` is `EditorNamingTests.aGIFPanelAllowsGIFOnly`;
    /// the menu contents are `QuickAccessModelTests.aGIFHasNoImageActionsCopiesItsFileAndHasTheGIFBadge`.
    @Test func aGIFsSaveAsWritesTheGIFOverAnExistingFileToo() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let gif = Data("GIF89a-bytes".utf8)
        let file = folder.appending(path: "Recording.gif")
        try gif.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 640, pixelHeight: 400, appName: nil, mediaKind: .gif,
                                   durationSeconds: 4, byteCount: gif.count)
        coordinator.history.add(record)
        let fresh = try desktop("Fresh.gif")
        let existing = try desktop("Existing.gif")
        try Data("old".utf8).write(to: existing)
        chooser.answers = [fresh, existing]

        for _ in 0..<2 {
            let save = Task { await coordinator.saveVideoCopy(recordID: record.id) }
            defer { save.cancel() }
            let watch = TaskWatch(save)
            try await eventually { watch.hasReturned }
        }

        #expect(chooser.asked.map(\.mediaKind) == [.gif, .gif])
        #expect(chooser.asked.map(\.fileName) == ["Recording.gif", "Recording.gif"])
        #expect(try Data(contentsOf: fresh) == gif)
        #expect(try Data(contentsOf: existing) == gif)
        #expect(try Data(contentsOf: file) == gif)
        #expect(world.notifier.calls == [.saved(title: "Saved", file: "Fresh.gif"),
                                         .saved(title: "Saved", file: "Existing.gif")])
        #expect(destination.state.withLock { $0.fileDownloads }.isEmpty)
    }

    /// No checklist line (catalogue SAVEAS E1): the one branch of `askSaveAsTarget` nothing else reaches, the record
    /// read again after the panel (RA:202-205), which the seam leaves in the coordinator. A capture deleted while its
    /// panel is up is not written, nothing is posted, and the coordinator logs why.
    @Test func aSaveAsWhoseCaptureIsDeletedWhileThePanelIsUpWritesNothingAndLogsIt() async throws {
        defer { world.removeAll() }
        defer { chooser.answer(nil) }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        let gone = try desktop("Gone.png")
        chooser.holds = true

        coordinator.saveAs(recordID: id)
        try await eventually { chooser.isWaiting }
        coordinator.history.remove(id: id)
        chooser.answer(gone)
        try await eventually { world.logLines == ["Save As: \(id) was deleted while the panel was open"] }
        #expect(!exists(gone))
        #expect(world.notifier.calls.isEmpty)
    }
}
