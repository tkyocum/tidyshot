import Foundation
import Testing
@testable import TidyShot

/// `Upload Trimmed` and the trim's refusals on a built coordinator (`AppCoordinator+Trim`, recording design,
/// Stale link and Write-time checks). `uploadTrimmed` reaches only the refusal rule, the destination, the
/// save folder, the payload and `startPlannedUpload`; no Trim window is built.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorTrimTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }

    /// An uploaded recording in `pending/` whose link still shows the full recording (`uploadIsStale`), as a
    /// trim's Save leaves an upload-only one.
    func addTrimmedUpload(to coordinator: AppCoordinator, byteCount: Int64 = 3,
                          key: String = "s/REC.mp4") throws -> CaptureRecord {
        let id = UUID()
        let file = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
        try CoordinatorWorld.writeSparseFile(at: file, byteCount: byteCount)
        let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                   appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                   objectLocation: world.location, uploadIsStale: true, mediaKind: .video,
                                   durationSeconds: 10, byteCount: Int(byteCount))
        coordinator.history.add(record)
        return record
    }

    /// recording-r2 :456, in part. `Upload Trimmed` PUTs the link's own key and clears `Link not updated`; a
    /// failed one keeps the link and the note and says `Not uploaded`. By hand: the trim sheet as it shows
    /// (its table is `RecordingTrimTests.saveTargetWithADestination` and `.saveTargetWithNoDestination`).
    @Test func uploadTrimmedClearsTheStaleNoteOnSuccessAndKeepsItOnFailure() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let trimmed = try addTrimmedUpload(to: coordinator)

        coordinator.uploadTrimmed(recordID: trimmed.id)
        try await eventually { coordinator.history.record(id: trimmed.id)?.uploadIsStale == false }

        #expect(destination.state.withLock { $0.fileUploads.map(\.key) } == ["s/REC.mp4"])
        #expect(destination.state.withLock { $0.fileUploads.map(\.cacheControl) } == ["no-cache"])
        #expect(coordinator.history.record(id: trimmed.id)?.uploadedKey == "s/REC.mp4")

        destination.state.withLock {
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
        }
        let failing = try addTrimmedUpload(to: coordinator, key: "s/OTHER.mp4")
        coordinator.uploadTrimmed(recordID: failing.id)
        try await eventually {
            world.notifier.calls.contains(.error(title: "Not uploaded",
                                                 message: EditorUploadPlan.failedReplaceRecordingMessage))
        }
        let kept = try #require(coordinator.history.record(id: failing.id))
        #expect(kept.uploadState == failing.uploadState)
        #expect(kept.uploadIsStale)
        #expect(kept.fileURL == failing.fileURL)
    }

    /// recording-r4 :251. `Upload Trimmed` of a file over the part threshold replaces the link in parts, at the
    /// link's key; a failure keeps the old link, marked stale, and a later `Upload Trimmed` of the unchanged
    /// file resumes the stored upload with no second Create.
    @Test func uploadTrimmedReplacesInPartsKeepsTheLinkOnFailureAndResumes() async throws {
        defer { world.removeAll() }
        world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 1)
        destination.state.withLock { $0.partFailures = [2: [.httpStatus(403, body: "AccessDenied: Access Denied")]] }
        let coordinator = world.makeCoordinator()
        let trimmed = try addTrimmedUpload(to: coordinator, byteCount: 1_048_576)

        coordinator.uploadTrimmed(recordID: trimmed.id)
        try await eventually {
            world.notifier.calls.contains(.error(title: "Not uploaded",
                                                 message: EditorUploadPlan.failedReplaceRecordingMessage))
        }
        #expect(destination.state.withLock { $0.creates.map(\.key) } == ["s/REC.mp4"])
        let failed = try #require(coordinator.history.record(id: trimmed.id))
        #expect(failed.uploadState == trimmed.uploadState)
        #expect(failed.uploadIsStale)
        #expect(failed.multipart?.uploadID == "upload-1")

        coordinator.uploadTrimmed(recordID: trimmed.id)
        try await eventually { coordinator.history.record(id: trimmed.id)?.uploadIsStale == false }

        #expect(destination.state.withLock { $0.creates.count } == 1)
        #expect(destination.state.withLock { $0.completes.map(\.uploadID) } == ["upload-1"])
        #expect(coordinator.history.record(id: trimmed.id)?.uploadedKey == "s/REC.mp4")
    }

    /// recording-r2 :645 (call C). The first replace of a launch whose URL was not copied, because the clipboard
    /// changed during the upload, posts the cache note titled `Uploaded`, not `Uploaded, URL copied`.
    @Test func aFirstReplaceWhoseURLWasNotCopiedPostsTheCacheNoteAsUploaded() async throws {
        defer { world.removeAll() }
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let trimmed = try addTrimmedUpload(to: coordinator)

        coordinator.uploadTrimmed(recordID: trimmed.id)
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
        world.clipboard.changeCount += 1
        destination.releaseUploads()
        try await eventually { coordinator.history.record(id: trimmed.id)?.uploadIsStale == false }

        #expect(world.notifier.calls.contains(.notice(title: "Uploaded", body: EditorUploadPlan.cacheNote)))
        #expect(!world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
        #expect(!world.clipboard.copies.contains { if case .url = $0 { true } else { false } })
        #expect(coordinator.linkNotCopiedIDs.contains(trimmed.id))
    }

    /// recording-r2 :475. While a Trim pass writes the file, Delete is refused with `Not deleted` and the trimming
    /// text, and `Upload Trimmed` with `Not uploaded` / `This capture is being trimmed.`; the record stays.
    /// Retry's refusal is `CoordinatorUploadTests.aRetryOfATrimmingOrUploadingRecordDoesNothingButSay`, and the
    /// card's disabled items `QuickAccessModelTests.retryUploadTrimmedAndDeleteAreDisabledWhileTrimming`.
    @Test func aCaptureBeingTrimmedRefusesDeleteAndUploadTrimmed() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let trimmed = try addTrimmedUpload(to: coordinator)
        coordinator.trimmingIDs.insert(trimmed.id)

        await coordinator.deleteCapture(recordID: trimmed.id)
        coordinator.uploadTrimmed(recordID: trimmed.id)

        #expect(world.notifier.calls == [.error(title: "Not deleted", message: CaptureDeletion.trimmingRefusal),
                                         .error(title: "Not uploaded", message: "This capture is being trimmed.")])
        #expect(world.confirm.asked.isEmpty)
        #expect(coordinator.history.record(id: trimmed.id) == trimmed)
        #expect(world.factory.askedConfigs.isEmpty)
    }
}
