import Foundation
import Testing
@testable import TidyShot

/// The drag-out download on a built coordinator (R4 design, Drag-out download; harness design 3.1): which
/// record starts one, the card's ring, the three ways it ends, and the resume data a failure keeps.
/// The transfer is `FakeDestination`'s scripted download.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorDragOutTests {
    let world: CoordinatorWorld
    let key = "s/2026/rec.mp4"

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }

    /// An uploaded recording with no local file at the world's location, its card showing.
    func showingUploadedRecording(in coordinator: AppCoordinator) -> CaptureRecord {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                   objectLocation: world.location, mediaKind: .video, durationSeconds: 10,
                                   byteCount: 1_000)
        coordinator.history.add(record)
        world.cards.showing.insert(record.id)
        return record
    }

    /// Resume data naming `name` as URLSession's partial file in the world's temporary folder.
    func resumeData(partial name: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["NSURLSessionResumeInfoTempFileName": name],
                                           format: .binary, options: 0)
    }

    func failure(resumeData: Data) -> URLError {
        URLError(.networkConnectionLost, userInfo: [NSURLSessionDownloadTaskResumeData: resumeData])
    }

    /// Starts a download for `record` and returns its task.
    func startDownload(_ coordinator: AppCoordinator, _ record: CaptureRecord) throws -> Task<URL?, Never> {
        coordinator.downloadDragFile(recordID: record.id)
        return try #require(coordinator.downloadingDragIDs[record.id])
    }

    var downloadsFolder: URL {
        world.temporaryDirectory.appending(path: "Drag/.downloads", directoryHint: .isDirectory)
    }

    /// 1 (harness design 3.1). R4 checklist, Drag-out: a drag shows `Downloading…` with a ring.
    @Test func aDragOfAShowingUploadedRecordingStartsOneDownload() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        destination.state.withLock { $0.holdsDownloads = true }

        let task = try startDownload(coordinator, record)
        try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

        #expect(destination.state.withLock { $0.downloads.map(\.key) } == [key])
        #expect(destination.state.withLock { $0.downloads.map(\.resumeData) } == [nil])
        #expect(coordinator.downloadingVideoIDs == [record.id])
        #expect(world.cards.downloads(for: record.id) == [.running(0)])
        destination.releaseDownloads()
        _ = await task.value
    }

    /// 2 (harness design 3.1). `DragDownloadRule.starts` has its own tests; this pins the coordinator's `isShowing` read.
    @Test func aDragWithNoCardShowingStartsNothing() throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        world.cards.showing = []

        coordinator.downloadDragFile(recordID: record.id)

        #expect(coordinator.downloadingDragIDs.isEmpty)
        #expect(coordinator.downloadingVideoIDs.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(world.cards.downloads(for: record.id).isEmpty)
    }

    /// 3 (harness design 3.1). R4 checklist, Drag-out: a disk-check refusal shows `Your disk is almost full.` and logs it.
    @Test func tooLittleFreeSpaceRefusesTheDownload() throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        // One byte under the record's 1,000 bytes plus the 1 GB a recording keeps free.
        world.freeBytes = 1_000_000_999

        coordinator.downloadDragFile(recordID: record.id)

        #expect(world.cards.downloads(for: record.id) == [.failed(RecordingLimits.diskFullText)])
        #expect(world.logLines == ["Drag-out download for \(record.id) refused, not enough disk space"])
        #expect(world.freeBytesAsked == [coordinator.dragFiles.directory])
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(coordinator.downloadingDragIDs.isEmpty)
    }

    /// 4 (harness design 3.1). No credentials: the card says why, and the log has the failure.
    @Test func noStoredCredentialsFailsTheDownload() throws {
        defer { world.removeAll() }
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)

        coordinator.downloadDragFile(recordID: record.id)

        let text = UploadError.notConfigured.localizedDescription
        #expect(world.cards.downloads(for: record.id) == [.failed(text)])
        #expect(world.logLines == ["Drag-out download for \(record.id) failed: \(text)"])
        #expect(coordinator.downloadingDragIDs.isEmpty)
        #expect(world.notifier.calls.isEmpty)
    }

    /// 5 (harness design 3.1). R4 checklist, Drag-out: the file lands under the key's name in `tmp/Drag/<id>/`.
    @Test func aDownloadThatLandsIsAdoptedAndHandedToTheCard() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        destination.state.withLock {
            $0.downloadFractions = [0.25, 0.5, 1]
            $0.downloadOutcome = .lands(bytes: 1_000)
        }

        let task = try startDownload(coordinator, record)
        let url = try #require(await task.value)

        let expected = coordinator.dragFiles.folder(for: record.id).appending(path: "rec.mp4")
        #expect(url.path(percentEncoded: false) == expected.path(percentEncoded: false))
        #expect(try Data(contentsOf: url).count == 1_000)
        let shown = world.cards.downloads(for: record.id)
        #expect(shown.first == .running(0))
        #expect(shown.contains(.running(0.25)))
        #expect(shown.contains(.running(0.5)))
        #expect(shown.last == .cleared)
        #expect(world.cards.dragFiles(for: record.id) == [url])
        // The ring clears before the card gets the file.
        let ends = world.cards.calls.filter { $0 == .downloading(record.id, nil) || $0 == .dragFile(record.id, url) }
        #expect(ends == [.downloading(record.id, nil), .dragFile(record.id, url)])
        #expect(coordinator.downloadingDragIDs.isEmpty)
        #expect(coordinator.downloadingVideoIDs.isEmpty)
    }

    /// 6 (harness design 3.1). R4 checklist, Drag-out: Close during the download cancels it, `… cancelled` in the log, and
    /// `tmp/Drag/<id>` and `.downloads/` hold nothing. The file lands as the cancel arrives.
    @Test func aCloseDuringTheTransferDropsWhatLands() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        destination.state.withLock {
            $0.holdsDownloads = true
            $0.downloadOutcome = .lands(bytes: 1_000)
        }
        let task = try startDownload(coordinator, record)
        try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

        coordinator.overlayDidClose(record.id, reason: .user)
        try await eventually { destination.state.withLock { $0.downloadCancellations } == 1 }
        destination.releaseDownloads()

        #expect(await task.value == nil)
        #expect(world.cards.downloads(for: record.id).last == .cleared)
        #expect(world.logLines.contains("Drag-out download for \(record.id) cancelled"))
        #expect(world.cards.dragFiles(for: record.id).isEmpty)
        #expect(coordinator.dragFiles.stagedFile(id: record.id) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false)).isEmpty)
    }

    /// 7 (harness design 3.1). The drag folder's removal (Delete, the clean-up) during the transfer bumps the generation and
    /// cancels: the same outcome as a close.
    @Test func aRemovedDragFolderDropsWhatLands() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        destination.state.withLock {
            $0.holdsDownloads = true
            $0.downloadOutcome = .lands(bytes: 1_000)
        }
        let task = try startDownload(coordinator, record)
        try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

        coordinator.removeDragFolder(record.id)
        try await eventually { destination.state.withLock { $0.downloadCancellations } == 1 }
        destination.releaseDownloads()

        #expect(await task.value == nil)
        #expect(world.cards.downloads(for: record.id).last == .cleared)
        #expect(world.logLines.contains("Drag-out download for \(record.id) cancelled"))
        #expect(world.cards.dragFiles(for: record.id).isEmpty)
        #expect(coordinator.dragFiles.stagedFile(id: record.id) == nil)
        // The landed file is in `Drag/.downloads/`, which `removeDragFolder` does not touch.
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false)).isEmpty)
    }

    /// 8 (harness design 3.1). R4 checklist, Drag-out: Wi-Fi off shows `Download failed` with the error and posts nothing;
    /// the resume data is kept with the time the request was signed (plan Gap 16 of R4).
    @Test func aFailureWithResumeDataKeepsItWithTheSigningTime() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        let data = try resumeData(partial: "CFNetworkDownload_A.tmp")
        let error = failure(resumeData: data)
        destination.state.withLock { $0.downloadOutcome = .fails(error) }
        let signedAt = world.date

        let task = try startDownload(coordinator, record)

        #expect(await task.value == nil)
        #expect(world.cards.downloads(for: record.id).last == .failed(error.localizedDescription))
        #expect(world.logLines.contains("Drag-out download for \(record.id) failed: \(error.localizedDescription)"))
        let kept = try #require(coordinator.dragDownloadResume[record.id])
        #expect(kept.data == data)
        #expect(kept.signedAt == signedAt)
        #expect(world.notifier.calls.isEmpty)
    }

    /// 9 (harness design 3.1). A failure that is not a transport error (a 403) keeps nothing.
    @Test func aFailureWithoutResumeDataKeepsNothing() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        destination.state.withLock { $0.downloadOutcome = .fails(UploadError.httpStatus(403, body: "")) }

        let task = try startDownload(coordinator, record)

        #expect(await task.value == nil)
        #expect(world.cards.downloads(for: record.id).last == .failed("Server returned HTTP 403."))
        #expect(coordinator.dragDownloadResume[record.id] == nil)
    }

    /// 10 (harness design 3.1). A transfer that fails after a cancel is a cancel: nothing failed, nothing kept.
    @Test func aFailureAfterACancelKeepsNothing() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        let error = failure(resumeData: try resumeData(partial: "CFNetworkDownload_B.tmp"))
        destination.state.withLock {
            $0.holdsDownloads = true
            $0.downloadOutcome = .fails(error)
        }
        let task = try startDownload(coordinator, record)
        try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

        coordinator.overlayDidClose(record.id, reason: .user)
        try await eventually { destination.state.withLock { $0.downloadCancellations } == 1 }
        destination.releaseDownloads()

        #expect(await task.value == nil)
        #expect(world.cards.downloads(for: record.id).last == .cleared)
        #expect(world.logLines.contains("Drag-out download for \(record.id) cancelled"))
        #expect(!world.logLines.contains { $0.contains("failed") })
        #expect(coordinator.dragDownloadResume[record.id] == nil)
    }

    /// 11 (harness design 3.1). R4 checklist, Drag-out: a drag soon after resumes, and the log shows `resumed at <fraction>`
    /// once; a resume keeps the first request's signing time.
    @Test func aDragWithinTheWindowResumesFromTheKeptData() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        let first = try resumeData(partial: "CFNetworkDownload_C.tmp")
        // The first download reports no fraction, so every `.running` after 0 is the resumed one's.
        destination.state.withLock {
            $0.downloadFractions = []
            $0.downloadOutcome = .fails(failure(resumeData: first))
        }
        let signedAt = world.date
        _ = try await startDownload(coordinator, record).value

        world.date = signedAt.addingTimeInterval(839)
        let second = try resumeData(partial: "CFNetworkDownload_D.tmp")
        let secondError = failure(resumeData: second)
        destination.state.withLock {
            $0.downloadFractions = [0.25, 0.5]
            $0.downloadOutcome = .fails(secondError)
        }
        _ = try await startDownload(coordinator, record).value

        #expect(destination.state.withLock { $0.downloads.map(\.resumeData) } == [nil, first])
        #expect(world.logLines.filter { $0.contains("resumed at") }
                == ["Drag-out download for \(record.id) resumed at 0.2500"])
        let shown = world.cards.downloads(for: record.id)
        #expect(shown == [.running(0), .failed(failure(resumeData: first).localizedDescription),
                          .running(0), .running(0.25), .running(0.5), .failed(secondError.localizedDescription)])
        #expect(coordinator.dragDownloadResume[record.id]?.data == second)
        #expect(coordinator.dragDownloadResume[record.id]?.signedAt == signedAt)
    }

    /// 12 (harness design 3.1). R4 checklist, Drag-out: 14 minutes or more after signing, a drag starts again from 0 with no
    /// `resumed at` line, signs afresh, and the unused resume data's partial file goes.
    @Test func aDragPastTheWindowStartsAgainAndRemovesThePartialFile() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        let partialName = "CFNetworkDownload_E.tmp"
        let partial = world.temporaryDirectory.appending(path: partialName)
        try Data("partial".utf8).write(to: partial)
        let first = try resumeData(partial: partialName)
        destination.state.withLock { $0.downloadOutcome = .fails(failure(resumeData: first)) }
        let signedAt = world.date
        _ = try await startDownload(coordinator, record).value

        world.date = signedAt.addingTimeInterval(840)
        let secondError = failure(resumeData: try resumeData(partial: "CFNetworkDownload_F.tmp"))
        destination.state.withLock { $0.downloadOutcome = .fails(secondError) }
        _ = try await startDownload(coordinator, record).value

        #expect(destination.state.withLock { $0.downloads.map(\.resumeData) } == [nil, nil])
        #expect(!world.logLines.contains { $0.contains("resumed at") })
        #expect(coordinator.dragDownloadResume[record.id]?.signedAt == signedAt.addingTimeInterval(840))
        try await eventually { !FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) }
    }

    /// 13 (harness design 3.1). A cancel with resume data kept drops it and its partial file, and clears the card.
    @Test func cancellingWithKeptResumeDataRemovesThePartialFile() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        let partialName = "CFNetworkDownload_G.tmp"
        let partial = world.temporaryDirectory.appending(path: partialName)
        try Data("partial".utf8).write(to: partial)
        let error = failure(resumeData: try resumeData(partial: partialName))
        destination.state.withLock { $0.downloadOutcome = .fails(error) }
        _ = try await startDownload(coordinator, record).value

        coordinator.cancelDragDownload(record.id)

        #expect(coordinator.dragDownloadResume[record.id] == nil)
        #expect(world.cards.downloads(for: record.id).last == .cleared)
        try await eventually { !FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) }
    }

    /// 14 (harness design 3.1). A fraction that arrives after the end does not put the ring back. A
    /// second record's running download is the control: its fraction, sent after the late one, shows,
    /// so the late one's main-actor hop has run by then.
    @Test func aFractionAfterTheEndDoesNotPutTheRingBack() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        _ = try await startDownload(coordinator, record).value
        let ended = try #require(destination.state.withLock { $0.downloadProgress })
        let other = showingUploadedRecording(in: coordinator)
        destination.state.withLock { $0.holdsDownloads = true }
        let otherTask = try startDownload(coordinator, other)
        try await eventually { destination.state.withLock { $0.downloads.count } == 2 }

        ended(0.9)
        destination.reportLateFraction(0.9)
        try await eventually { world.cards.downloads(for: other.id).contains(.running(0.9)) }

        #expect(world.cards.downloads(for: record.id).last == .cleared)
        #expect(!world.cards.downloads(for: record.id).contains(.running(0.9)))
        destination.releaseDownloads()
        _ = await otherTask.value
    }

    /// 15 (harness design 3.1). R4 checklist, Drag-out: Delete during the download cancels it and removes the folder.
    @Test func deleteCancelsARunningDownloadAndRemovesTheFolder() async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        destination.state.withLock {
            $0.holdsDownloads = true
            $0.downloadOutcome = .lands(bytes: 1_000)
        }
        let task = try startDownload(coordinator, record)
        try await eventually { destination.state.withLock { $0.downloads.count } == 1 }
        // A stale copy in the record's drag folder, so the folder's removal can be seen (the download
        // only makes `Drag/<id>/` when it is adopted).
        let folder = coordinator.dragFiles.folder(for: record.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: folder.appending(path: "rec.mp4"))

        await coordinator.deleteCapture(recordID: record.id)
        try await eventually { destination.state.withLock { $0.downloadCancellations } >= 1 }
        destination.releaseDownloads()

        #expect(await task.value == nil)
        #expect(world.confirm.asked.isEmpty)
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(destination.state.withLock { $0.deletedKeys } == [key])
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false)).isEmpty)
    }

    /// 16 (harness design 3.1). A second drag while one runs starts no second GET.
    @Test func aSecondDragWhileOneRunsStartsNoSecondDownload() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = showingUploadedRecording(in: coordinator)
        destination.state.withLock { $0.holdsDownloads = true }
        let task = try startDownload(coordinator, record)
        try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

        coordinator.downloadDragFile(recordID: record.id)
        for _ in 0..<20 { await Task.yield() }

        #expect(destination.state.withLock { $0.downloads.count } == 1)
        #expect(coordinator.downloadingDragIDs[record.id] == task)
        destination.releaseDownloads()
        _ = await task.value
    }
}
