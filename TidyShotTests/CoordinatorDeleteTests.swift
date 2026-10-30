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

    /// An upload-only screenshot in `pending/` with a thumbnail, added to history: failed, so a Retry
    /// starts it.
    func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord {
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, thumbnailFileName: thumbnail,
                                   pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .failed(message: "Upload was interrupted."), byteCount: png.count)
        coordinator.history.add(record)
        return record
    }

    /// An uploaded capture whose file is in the stored save folder, with a thumbnail. A nil `location`
    /// is a capture uploaded before Phase 3.
    func addSavedUpload(to coordinator: AppCoordinator, in folder: URL, kind: MediaKind = .image,
                        key: String = "s/SAVED.png", location: ObjectLocation?) throws -> CaptureRecord {
        let id = UUID()
        let file = folder.appending(path: "Saved \(id.uuidString).\(kind.fileExtension)")
        try Data("file".utf8).write(to: file)
        let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
        let record = CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                   objectLocation: location, mediaKind: kind,
                                   durationSeconds: kind == .image ? nil : 10)
        coordinator.history.add(record)
        return record
    }

    func thumbnailURL(_ coordinator: AppCoordinator, _ record: CaptureRecord) throws -> URL {
        coordinator.thumbnails.url(forFileName: try #require(record.thumbnailFileName))
    }

    /// The record kinds `deleteRemovesTheObjectTheFileTheThumbnailAndTheRow` deletes, each with its own
    /// Ask before deleting.
    nonisolated enum Kind: CaseIterable, Sendable {
        /// With Ask before deleting on.
        case image
        /// With it off.
        case video
        /// With it on.
        case gif

        var mediaKind: MediaKind {
            switch self {
            case .image: .image
            case .video: .video
            case .gif: .gif
            }
        }

        var asksFirst: Bool { self != .video }
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

    /// 47 (harness design 3.3). Removing a record clears its bookkeeping everywhere. phase-4a :53: deleting a row
    /// whose card is open closes that card and drops the retained image, so Annotate on another row opens
    /// its own capture (which source it reads is `EditorInputTests.retainedWinsForLatestCapture`).
    @Test func removingARecordClearsItsBookkeeping() async throws {
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
        let image = try CoordinatorWorld.image(width: 4, height: 2)
        coordinator.latestCapture = (id: id, image: ScaledImage(image: image, scale: 1))

        await coordinator.deleteCapture(recordID: id)

        #expect(world.confirm.asked.isEmpty)
        #expect(coordinator.history.record(id: id) == nil)
        #expect(!coordinator.optimizingVideoIDs.contains(id))
        #expect(!coordinator.fileUploadIDs.contains(id))
        #expect(coordinator.videoClipboardCounts[id] == nil)
        #expect(!coordinator.linkNotCopiedIDs.contains(id))
        #expect(coordinator.copyFileCounts[id] == nil)
        #expect(coordinator.dragDownloadResume[id] == nil)
        #expect(coordinator.latestCapture?.id == nil)
        #expect(world.cards.closes == [.deleted])
    }

    /// coordinator-split :45, phase-3 :38, phase-3 :39, phase-3 :41. Delete during an upload: Cancel in the alert
    /// keeps everything, the upload goes on and the card stays; Delete cancels the upload, also on a lane the
    /// Upload tab replaced, deletes the key the upload had reserved, removes the row, the pending file and
    /// the thumbnail, closes the card, and the menu bar icon (`isUploading`) goes back.
    @Test(arguments: [false, true])
    func deleteDuringAnUploadCancelsItThenDeletesTheReservedKey(onAReplacedLane: Bool) async throws {
        defer { world.removeAll() }
        destination.state.withLock { $0.blockingUploadsRemaining = 1 }
        world.confirm.answers = [false, true]
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let pending = try #require(record.fileURL)
        let thumbnail = try thumbnailURL(coordinator, record)
        coordinator.retryUpload(recordID: record.id)
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
        if onAReplacedLane {
            coordinator.destinationDidChange()
            #expect(coordinator.drainingQueues.count == 1)
        }
        // The question names the record as it is now, uploading.
        let uploading = try #require(coordinator.history.record(id: record.id))

        await coordinator.deleteCapture(recordID: record.id)
        #expect(world.confirm.asked == [.delete(uploading)])
        #expect(coordinator.history.record(id: record.id) != nil)
        #expect(coordinator.uploadingIDs.contains(record.id))
        #expect(world.cards.closes.isEmpty)

        await coordinator.deleteCapture(recordID: record.id)
        let attempted = destination.state.withLock { $0.attemptKeys }
        #expect(attempted.count == 1)
        #expect(destination.state.withLock { $0.deletedKeys } == attempted)
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(!exists(pending))
        #expect(!exists(thumbnail))
        #expect(world.cards.closes == [.deleted])
        #expect(!coordinator.isUploading)
        if onAReplacedLane {
            try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
        }
    }

    /// phase-3 :40, phase-5 :181, recording-r1 :309, recording-r2 :676. Delete after the upload finished removes the
    /// object, the save-folder file, the thumbnail and the row, after one confirmation with Ask before
    /// deleting on and none with it off; a stitched capture, a video and a GIF go as a screenshot does.
    @Test(arguments: Kind.allCases)
    func deleteRemovesTheObjectTheFileTheThumbnailAndTheRow(kind: Kind) async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = kind.asksFirst
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let key = "s/SAVED.\(kind.mediaKind.fileExtension)"
        let record = try addSavedUpload(to: coordinator, in: folder, kind: kind.mediaKind, key: key,
                                        location: world.location)
        let file = try #require(record.fileURL)
        let thumbnail = try thumbnailURL(coordinator, record)

        await coordinator.deleteCapture(recordID: record.id)

        #expect(world.confirm.asked == (kind.asksFirst ? [.delete(record)] : []))
        #expect(destination.state.withLock { $0.deletedKeys } == [key])
        #expect(world.factory.askedLocations == [world.location])
        #expect(!exists(file))
        #expect(!exists(thumbnail))
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(world.cards.closes == [.deleted])
    }

    /// phase-3-1 :50. Delete of an upload-only capture whose upload failed asks once and sends no DELETE (nothing
    /// was uploaded and no key reserved), and the row, the thumbnail and `pending/<id>.png` go.
    @Test func aFailedUploadOnlyCaptureIsDeletedWithOneQuestionAndNoDelete() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let pending = try #require(record.fileURL)
        let thumbnail = try thumbnailURL(coordinator, record)

        await coordinator.deleteCapture(recordID: record.id)

        #expect(world.confirm.asked == [.delete(record)])
        #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(!exists(thumbnail))
        #expect(!exists(pending))
    }

    /// phase-3-1 :52, small-tweaks :9. With no credentials, Delete of an uploaded capture shows the second alert,
    /// `Couldn't delete it from storage: No credentials are saved in Settings > Upload.`; with Ask before
    /// deleting off it is the only alert. Remove drops the row.
    @Test(arguments: [true, false])
    func aDeleteThatCannotReachStorageAsksToRemoveFromHistory(confirmFirst: Bool) async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = confirmFirst
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let coordinator = world.makeCoordinator()
        let record = addUploadedImage(to: coordinator)
        let question = DeleteConfirmation.removeFromHistory(
            message: CaptureDeletion.storageFailureMessage(reason: "No credentials are saved in Settings > Upload."),
            informativeText: CaptureDeletion.storageFailureText)

        await coordinator.deleteCapture(recordID: record.id)

        #expect(world.confirm.asked == (confirmFirst ? [.delete(record), question] : [question]))
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// phase-3-1 :51. Delete after an upload reserved its key, with the storage DELETE failing: the second alert
    /// carries the reason; Cancel keeps the row (`Upload cancelled.`, failed, its key reserved) and
    /// `pending/<id>.png`; a second Delete that fails again, then Remove, drops the row, the thumbnail and the
    /// pending file.
    @Test func aRemoteDeleteFailureDuringAnUploadKeepsTheRecordUntilRemoveFromHistory() async throws {
        defer { world.removeAll() }
        let refused = UploadError.httpStatus(403, body: "AccessDenied: Access Denied")
        destination.state.withLock {
            $0.blockingUploadsRemaining = 1
            $0.deleteFailures = [refused, refused]
        }
        world.confirm.answers = [true, false]
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let pending = try #require(record.fileURL)
        let thumbnail = try thumbnailURL(coordinator, record)
        coordinator.retryUpload(recordID: record.id)
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
        let uploading = try #require(coordinator.history.record(id: record.id))
        let question = DeleteConfirmation.removeFromHistory(
            message: CaptureDeletion.storageFailureMessage(reason: refused.localizedDescription),
            informativeText: CaptureDeletion.storageFailureText)

        await coordinator.deleteCapture(recordID: record.id)
        let key = try #require(destination.state.withLock { $0.attemptKeys.first })
        let kept = try #require(coordinator.history.record(id: record.id))
        #expect(world.confirm.asked == [.delete(uploading), question])
        #expect(kept.uploadState == .failed(message: "Upload cancelled."))
        #expect(kept.pendingObjectKey == key)
        #expect(exists(pending))

        world.confirm.answers = [true, true]
        await coordinator.deleteCapture(recordID: record.id)
        #expect(world.confirm.asked == [.delete(uploading), question, .delete(kept), question])
        #expect(destination.state.withLock { $0.deletedKeys } == [key, key])
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(!exists(thumbnail))
        #expect(!exists(pending))
    }

    /// phase-3 :26 (with `CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays`, the alert's text). A
    /// capture uploaded before Phase 3 has no stored location: Delete sends no DELETE, so the object stays,
    /// and removes the row and the save-folder file.
    @Test func aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record = try addSavedUpload(to: coordinator, in: folder, location: nil)
        let file = try #require(record.fileURL)

        await coordinator.deleteCapture(recordID: record.id)

        #expect(world.confirm.asked == [.delete(record)])
        #expect(world.factory.askedLocations.isEmpty)
        #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
        #expect(!exists(file))
        #expect(coordinator.history.record(id: record.id) == nil)
    }

    /// phase-3 :31. After the Upload tab names another bucket, Delete of a capture uploaded before the change
    /// removes the object from the bucket it went to, never through the current settings.
    @Test func aDeleteAfterABucketChangeDeletesWhereTheObjectWent() async {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        let old = FakeDestination()
        world.factory.add(old, at: location("old.tky.io"))
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://old.tky.io/s/OLD.png")!,
                                                          key: "s/OLD.png"),
                                   objectLocation: location("old.tky.io"))
        coordinator.history.add(record)

        await coordinator.deleteCapture(recordID: record.id)

        #expect(old.state.withLock { $0.deletedKeys } == ["s/OLD.png"])
        #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
        #expect(world.factory.askedLocations == [location("old.tky.io")])
        #expect(coordinator.history.record(id: record.id) == nil)
    }

    /// phase-4a :135. Delete during a replace (an upload over the link's own key) cancels the upload in its lane
    /// and deletes the link's key, so `curl -I <url>` gives 403 or 404.
    @Test func deleteDuringAReplaceCancelsItAndDeletesTheLinksKey() async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        destination.state.withLock { $0.blockingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let record = addUploadedImage(to: coordinator, key: "s/LINK.png")
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let target = try #require(coordinator.makeDestination())
        coordinator.startPlannedUpload(recordID: record.id, plan: .replace(key: "s/LINK.png"), payload: .data(png),
                                       destination: target)
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
        #expect(destination.state.withLock { $0.attemptKeys } == ["s/LINK.png"])

        await coordinator.deleteCapture(recordID: record.id)

        #expect(coordinator.uploadingIDs.isEmpty)
        try await eventually { await coordinator.queue?.queue.isIdle == true }
        #expect(destination.state.withLock { $0.uploads.isEmpty })
        #expect(destination.state.withLock { $0.deletedKeys } == ["s/LINK.png"])
        #expect(coordinator.history.record(id: record.id) == nil)
    }

    /// recording-r4 :236. Delete of a recording mid-upload in parts: the parts are cancelled, the stored upload is
    /// aborted where it was created (twice: a 204 is repeated), the reserved key is deleted, and the record
    /// and its `multipart/` files go.
    @Test func deleteDuringAMultipartUploadAbortsItAndDeletesTheKey() async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 3)
        destination.state.withLock { $0.partDelay = .seconds(60) }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
        try CoordinatorWorld.writeSparseFile(at: file, byteCount: 1_048_576)
        coordinator.history.add(CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 1600,
                                              pixelHeight: 1000, appName: nil,
                                              uploadState: .failed(message: "Upload was interrupted."),
                                              mediaKind: .video, durationSeconds: 10, byteCount: 1_048_576))
        coordinator.retryUpload(recordID: id)
        try await eventually { coordinator.history.record(id: id)?.multipart != nil }
        try await eventually { destination.state.withLock { $0.partsInFlight } == 3 }
        let key = try #require(destination.state.withLock { $0.creates.first?.key })

        await coordinator.deleteCapture(recordID: id)

        #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["upload-1", "upload-1"])
        #expect(destination.state.withLock { $0.deletedKeys } == [key])
        #expect(destination.state.withLock { $0.completes.isEmpty })
        #expect(coordinator.history.record(id: id) == nil)
        #expect(!exists(file))
        try await eventually { !exists(coordinator.multipartFiles.sidecarURL(for: id)) }
    }

    /// recording-r4 :377 (call G). Delete's second Abort failing, after a first that answered 204, fails Delete as
    /// a first failure does: the second alert carries the reason, the log names it, and Remove drops the
    /// record. `onCall` sets the failure after the first Abort has drawn its own.
    @Test func aSecondAbortThatFailsAsksToRemoveFromHistory() async throws {
        defer { world.removeAll() }
        world.settings.confirmBeforeDeleting = false
        let refused = UploadError.httpStatus(403, body: "AccessDenied: Access Denied")
        let fake = world.factory.standard
        fake.state.withLock {
            $0.onCall = { call in
                guard call == "abort" else { return }
                fake.state.withLock { state in
                    if state.aborts.count == 1 { state.abortFailures = [refused] }
                }
            }
        }
        defer { fake.state.withLock { $0.onCall = nil } }
        let coordinator = world.makeCoordinator()
        let stored = MultipartUploadState(uploadID: "stored-1", key: "s/STORED.mp4", location: world.location,
                                          partSize: 262_144, byteCount: 3, sourceModified: Date(),
                                          sourcePath: "/nowhere/Recording.mp4", startedAt: Date())
        let record = try addPendingRecording(to: coordinator, state: .failed(message: "Upload was interrupted."),
                                             multipart: stored)
        let name = try #require(record.fileURL?.lastPathComponent)
        let question = DeleteConfirmation.removeFromHistory(
            message: CaptureDeletion.storageFailureMessage(reason: refused.localizedDescription),
            informativeText: CaptureDeletion.storageFailureText)

        await coordinator.deleteCapture(recordID: record.id)

        #expect(fake.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1", "stored-1"])
        #expect(world.confirm.asked == [question])
        #expect(world.logLines.contains("Upload: \(name) multipart abort failed: \(refused.localizedDescription)"))
        #expect(fake.state.withLock { $0.deletedKeys.isEmpty })
        #expect(coordinator.history.record(id: record.id) == nil)
    }

    /// phase-2 :57, phase-3 :66, recording-r1 :310. Retention at 1 day, then a capture: the older rows go with
    /// their thumbnails, their save-folder files stay (a video's as a screenshot's), a failed upload-only
    /// capture is kept with its `pending/` file however old it is, and nothing asks for a destination.
    @Test func retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        // Relative to the real `Date()`, which the history prunes against.
        let old = Date(timeIntervalSinceNow: -2 * 86_400)
        var oldRecords: [CaptureRecord] = []
        for kind in [MediaKind.image, .video] {
            let id = UUID()
            let file = folder.appending(path: "Old \(id.uuidString).\(kind.fileExtension)")
            try Data("file".utf8).write(to: file)
            let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
            let key = "s/\(id.uuidString).\(kind.fileExtension)"
            let record = CaptureRecord(id: id, timestamp: old, fileURL: file, thumbnailFileName: thumbnail,
                                       pixelWidth: 4, pixelHeight: 2, appName: nil,
                                       uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                       objectLocation: world.location, mediaKind: kind)
            coordinator.history.add(record)
            oldRecords.append(record)
        }
        let unsentID = UUID()
        let unsentFile = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 4, height: 2),
                                                            id: unsentID, ext: "png")
        coordinator.history.add(CaptureRecord(id: unsentID, timestamp: old, fileURL: unsentFile, fileIsTemporary: true,
                                              pixelWidth: 4, pixelHeight: 2, appName: nil,
                                              uploadState: .failed(message: "Upload was interrupted.")))
        // Added under the 30-day default, so these adds prune nothing.
        #expect(coordinator.history.records.count == 3)

        world.settings.historyRetentionDays = 1
        coordinator.history.add(CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil))

        for record in oldRecords {
            let thumbnail = try thumbnailURL(coordinator, record)
            let file = try #require(record.fileURL)
            #expect(coordinator.history.record(id: record.id) == nil)
            #expect(!exists(thumbnail))
            #expect(exists(file))
        }
        #expect(coordinator.history.record(id: unsentID) != nil)
        #expect(exists(unsentFile))
        #expect(world.factory.askedConfigs.isEmpty)
    }
}
