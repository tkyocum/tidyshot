import Foundation
import Testing
@testable import TidyShot

/// The actions on a record from a card, a pin or a Recent Captures row (`AppCoordinator+RecordActions`):
/// Copy URL and the row's click, Copy Image, Copy File, and the Save As… suggestion and write. The Save
/// panel is the system's and is never built here.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorRecordActionsTests {
    let world: CoordinatorWorld
    let key = "s/SHOT.png"

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }
    var link: URL { URL(string: "https://snap.tky.io/\(key)")! }

    /// An uploaded capture with no local file, at the world's location.
    func uploadedOnly() -> CaptureRecord {
        CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                      uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
    }

    /// A PNG of 4 by 2 pixels written into `folder` as `name`.
    func writePNG(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appending(path: name)
        try CoordinatorWorld.pngData(width: 4, height: 2).write(to: url)
        return url
    }

    nonisolated enum Source: CaseIterable, Sendable {
        /// Saved in the save folder, never uploaded.
        case savedFile
        /// Uploaded, its file kept in the save folder.
        case uploadedWithItsFile
        /// Upload only, uploaded: no local file.
        case uploadOnly
    }

    nonisolated enum Missing: CaseIterable, Sendable {
        /// Uploaded before Phase 3 (no stored location), its save-folder file deleted.
        case prePhase3Upload
        /// Saved and never uploaded, its file renamed in Finder.
        case renamedSavedFile
    }

    /// phase-2 :40, phase-2 :51, phase-3-1 :30, phase-3 :23. Copy URL and a row's click copy an uploaded capture's
    /// link, again after something else was copied; a saved capture that was never uploaded copies its file.
    /// By hand (phase-3-1 :30, phase-3 :23): the menu closing, which is real menu tracking
    /// (`RecentCapturesMenu.afterMenusClose`).
    @Test func copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile() {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let uploaded = uploadedOnly()
        coordinator.history.add(uploaded)
        let file = URL(filePath: "/Users/tim/Pictures/Shot.png")
        let saved = CaptureRecord(fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil)
        coordinator.history.add(saved)

        coordinator.copyLinkOrFile(recordID: uploaded.id)
        world.clipboard.changeCount += 1
        coordinator.copyLinkOrFile(recordID: uploaded.id)
        coordinator.copyLinkOrFile(recordID: saved.id)

        #expect(world.clipboard.copies == [.url(link), .url(link), .fileURL(file)])
    }

    /// phase-6a :151, phase-3-1 :33 (with `aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage`). Copy Image puts
    /// the PNG and its TIFF on the clipboard for each kind of capture: from the file when there is one,
    /// otherwise from a signed download that posts `Copying image…`; `Image copied` names the key, or the
    /// file of a capture never uploaded (D9).
    @Test(arguments: Source.allCases)
    func copyImageReadsTheFileOrDownloadsTheObject(source: Source) async throws {
        defer { world.removeAll() }
        destination.state.withLock { $0.downloadedData = (try? CoordinatorWorld.pngData(width: 4, height: 2)) ?? Data() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record: CaptureRecord
        switch source {
        case .savedFile:
            let file = try writePNG("Shot.png", in: folder)
            record = CaptureRecord(fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil)
        case .uploadedWithItsFile:
            let file = try writePNG("Shot.png", in: folder)
            record = CaptureRecord(fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        case .uploadOnly:
            record = uploadedOnly()
        }
        coordinator.history.add(record)

        await coordinator.copyImage(recordID: record.id)

        #expect(world.clipboard.copies == [.pngAndTIFF])
        switch source {
        case .savedFile:
            #expect(world.notifier.calls == [.notice(title: "Image copied", body: "Shot.png")])
            #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
        case .uploadedWithItsFile:
            #expect(world.notifier.calls == [.notice(title: "Image copied", body: key)])
            #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
        case .uploadOnly:
            #expect(world.notifier.calls == [.notice(title: "Copying image…", body: "Downloading \(key)"),
                                             .notice(title: "Image copied", body: key)])
            #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
        }
    }

    /// phase-3-1 :33 (with `copyImageReadsTheFileOrDownloadsTheObject`). Copy Image of an upload-only capture whose
    /// download fails (Wi-Fi off) posts `Could not copy image` with the reason, after `Copying image…`, and
    /// copies nothing.
    @Test func aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage() async {
        defer { world.removeAll() }
        let offline = URLError(.notConnectedToInternet)
        destination.state.withLock { $0.dataDownloadFailures = [offline] }
        let coordinator = world.makeCoordinator()
        let record = uploadedOnly()
        coordinator.history.add(record)

        await coordinator.copyImage(recordID: record.id)

        #expect(world.notifier.calls == [.notice(title: "Copying image…", body: "Downloading \(key)"),
                                         .error(title: "Could not copy image", message: offline.localizedDescription)])
        #expect(world.clipboard.copies.isEmpty)
        #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
    }

    /// phase-3-1 :34, phase-3-1 :35. Copy Image of a capture whose recorded file cannot be read and that has no
    /// upload to download from (one from before Phase 3 has no stored location) posts `Could not copy image`
    /// with `The local file could not be read.`, and downloads nothing.
    @Test(arguments: Missing.allCases)
    func copyImageOfAMissingFileWithNoUsableUploadSaysTheFileCouldNotBeRead(record missing: Missing) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let gone = folder.appending(path: "Shot.png")
        let record: CaptureRecord
        switch missing {
        case .prePhase3Upload:
            record = CaptureRecord(fileURL: gone, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: link, key: key))
        case .renamedSavedFile:
            _ = try writePNG("Shot renamed.png", in: folder)
            record = CaptureRecord(fileURL: gone, pixelWidth: 4, pixelHeight: 2, appName: nil)
        }
        coordinator.history.add(record)

        await coordinator.copyImage(recordID: record.id)

        #expect(world.notifier.calls == [.error(title: "Could not copy image",
                                                 message: "The local file could not be read.")])
        #expect(world.clipboard.copies.isEmpty)
        #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
    }

    /// phase-4a :105. The Save As… suggestion of an uploaded upload-only capture is named from the file name
    /// template with the counter as it stands, and draws none, so the next capture's number is not skipped.
    @Test func saveAsSuggestionUsesTheCurrentCounterWithoutDrawingOne() {
        defer { world.removeAll() }
        world.settings.fileNameTemplate = "shot-{counter}"
        _ = world.settings.nextCounter()
        _ = world.settings.nextCounter()
        let coordinator = world.makeCoordinator()
        let record = uploadedOnly()
        coordinator.history.add(record)

        let suggestion = coordinator.saveAsSuggestion(recordID: record.id)

        #expect(suggestion.fileName == "shot-2.png")
        #expect(world.settings.currentCounter == 2)
    }

    /// phase-4a :108, in part. The Save As… write over an existing file replaces it and posts `Saved`; over a
    /// locked file it fails with `Not saved` and the reason, and the file is unchanged. By hand: the panel's
    /// Replace prompt, and the editor's unsaved dot staying (D16).
    @Test func saveAsReplacesAnExistingFileAndSaysNotSavedForALockedOne() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let existing = world.root.appending(path: "Existing.png")
        try Data("old".utf8).write(to: existing)

        let replaced = await coordinator.writeSaveAsCopy(png, to: existing)
        #expect(replaced)
        #expect(try Data(contentsOf: existing) == png)
        #expect(world.notifier.calls == [.saved(title: "Saved", file: "Existing.png")])

        let locked = world.root.appending(path: "Locked.png")
        try Data("old".utf8).write(to: locked)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path(percentEncoded: false)) }

        let written = await coordinator.writeSaveAsCopy(png, to: locked)
        #expect(!written)
        #expect(try Data(contentsOf: locked) == Data("old".utf8))
        let error = try #require(world.notifier.errors.last)
        #expect(error.title == "Not saved")
        #expect(!error.message.isEmpty)
    }

    /// recording-r1 :287, recording-r4 :290. Copy File on a recording in the save folder puts the file itself on
    /// the clipboard; an uploaded recording with no local file copies nothing, also when a downloaded drag copy
    /// sits in its folder (that is not a local file). That Trim downloads its own copy is
    /// `RecordingTrimTests.sourceFollowsEditorInputsOrder`.
    @Test func copyFilePutsASavedRecordingItselfAndNeedsALocalFile() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let file = folder.appending(path: "Recording.mp4")
        try Data(repeating: 7, count: 3).write(to: file)
        let saved = CaptureRecord(fileURL: file, pixelWidth: 1600, pixelHeight: 1000, appName: nil, mediaKind: .video,
                                  durationSeconds: 10)
        let uploaded = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/REC.mp4")!,
                                                            key: "s/REC.mp4"),
                                     objectLocation: world.location, mediaKind: .video, durationSeconds: 10)
        coordinator.history.add(saved)
        coordinator.history.add(uploaded)
        let downloaded = coordinator.dragFiles.folder(for: uploaded.id)
        try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 3).write(to: downloaded.appending(path: "REC.mp4"))

        await coordinator.copyFile(recordID: saved.id)
        await coordinator.copyFile(recordID: uploaded.id)

        #expect(world.clipboard.copies == [.fileURL(file)])
        #expect(coordinator.dragFiles.stagedFile(id: saved.id) == nil)
        #expect(coordinator.copyFileCounts.isEmpty)
        #expect(coordinator.dragCleanups.isEmpty)
    }
}
