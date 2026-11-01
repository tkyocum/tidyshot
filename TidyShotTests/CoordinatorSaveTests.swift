import Foundation
import Testing
@testable import TidyShot

/// The save funnels' shared tail and the recording funnel on a built coordinator (`finishSave`,
/// `saveRecording`; recording design, After stopping and Clipboard after the upload; R2's privacy rule; R1's
/// quit mode). Each recording is a few bytes in the world's temporary folder: the funnel moves its file and
/// the fake destination never reads it. Overlay is off unless a test says otherwise, since a card on screen
/// reads the screens.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorSaveTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
        world.settings.showOverlay = false
    }

    var destination: FakeDestination { world.factory.standard }

    /// A finished recording of `bytes` bytes in the world's temporary folder, started now, so retention
    /// (which prunes against the real `Date()`) keeps its record.
    func makeRecording(_ kind: MediaKind = .video, bytes: Int = 3) throws -> Recording {
        let id = UUID()
        let url = world.temporaryDirectory.appending(path: "\(id.uuidString).\(kind.fileExtension)")
        try Data(repeating: 7, count: bytes).write(to: url)
        return Recording(id: id, fileURL: url, startedAt: Date(), pixelWidth: 1600, pixelHeight: 1000, duration: 10,
                         poster: nil, displayID: 1, mediaKind: kind)
    }

    /// `saveRecording`, with the recording counted in first, as the recorder's `.keep` does.
    @discardableResult
    func save(_ coordinator: AppCoordinator, _ recording: Recording, _ intent: CaptureIntent,
              mode: RecordingSaveMode = .normal, stopNotice: RecordingNotice? = nil, saveNotice: RecordingNotice? = nil,
              microphoneNote: RecordingNotice? = nil, cameraNote: RecordingNotice? = nil,
              highlightsNote: RecordingNotice? = nil, unmutedIntervals: [MuteInterval] = []) async -> CaptureRecord? {
        coordinator.recordingSavesInFlight = 1
        return await coordinator.saveRecording(recording, intent: intent, stopNotice: stopNotice, mode: mode,
                                               saveNotice: saveNotice, microphoneNote: microphoneNote,
                                               cameraNote: cameraNote, highlightsNote: highlightsNote,
                                               unmutedIntervals: unmutedIntervals)
    }

    func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
        if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
        return false
    }

    func exists(_ url: URL?) -> Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// True when `url` sits directly in `folder`.
    func isIn(_ url: URL?, _ folder: URL) -> Bool {
        url?.deletingLastPathComponent().pathComponents == folder.pathComponents
    }

    /// Every string a notifier call carries.
    func texts(of call: FakeNotifier.Call) -> [String] {
        switch call {
        case .saved(let title, let file): [title, file]
        case .uploaded(let url, _): [url.absoluteString]
        case .error(let title, let message, let subtitle): [title, message] + [subtitle].compactMap { $0 }
        case .notice(let title, let body, let subtitle): [title, body] + [subtitle].compactMap { $0 }
        case .setUp, .held, .released, .waited: []
        }
    }

    nonisolated enum Cause: CaseIterable, Sendable {
        /// No credentials when it is saved; stored again before the retry.
        case noDestination
        /// The upload refused; the retry comes after a relaunch.
        case failingDestination
    }

    /// phase-2 :44. With Overlay off a capture shows no card and still uploads. The tail is `finishSave`, which a
    /// screenshot's save and a recording's share.
    @Test func aCaptureWithTheOverlayOffShowsNoCardAndStillUploads() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let image = try CoordinatorWorld.image(width: 4, height: 2)
        let file = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .uploading(fraction: 0), byteCount: png.count)
        let target = coordinator.makeDestination()

        await coordinator.finishSave(record, image: image, scale: 1, captureDisplayID: 1, notConfiguredWarning: nil,
                                     showsCard: true, upload: target, payload: { .data(png) }, notification: .none)
        try await eventually { isUploaded(coordinator, id) }

        #expect(!world.cards.calls.contains(.show(id)))
        #expect(coordinator.latestCapture?.id == nil)
        #expect(destination.state.withLock { $0.uploads.count } == 1)
    }

    /// recording-r1 :94, recording-r1 :319. An upload-only recording that cannot upload waits in `pending/`,
    /// failed, with nothing on the clipboard and no `Recording saved` (with no destination, the warning says
    /// TidyShot keeps it); a Retry, after a relaunch too, uploads it and empties `pending/`.
    @Test(arguments: Cause.allCases)
    func anUploadOnlyRecordingThatCannotUploadWaitsInPendingUntilARetry(cause: Cause) async throws {
        defer { world.removeAll() }
        switch cause {
        case .noDestination:
            try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        case .failingDestination:
            destination.state.withLock {
                $0.failuresRemaining = 1
                $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
            }
        }
        // A folder is stored, so a file sent to the save folder by mistake lands in `<root>/Saved/` and fails
        // `isIn(pending, …)` below instead of opening the folder panel (D31).
        try world.storeSaveFolder()
        var coordinator = world.makeCoordinator()
        let recording = try makeRecording()

        let record = try #require(await save(coordinator, recording, CaptureIntent(action: .uploadOnly)))
        try await eventually { coordinator.history.record(id: record.id)?.isFailed == true }

        let pending = try #require(record.fileURL)
        #expect(isIn(pending, coordinator.pendingFiles.directory))
        #expect(pending.lastPathComponent == "\(recording.id.uuidString).mp4")
        #expect(exists(pending))
        #expect(world.clipboard.copies.isEmpty)
        #expect(!world.notifier.calls.contains { if case .saved = $0 { true } else { false } })
        switch cause {
        case .noDestination:
            #expect(world.notifier.calls.contains(.error(title: "Upload not configured",
                                                          message: RecordingSavePlan.uploadOnlyNotConfiguredWarning)))
            try world.credentials.save(CoordinatorWorld.awsCredentials, account: KeychainCredentialStore.defaultAccount)
        case .failingDestination:
            coordinator = world.makeCoordinator()
            coordinator.history.load()
        }
        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }

        #expect(destination.state.withLock { $0.fileUploads.map(\.url.lastPathComponent) } == [pending.lastPathComponent])
        #expect(!exists(pending))
    }

    /// recording-r1 :277, recording-r2 :271. Upload and copy URL: with Also copy image on, a recording's file
    /// reference is on the clipboard meanwhile and its URL replaces it after, while nothing else was copied; a
    /// GIF uploads as `image/gif`, its URL leaves a copy made meanwhile alone with `Uploaded`, and a click then
    /// copies the link.
    @Test(arguments: zip([MediaKind.video, .gif], [false, true]))
    func aRecordingsURLReplacesItsFileReferenceOnlyWhileTheClipboardHoldsIt(kind: MediaKind,
                                                                            clipboardMoved: Bool) async throws {
        defer { world.removeAll() }
        world.settings.alsoCopyImageWhenUploading = kind == .video
        let folder = try world.storeSaveFolder()
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let recording = try makeRecording(kind)

        let record = try #require(await save(coordinator, recording, CaptureIntent(action: .upload)))
        let file = try #require(record.fileURL)
        #expect(isIn(file, folder))
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        if clipboardMoved {
            world.clipboard.changeCount += 1
        }
        destination.releaseUploads()
        try await eventually { isUploaded(coordinator, record.id) }

        let url = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
        if clipboardMoved {
            #expect(world.clipboard.copies.isEmpty)
            #expect(world.notifier.calls.contains(.uploaded(url: url, copied: false)))
            #expect(destination.state.withLock { $0.fileUploads.map(\.contentType) } == ["image/gif"])
            coordinator.copyLinkOrFile(recordID: record.id)
            #expect(world.clipboard.copies == [.url(url)])
        } else {
            #expect(world.clipboard.copies == [.fileURL(file), .url(url)])
            #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
        }
    }

    /// recording-r1 :318. Upload and copy URL with no destination saves the recording as Save and copy image
    /// would: in the save folder with no upload, its file on the clipboard whatever the copy setting says,
    /// `Recording saved`, and the `Upload not configured` warning.
    @Test func uploadWithNoDestinationSavesTheRecordingAndCopiesItsFile() async throws {
        defer { world.removeAll() }
        world.settings.copyImageToClipboard = false
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let recording = try makeRecording()

        let record = try #require(await save(coordinator, recording, CaptureIntent(action: .upload)))

        let file = try #require(record.fileURL)
        #expect(isIn(file, folder))
        #expect(!record.fileIsTemporary)
        #expect(record.uploadState == .none)
        #expect(world.clipboard.copies == [.fileURL(file)])
        #expect(world.notifier.calls == [.error(title: "Upload not configured",
                                                 message: RecordingSavePlan.uploadNotConfiguredWarning),
                                         .saved(title: "Recording saved", file: file.lastPathComponent)])
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// recording-r1 :332 (gap 5), in part. Quit mode, for every action and with Overlay on: no folder prompt, no
    /// upload, no card, no notice and no warning, while the clipboard rule (`RecordingSavePlan` in quit mode) and
    /// the shutter still apply. With no folder stored the file is kept in `pending/<id>.mp4`; an uploading record
    /// is written as interrupted. An uploading action still reads its destination; nothing is sent (D7). By hand:
    /// the quit itself, a folder panel open at the quit, and `.upload`'s `Upload failed` and Retry after the
    /// relaunch.
    @Test func quitModeSkipsTheCardTheUploadAndTheNoticesForEveryAction() async throws {
        defer { world.removeAll() }
        world.settings.showOverlay = true
        let coordinator = world.makeCoordinator()
        // `copyOnly` is the URL command's `action=copy`, which a recording's save ignores.
        let intents = [CaptureIntent(action: .save), CaptureIntent(action: .save, copyOnly: true),
                       CaptureIntent(action: .upload), CaptureIntent(action: .uploadOnly)]
        var expected: [FakeClipboard.Copy] = []

        // Save first with no folder stored: quit mode asks for none. Gated, since a save that asked would wait on
        // a real folder panel; the panel is then closed as Cancel, so the save returns (D31).
        let unsaved = try makeRecording()
        let first = Task { await save(coordinator, unsaved, CaptureIntent(action: .save), mode: .quit) }
        let watch = TaskWatch(first)
        do {
            try await eventually { watch.hasReturned }
        } catch {
            world.saveLocation.cancelFolderChoice()
            throw error
        }
        let kept = try #require(await first.value)
        let keptFile = try #require(kept.fileURL)
        let keptPlan = RecordingSavePlan.make(action: .save, hasDestination: true,
                                              result: .fallback(reason: RecordingSavePlan.noFolderReason),
                                              copyImage: world.settings.copyImageToClipboard,
                                              alsoCopyImage: world.settings.alsoCopyImageWhenUploading, quitMode: true)
        if keptPlan.copiesFileReference {
            expected.append(.fileURL(keptFile))
        }
        #expect(world.saveLocation.currentURL == nil)
        #expect(kept.fileIsTemporary)
        #expect(isIn(keptFile, coordinator.pendingFiles.directory))
        #expect(keptFile.lastPathComponent == "\(unsaved.id.uuidString).mp4")
        #expect(exists(keptFile))
        #expect(coordinator.history.record(id: kept.id) != nil)
        #expect(world.clipboard.copies == expected)
        #expect(world.shutterCount == 1)
        let folder = try world.storeSaveFolder()

        for (index, intent) in intents.enumerated() {
            let recording = try makeRecording()
            let record = try #require(await save(coordinator, recording, intent, mode: .quit))
            let file = try #require(record.fileURL)
            let plan = RecordingSavePlan.make(action: intent.action, hasDestination: true,
                                              result: intent.action == .uploadOnly ? .pending : .saveFolder,
                                              copyImage: world.settings.copyImageToClipboard,
                                              alsoCopyImage: world.settings.alsoCopyImageWhenUploading, quitMode: true)
            if plan.copiesFileReference {
                expected.append(.fileURL(file))
            }
            #expect(isIn(file, intent.action == .uploadOnly ? coordinator.pendingFiles.directory : folder))
            #expect(record.uploadState == plan.uploadState)
            #expect(world.clipboard.copies == expected)
            #expect(world.shutterCount == index + 2)
        }

        #expect(expected.count == 3)
        #expect(!world.cards.calls.contains { if case .show = $0 { true } else { false } })
        #expect(world.notifier.calls.isEmpty)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(coordinator.uploadingIDs.isEmpty)
    }

    /// recording-r2 :312, in part. A recording whose muting failed, for Save with no folder set and with one,
    /// Upload and Upload only: no folder is asked for, the file is in `pending/` and not in the save folder,
    /// nothing uploads, the clipboard is unchanged, and `Sound not muted` posts; Retry Failed Uploads posts
    /// nothing and a press on the card stages nothing to drag. By hand: the `-MuteFailure` run itself, the card's
    /// tool tip and the mark after a relaunch; the card's text and what it offers are
    /// `QuickAccessModelTests.aMarkedRecordSaysSoundNotMutedAndOffersOpenTrimAndDeleteOnly` (D16).
    @Test func aMarkedRecordingStaysInPendingForEveryActionAndNeverLeaves() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let marked = [MuteInterval(start: 1, end: 2)]
        var records: [CaptureRecord] = []
        // Save first with no folder set: a marked save never asks for one. Gated, since a save that asked would
        // wait on a real folder panel; the panel is then closed as Cancel, so the save returns (D31).
        let unsaved = try makeRecording()
        let first = Task { await save(coordinator, unsaved, CaptureIntent(action: .save), unmutedIntervals: marked) }
        let watch = TaskWatch(first)
        do {
            try await eventually { watch.hasReturned }
        } catch {
            world.saveLocation.cancelFolderChoice()
            throw error
        }
        records.append(try #require(await first.value))
        #expect(world.saveLocation.currentURL == nil)
        try world.storeSaveFolder()
        for action in [AfterCaptureAction.save, .upload, .uploadOnly] {
            let recording = try makeRecording()
            records.append(try #require(await save(coordinator, recording, CaptureIntent(action: action),
                                                   unmutedIntervals: marked)))
        }

        for record in records {
            #expect(record.fileIsTemporary)
            #expect(isIn(record.fileURL, coordinator.pendingFiles.directory))
            #expect(exists(record.fileURL))
            #expect(record.uploadState == .none)
            #expect(record.uploadBlockedReason == CaptureRecord.soundNotMutedBody)
        }
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.notifier.calls == Array(repeating: FakeNotifier.Call.error(title: CaptureRecord.soundNotMutedTitle,
                                                                 message: CaptureRecord.soundNotMutedBody), count: 4))

        coordinator.retryFailedUploads()
        let shown = records[0]
        world.cards.showing.insert(shown.id)
        coordinator.prepareDragFile(recordID: shown.id)
        for _ in 0..<20 { await Task.yield() }
        #expect(world.notifier.calls.count == 4)
        #expect(coordinator.dragFiles.stagedFile(id: shown.id) == nil)
        #expect(world.cards.dragFiles(for: shown.id).isEmpty)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
    }

    /// recording-r2 :608, recording-r3 :367. After Stop the notices come in one order: the save's own (`GIF not
    /// made`), `Recording stopped`, the microphone note, the camera note, the highlights note; and `GIF not
    /// made` posts with Show notification off.
    @Test func noticesAfterStopComeInOrderWhateverShowNotificationSays() async throws {
        defer { world.removeAll() }
        world.settings.showNotification = false
        // Stored so an upload-only save sent to the save folder by mistake opens no folder panel (D31).
        try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let notMade = GIFConversion.notMade(GIFMakerError.couldNotRead.localizedDescription)
        let stopped = RecordingNotice(title: "Recording stopped", body: "The display was disconnected.")
        let microphone = RecordingNotice(title: MicrophoneChoice.recordedWithoutTitle, body: MicrophoneChoice.noInputText)
        let camera = RecordingNotice(title: "Recorded without the camera", body: "No camera is connected.")
        let highlights = RecordingNotice(title: "Recorded without click highlights", body: "Input Monitoring is off.")
        let recording = try makeRecording()

        let record = try #require(await save(coordinator, recording, CaptureIntent(action: .uploadOnly),
                                             stopNotice: stopped, saveNotice: notMade, microphoneNote: microphone,
                                             cameraNote: camera, highlightsNote: highlights))
        try await eventually { isUploaded(coordinator, record.id) }

        #expect(world.notifier.errors.map(\.title) == [notMade.title, stopped.title, microphone.title, camera.title,
                                                        highlights.title])
        #expect(world.notifier.errors.first?.message == notMade.body)
    }

    /// recording-r2 :632, in part. A GIF's size is the GIF file's own after its move into the save folder. By
    /// hand: the MP4's size after a failed conversion, and the rows against `ls -l` (a muted recording's size
    /// is `VideoValidationTests.aRewrittenFileReadsItsNewSize`, a trimmed one's
    /// `CaptureRecordTests.aTrimsWriteRecordsTheTrimmedFile`).
    @Test func aGIFsSizeIsTheMovedFilesSize() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let recording = try makeRecording(.gif, bytes: 1_234)

        let record = try #require(await save(coordinator, recording, CaptureIntent(action: .save)))

        let file = try #require(record.fileURL)
        #expect(isIn(file, folder))
        #expect(file.pathExtension == "gif")
        #expect(record.mediaKind == .gif)
        let size = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int
        #expect(record.byteCount == size)
        #expect(record.byteCount == 1_234)
    }

    /// small-tweaks:15 (:18), the save half (the optimised size is
    /// `CoordinatorClopTests.anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie`). An MP4's size is
    /// the file's own after its move into the save folder; the row's text from the size is
    /// `RecentCaptureFormattingTests.detailIsTheTimeAndTheSize`.
    @Test func anMP4sSizeIsTheMovedFilesSize() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let recording = try makeRecording(.video, bytes: 1_234)

        let record = try #require(await save(coordinator, recording, CaptureIntent(action: .save)))

        let file = try #require(record.fileURL)
        #expect(isIn(file, folder))
        #expect(file.pathExtension == "mp4")
        #expect(record.mediaKind == .video)
        let size = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int
        #expect(record.byteCount == size)
        #expect(record.byteCount == 1_234)
    }

    /// recording-r4 :313 (gap 6). A recording's notices never name the URL command's sender: not its stop notice,
    /// not its upload's.
    @Test func recordingNoticesNeverNameTheSender() async throws {
        defer { world.removeAll() }
        // Stored so an upload-only save sent to the save folder by mistake opens no folder panel (D31).
        try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let stopped = RecordingNotice(title: "Recording stopped", body: "The display was disconnected.")
        let recording = try makeRecording()

        let record = try #require(await save(coordinator, recording,
                                             CaptureIntent(action: .uploadOnly, sender: "Raycast"), stopNotice: stopped))
        try await eventually { isUploaded(coordinator, record.id) }

        #expect(world.notifier.calls.contains(.error(title: stopped.title, message: stopped.body)))
        #expect(world.notifier.calls.contains { if case .uploaded = $0 { true } else { false } })
        for call in world.notifier.calls {
            #expect(!texts(of: call).contains { $0.contains("Raycast") }, "\(call)")
        }
    }
}
