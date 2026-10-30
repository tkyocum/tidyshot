import Foundation
import Testing
@testable import TidyShot

/// Delete, its aborts and the prune on a built coordinator (R4 design, Delete; Phase 3's delete order;
/// harness design 3.3). Destinations come from the world's factory; the alerts are `FakeConfirm`.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorDeleteTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }

    func location(_ bucket: String) -> ObjectLocation {
        ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2", bucket: bucket,
                       usePathStyle: true)
    }

    func ref(at location: ObjectLocation, uploadID: String = "stored-1") -> MultipartRef {
        MultipartRef(uploadID: uploadID, key: "s/STORED.mp4", location: location)
    }

    /// An uploaded screenshot with no local file, at the world's location.
    func addUploadedImage(to coordinator: AppCoordinator, key: String = "s/SHOT.png") -> CaptureRecord {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                   objectLocation: world.location)
        coordinator.history.add(record)
        return record
    }

    /// A recording in `pending/` of 3 bytes, added to history.
    func addPendingRecording(to coordinator: AppCoordinator, state: CaptureRecord.UploadState = .none,
                             multipart: MultipartUploadState? = nil) throws -> CaptureRecord {
        let id = UUID()
        let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
        try CoordinatorWorld.writeSparseFile(at: url, byteCount: 3)
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                   appName: nil, uploadState: state, mediaKind: .video, durationSeconds: 10,
                                   byteCount: 3, multipart: multipart)
        coordinator.history.add(record)
        return record
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// 35 (harness design 3.3). Nothing to abort: nil, and no destination is made.
    @Test func abortingNothingAsksForNoDestination() async {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()

        #expect(await coordinator.abortUploads([], name: "Recording.mp4") == nil)
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// 36 (harness design 3.3). A Keychain read that fails is the reason, not missing credentials.
    @Test func aKeychainReadThatFailsIsTheAbortsReason() async {
        defer { world.removeAll() }
        world.credentialStore = ThrowingCredentialStore()
        let coordinator = world.makeCoordinator()

        let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

        let expected = "Could not read S3 credentials from the keychain: The keychain is locked."
        #expect(reason == expected)
        #expect(world.logLines == ["Keychain read failed: The keychain is locked.",
                                   "Upload: Recording.mp4 multipart abort failed: \(expected)"])
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// 37 (harness design 3.3). No stored credentials is the reason.
    @Test func noStoredCredentialsIsTheAbortsReason() async throws {
        defer { world.removeAll() }
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let coordinator = world.makeCoordinator()

        let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

        #expect(reason == "No credentials are saved in Settings > Upload.")
        #expect(world.logLines == ["Upload: Recording.mp4 multipart abort failed: No credentials are saved in Settings > Upload."])
    }

    /// 38 (harness design 3.3). R4 checklist, Multipart: Delete of a failed multipart upload aborts it. A 204 is sent again,
    /// for a part that lands after the first.
    @Test func anAbortThatAnswers204IsSentAgain() async {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()

        let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

        #expect(reason == nil)
        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1", "stored-1"])
        #expect(world.logLines == ["Upload: Recording.mp4 multipart aborted"])
    }

    /// 39 (harness design 3.3 and 5.2). An Abort that answers 404 is not sent again, counts as done, and is
    /// logged as gone.
    @Test func anAbortThatFindsNothingIsNotRepeatedAndLogsItGone() async {
        defer { world.removeAll() }
        destination.state.withLock { $0.abortResult = .notFound }
        let coordinator = world.makeCoordinator()

        let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

        #expect(reason == nil)
        #expect(destination.state.withLock { $0.aborts.count } == 1)
        #expect(world.logLines == ["Upload: Recording.mp4 multipart upload already gone"])
    }

    /// 40 (harness design 3.3). A failed Abort is the reason at once; a later upload is not tried.
    @Test func aFailedAbortStopsAtOnce() async {
        defer { world.removeAll() }
        destination.state.withLock { $0.abortFailures = [.httpStatus(403, body: "AccessDenied: Access Denied")] }
        let other = FakeDestination()
        world.factory.add(other, at: location("old.tky.io"))
        let coordinator = world.makeCoordinator()

        let reason = await coordinator.abortUploads([ref(at: world.location), ref(at: location("old.tky.io"))],
                                                    name: "Recording.mp4")

        #expect(reason == "Server returned HTTP 403: AccessDenied: Access Denied")
        #expect(other.state.withLock { $0.aborts.isEmpty })
        #expect(world.factory.askedLocations == [world.location])
        #expect(world.logLines == ["Upload: Recording.mp4 multipart abort failed: Server returned HTTP 403: AccessDenied: Access Denied"])
    }

    /// 41 (harness design 3.3). Each upload is aborted where it was created, never through the current Upload settings.
    @Test func eachUploadIsAbortedWhereItWasCreated() async {
        defer { world.removeAll() }
        let first = FakeDestination()
        let second = FakeDestination()
        world.factory.add(first, at: location("one.tky.io"))
        world.factory.add(second, at: location("two.tky.io"))
        let coordinator = world.makeCoordinator()

        let reason = await coordinator.abortUploads([ref(at: location("one.tky.io"), uploadID: "one"),
                                                     ref(at: location("two.tky.io"), uploadID: "two")],
                                                    name: "Recording.mp4")

        #expect(reason == nil)
        #expect(world.factory.askedLocations == [location("one.tky.io"), location("two.tky.io")])
        #expect(first.state.withLock { $0.aborts.map(\.uploadID) } == ["one", "one"])
        #expect(second.state.withLock { $0.aborts.map(\.uploadID) } == ["two", "two"])
        #expect(destination.state.withLock { $0.aborts.isEmpty })
    }

    /// 42 (harness design 3.3). Phase 3: one confirmation; a second Delete while it is open asks nothing; Cancel keeps the
    /// record and deletes nothing.
    @Test func deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing() async throws {
        defer { world.removeAll() }
        world.confirm.holds = true
        let coordinator = world.makeCoordinator()
        let record = addUploadedImage(to: coordinator)

        let first = Task { await coordinator.deleteCapture(recordID: record.id) }
        try await eventually { world.confirm.isWaiting }
        // Its own task, gated with `eventually`: were the guard broken, `FakeConfirm` would record the
        // second ask as an issue and answer it Cancel, so the test fails instead of hanging.
        let second = TaskWatch(Task { await coordinator.deleteCapture(recordID: record.id) })
        try await eventually { second.hasReturned }
        #expect(world.confirm.asked == [.delete(record)])
        world.confirm.answer(false)
        await first.value

        #expect(coordinator.deletingIDs.isEmpty)
        #expect(coordinator.history.record(id: record.id) != nil)
        #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
    }

    /// 43 (harness design 3.3). R4 checklist, Multipart: an Abort refused shows the second alert with the reason and `The
    /// object stays in the bucket.`; No keeps the record and deletes nothing, Yes removes the record and
    /// its pending file.
    @Test func anAbortFailureAsksToRemoveFromHistory() async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        let refused = UploadError.httpStatus(403, body: "AccessDenied: Access Denied")
        destination.state.withLock { $0.abortFailures = [refused, refused] }
        world.confirm.answers = [false, true]
        let coordinator = world.makeCoordinator()
        let stored = MultipartUploadState(uploadID: "stored-1", key: "s/STORED.mp4", location: world.location,
                                          partSize: 262_144, byteCount: 3, sourceModified: Date(),
                                          sourcePath: "/nowhere/Recording.mp4", startedAt: Date())
        let record = try addPendingRecording(to: coordinator, state: .failed(message: "Upload was interrupted."),
                                             multipart: stored)
        let pending = try #require(record.fileURL)
        let question = DeleteConfirmation.removeFromHistory(
            message: CaptureDeletion.storageFailureMessage(reason: "Server returned HTTP 403: AccessDenied: Access Denied"),
            informativeText: CaptureDeletion.storageFailureText)

        await coordinator.deleteCapture(recordID: record.id)
        #expect(world.confirm.asked == [question])
        #expect(coordinator.history.record(id: record.id) != nil)
        #expect(exists(pending))

        await coordinator.deleteCapture(recordID: record.id)
        #expect(world.confirm.asked == [question, question])
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(!exists(pending))
        #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
    }

    /// 44 (harness design 3.3). Phase 3: a key another capture shares is kept, `Not deleted from storage` says so, and the
    /// record goes.
    @Test func aSharedKeyKeepsTheObjectAndSaysSo() async {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        let coordinator = world.makeCoordinator()
        let deleted = addUploadedImage(to: coordinator, key: "s/SHARED.png")
        let sharer = addUploadedImage(to: coordinator, key: "s/SHARED.png")

        await coordinator.deleteCapture(recordID: deleted.id)

        #expect(world.confirm.asked.isEmpty)
        #expect(coordinator.history.record(id: deleted.id) == nil)
        #expect(coordinator.history.record(id: sharer.id) != nil)
        #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
        #expect(world.notifier.calls == [.error(title: "Not deleted from storage",
                                                 message: "Another capture shares this key, s/SHARED.png, so its object was kept. This capture was removed from Recent Captures.")])
    }

    /// 45 (harness design 3.3). Phase 3: a pending file that cannot be removed keeps the record, with `Not deleted`.
    @Test func aPendingFileThatCannotBeRemovedKeepsTheRecord() async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        let coordinator = world.makeCoordinator()
        let record = try addPendingRecording(to: coordinator)
        let pending = try #require(record.fileURL)
        let folder = coordinator.pendingFiles.directory.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }

        await coordinator.deleteCapture(recordID: record.id)

        #expect(world.confirm.asked.isEmpty)
        #expect(coordinator.history.record(id: record.id) != nil)
        #expect(exists(pending))
        let error = try #require(world.notifier.errors.first)
        #expect(error.title == "Not deleted")
        #expect(error.message.hasPrefix("Could not delete \(pending.lastPathComponent): "))
    }

    /// 46 (harness design 3.3). R4 checklist, Multipart: pruning removes the thumbnail, the pending file, the sidecar and the
    /// kept copy, and aborts nothing (no destination is made). It closes no card.
    @Test func pruningRemovesTheFilesAndAsksForNoDestination() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
        let pending = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
        try CoordinatorWorld.writeSparseFile(at: pending, byteCount: 3)
        try coordinator.multipartFiles.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: false, parts: []),
                                                    id: id)
        let keptCopy = coordinator.multipartFiles.keptCopyURL(for: id, ext: "mp4")
        try Data([1]).write(to: keptCopy)
        let record = CaptureRecord(id: id, fileURL: pending, fileIsTemporary: true, thumbnailFileName: thumbnail,
                                   pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/OLD.mp4")!, key: "s/OLD.mp4"),
                                   objectLocation: world.location, mediaKind: .video)

        coordinator.removeFiles(ofPruned: [record])

        #expect(!exists(coordinator.thumbnails.url(forFileName: thumbnail)))
        #expect(!exists(pending))
        try await eventually { !exists(coordinator.multipartFiles.sidecarURL(for: id)) && !exists(keptCopy) }
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(world.cards.closes.isEmpty)
    }

    /// 47 (harness design 3.3). Removing a record clears its bookkeeping everywhere.
    @Test func removingARecordClearsItsBookkeeping() async {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil)
        coordinator.history.add(record)
        let id = record.id
        coordinator.optimizingVideoIDs.insert(id)
        coordinator.fileUploadIDs.insert(id)
        coordinator.videoClipboardCounts[id] = 3
        coordinator.linkNotCopiedIDs.insert(id)
        coordinator.copyFileCounts[id] = 4
        coordinator.dragDownloadResume[id] = (data: Data([1]), signedAt: world.date)

        await coordinator.deleteCapture(recordID: id)

        #expect(world.confirm.asked.isEmpty)
        #expect(coordinator.history.record(id: id) == nil)
        #expect(!coordinator.optimizingVideoIDs.contains(id))
        #expect(!coordinator.fileUploadIDs.contains(id))
        #expect(coordinator.videoClipboardCounts[id] == nil)
        #expect(!coordinator.linkNotCopiedIDs.contains(id))
        #expect(coordinator.copyFileCounts[id] == nil)
        #expect(coordinator.dragDownloadResume[id] == nil)
    }
}
