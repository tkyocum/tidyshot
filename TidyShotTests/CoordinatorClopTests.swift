import Foundation
import Testing
@testable import TidyShot

/// Clop on a built coordinator (small seams design, CLOP): the image and recording decisions, what is
/// sent, the `Clop:` lines, and Delete, a Retry, a settings change and the toggle while Clop holds a
/// request. Clop is the world's `FakeClop`; its work folder is `<root>/tmp/Clop`. A test that scripts
/// `.hold` releases it in a `defer` placed after `removeAll()`'s and gates on `clopWaitsPerLane` emptying
/// before its last checks, so the start task has ended.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorClopTests {
    let world: CoordinatorWorld
    /// `MultipartPlan.standard.threshold` (100 MiB): Clop's movie at this size or more is kept for resume,
    /// whatever the lane's plan (+Upload:274).
    let threshold = MultipartPlan.standard.threshold

    init() throws {
        world = try CoordinatorWorld()
        world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 3)
        world.settings.optimiseWithClop = true
    }

    var destination: FakeDestination { world.factory.standard }

    /// An upload-only screenshot in `pending/`, failed, added to history.
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

    /// A screenshot saved as `Saved <id>.png` in `folder`, failed, added to history.
    func addSavedImage(to coordinator: AppCoordinator, in folder: URL) throws -> CaptureRecord {
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let url = folder.appending(path: "Saved \(id.uuidString).png")
        try png.write(to: url)
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: false, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                   byteCount: png.count)
        coordinator.history.add(record)
        return record
    }

    /// A 10 s recording whose sparse file of `byteCount` bytes is `pending/<id>.mp4`, failed, added to history.
    func addPendingRecording(to coordinator: AppCoordinator, byteCount: Int64) throws -> CaptureRecord {
        let id = UUID()
        let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
        try CoordinatorWorld.writeSparseFile(at: url, byteCount: byteCount)
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                   mediaKind: .video, durationSeconds: 10, byteCount: Int(byteCount))
        coordinator.history.add(record)
        return record
    }

    /// A 10 s GIF of 3 sparse bytes, `pending/<id>.gif`, failed, added to history.
    func addGIF(to coordinator: AppCoordinator) throws -> CaptureRecord {
        let id = UUID()
        let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).gif")
        try CoordinatorWorld.writeSparseFile(at: url, byteCount: 3)
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                   mediaKind: .gif, durationSeconds: 10, byteCount: 3)
        coordinator.history.add(record)
        return record
    }

    /// Keys `s/<counter>.<ext>`, so the order counters are drawn in shows.
    func useCounterTemplate() {
        var config = CoordinatorWorld.config
        config.keyTemplate = "s/{counter}"
        world.settings.s3Config = config
    }

    func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
        coordinator.history.record(id: id)?.uploadedURL != nil
    }

    /// The last `Optimizing…` flag the card was given for `id`, or nil when it was given none.
    func lastOptimizing(_ id: UUID) -> Bool? {
        for call in world.cards.calls.reversed() {
            if case .optimizing(let callID, let flag) = call, callID == id { return flag }
        }
        return nil
    }

    /// phase-7-clop:21 (:23), in part; phase-7-clop:45 (:47); small-tweaks:14 (:17); the hold leg of
    /// phase-7-clop:29 (:31) and the Retry leg of phase-7-clop:28 (:30). With Clop on and running, a Retry's PNG
    /// goes to Clop, the pending file stays as captured while it waits, and Clop's bytes are sent and become the
    /// row's size. Turned off during that request, the running upload still sends Clop's bytes; the next asks
    /// nothing and sends the original. Stays: phase-7-clop:21, closing Settings with no Save and `defaults read`
    /// of the real domain, by hand (the persistence is `AppSettingsTests.optimiseWithClopDefaultsOffAndPersists`).
    @Test func turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        let smaller = Data("clop".utf8)
        world.clop.answers = [.hold]
        let coordinator = world.makeCoordinator()
        let first = try addPendingImage(to: coordinator)
        let pending = try #require(first.fileURL)
        let original = try Data(contentsOf: pending)

        coordinator.retryUpload(recordID: first.id)
        try await eventually { world.clop.isHolding }
        #expect(world.clop.requests == [.png(original)])
        #expect(world.clop.runningChecks == 1)
        #expect(try Data(contentsOf: pending) == original)
        #expect(coordinator.history.record(id: first.id)?.uploadState == .uploading(fraction: 0))
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)

        world.settings.optimiseWithClop = false
        world.clop.release(.smaller(smaller))
        try await eventually { isUploaded(coordinator, first.id) }
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        #expect(destination.state.withLock { $0.uploads.map(\.data) } == [smaller])
        #expect(coordinator.history.record(id: first.id)?.byteCount == smaller.count)
        #expect(!world.logLines.contains { $0.hasPrefix("Clop:") })

        let second = try addPendingImage(to: coordinator)
        let secondOriginal = try Data(contentsOf: try #require(second.fileURL))
        coordinator.retryUpload(recordID: second.id)
        try await eventually { isUploaded(coordinator, second.id) }
        #expect(world.clop.requests.count == 1)
        #expect(world.clop.runningChecks == 1)
        #expect(destination.state.withLock { $0.uploads.map(\.data) } == [smaller, secondOriginal])
        #expect(coordinator.history.record(id: second.id)?.byteCount == secondOriginal.count)
    }

    /// phase-7-clop:31 (:33), phase-7-clop:35 (:37), phase-7-clop:36 (:38), phase-7-clop:37 (:39). Clop not running
    /// asks nothing; a result Clop could not shrink, a converted file and a failed request each upload the original.
    /// Each logs one `Clop:` line and posts no error. TidyShot never launches Clop: `ClopApp` has no launch call. What
    /// makes real Clop answer each way (a white fill, Clop's convert setting, the free-tier cap) is the lines' set-up;
    /// the optimiser's own checks are `ClopOptimiserTests`.
    @Test(arguments: [
        (ClopSkipReason.notRunning, "Clop: Clop is not running, uploading the original"),
        (.notSmaller, "Clop: the result is not smaller, uploading the original"),
        (.converted, "Clop: Clop converted the file to another format, uploading the original"),
        (.failed("Clop's port is unavailable"), "Clop: Clop's port is unavailable, uploading the original"),
    ])
    func aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason: ClopSkipReason, line: String) async throws {
        defer { world.removeAll() }
        if reason == .notRunning {
            world.clop.isRunning = false
        } else {
            world.clop.answers = [.original(reason)]
        }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let original = try Data(contentsOf: try #require(record.fileURL))

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }

        #expect(world.clop.runningChecks == 1)
        #expect(world.clop.requests == (reason == .notRunning ? [] : [.png(original)]))
        #expect(world.logLines.filter { $0.hasPrefix("Clop:") } == [line])
        #expect(destination.state.withLock { $0.uploads.map(\.data) } == [original])
        #expect(world.notifier.errors.isEmpty)
        #expect(coordinator.history.record(id: record.id)?.byteCount == original.count)
    }

    /// recording-r1:271 (:285), its second sentence (the first is
    /// `CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey`); recording-r1:330 (:376); the
    /// Delete leg of recording-r1:296 (:328), in part. Delete while Clop holds a recording's request: the card leaves
    /// `Optimizing…` and Delete finishes before Clop answers; Clop's late movie is removed, so `tmp/Clop` is empty,
    /// nothing uploads and no counter is drawn. The next two recordings take the next two counters, and `tmp/Clop` is
    /// empty after each optimised upload. Stays: recording-r1:296, the real container's `tmp/Clop` and the launch
    /// sweep of it (`TMPDIRS`).
    @Test func deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        useCounterTemplate()
        world.clop.answers = [.hold, .smallerMovie(byteCount: 2), .smallerMovie(byteCount: 2)]
        let coordinator = world.makeCoordinator()
        let deleted = try addPendingRecording(to: coordinator, byteCount: 3)
        let next = try addPendingRecording(to: coordinator, byteCount: 3)
        let third = try addPendingRecording(to: coordinator, byteCount: 3)
        let file = try #require(deleted.fileURL)
        let counter = world.settings.currentCounter

        coordinator.retryUpload(recordID: deleted.id)
        try await eventually { world.clop.isHolding }
        #expect(world.clop.requests == [.video(file, duration: 10)])
        #expect(coordinator.optimizingVideoIDs == [deleted.id])
        #expect(world.cards.calls.contains(.optimizing(deleted.id, true)))

        let delete = Task { await coordinator.deleteCapture(recordID: deleted.id) }
        defer { delete.cancel() }
        let deleteWatch = TaskWatch(delete)
        try await eventually { deleteWatch.hasReturned }
        #expect(world.clop.isHolding)
        #expect(world.confirm.asked.count == 1)
        #expect(coordinator.history.record(id: deleted.id) == nil)
        #expect(!exists(file))
        #expect(coordinator.optimizingVideoIDs.isEmpty)
        #expect(coordinator.uploadingIDs.isEmpty)
        #expect(coordinator.fileUploadIDs.isEmpty)
        #expect(lastOptimizing(deleted.id) == false)

        world.clop.release(.smallerMovie(byteCount: 2))
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        try await eventually { world.clop.workFiles.isEmpty }
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(world.settings.currentCounter == counter)

        coordinator.retryUpload(recordID: next.id)
        try await eventually { isUploaded(coordinator, next.id) }
        #expect(world.clop.requests.count == 2)
        #expect(coordinator.history.record(id: next.id)?.uploadedKey == "s/\(counter + 1).mp4")
        #expect(coordinator.history.record(id: next.id)?.byteCount == 2)
        #expect(world.settings.currentCounter == counter + 1)
        try await eventually { world.clop.workFiles.isEmpty }

        coordinator.retryUpload(recordID: third.id)
        try await eventually { isUploaded(coordinator, third.id) }
        #expect(world.clop.requests.count == 3)
        #expect(coordinator.history.record(id: third.id)?.uploadedKey == "s/\(counter + 2).mp4")
        #expect(world.settings.currentCounter == counter + 2)
        try await eventually { world.clop.workFiles.isEmpty }
    }

    /// phase-7-clop:44 (:46). Upload settings saved while Clop holds a PNG: the replaced lane is kept while the upload
    /// waits for Clop, the upload then finishes at the destination it started with and its URL is copied, the next
    /// capture goes to the new destination, and the old lane drains. The 65,536 px capture is the set-up the held
    /// request stands for.
    @Test func changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        let smaller = Data("clop".utf8)
        world.clop.answers = [.hold, .smaller(smaller)]
        let coordinator = world.makeCoordinator()
        let first = try addPendingImage(to: coordinator)
        coordinator.retryUpload(recordID: first.id)
        try await eventually { world.clop.isHolding }

        var moved = CoordinatorWorld.config
        moved.bucket = "other.tky.io"
        moved.publicURLTemplate = "https://other.tky.io/{key}"
        let other = FakeDestination()
        world.factory.add(other, at: ObjectLocation(config: moved))
        world.settings.s3Config = moved
        coordinator.destinationDidChange()
        #expect(coordinator.queue == nil)
        #expect(coordinator.drainingQueues.count == 1)
        try await world.clock.run(for: .seconds(1))
        #expect(coordinator.drainingQueues.count == 1)

        world.clop.release(.smaller(smaller))
        try await eventually { isUploaded(coordinator, first.id) }
        let firstURL = try #require(coordinator.history.record(id: first.id)?.uploadedURL)
        #expect(coordinator.history.record(id: first.id)?.objectLocation == world.location)
        #expect(destination.state.withLock { $0.uploads.map(\.data) } == [smaller])
        #expect(world.clipboard.copies.last == .url(firstURL))

        let second = try addPendingImage(to: coordinator)
        coordinator.retryUpload(recordID: second.id)
        try await eventually { isUploaded(coordinator, second.id) }
        #expect(coordinator.history.record(id: second.id)?.objectLocation == ObjectLocation(config: moved))
        #expect(other.state.withLock { $0.uploads.map(\.data) } == [smaller])
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
        try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
        #expect(coordinator.clopWaitsPerLane.isEmpty)
    }

    /// recording-r4:255 (:269), its first sentence; recording-r4:323 (:372); small-tweaks:15 (:18), the kept-copy
    /// variant of the optimised size. Clop's movie at the 100 MiB threshold is kept in `multipart/<id>.mp4`, not left
    /// in `tmp/Clop`; the upload fails part way; Retry resumes from the kept copy without asking Clop, the row takes
    /// Clop's size, and the copy is gone after the upload.
    @Test func aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop() async throws {
        defer { world.removeAll() }
        // Two parts for Clop's movie; the stored upload starts after the record's file was written.
        world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: MultipartPlan.maxPartSize, inFlight: 1)
        world.date = Date(timeIntervalSinceNow: 3600)
        destination.state.withLock { $0.partFailures = [2: [.httpStatus(403, body: "AccessDenied: Access Denied")]] }
        world.clop.answers = [.smallerMovie(byteCount: threshold)]
        let coordinator = world.makeCoordinator()
        let record = try addPendingRecording(to: coordinator, byteCount: 2 * threshold)
        let keptCopy = coordinator.multipartFiles.keptCopyURL(for: record.id, ext: "mp4")

        coordinator.retryUpload(recordID: record.id)
        try await eventually {
            coordinator.history.record(id: record.id)?.uploadState
                == .failed(message: "Part 2 of 2: Server returned HTTP 403: AccessDenied: Access Denied")
        }
        #expect(exists(keptCopy))
        #expect(world.clop.workFiles.isEmpty)
        #expect(coordinator.history.record(id: record.id)?.multipart?.sourcePath == keptCopy.path(percentEncoded: false))
        #expect(coordinator.history.record(id: record.id)?.multipart?.byteCount == threshold)

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }
        #expect(world.clop.requests.count == 1)
        #expect(world.clop.runningChecks == 1)
        #expect(world.logLines.contains("Upload: \(keptCopy.lastPathComponent) resumes at 1 of 2 parts"))
        #expect(destination.state.withLock { $0.creates.count } == 1)
        #expect(coordinator.history.record(id: record.id)?.byteCount == Int(threshold))
        try await eventually { !exists(keptCopy) }
    }

    /// phase-7-clop:32 (:34). Three uploads in a row with `{counter}` in the key template take counters in the order
    /// they started (the counter advanced by 3 at once), though Clop holds the second while the other two upload; the
    /// second then uploads under its own counter. The large scrolling capture is the set-up the held request stands
    /// for, and the world's `currentCounter` is what `defaults read … captureCounter` reads.
    @Test func threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        useCounterTemplate()
        world.clop.answers = [.smaller(Data("a".utf8)), .hold, .smaller(Data("c".utf8))]
        let coordinator = world.makeCoordinator()
        let a = try addPendingImage(to: coordinator)
        let b = try addPendingImage(to: coordinator)
        let c = try addPendingImage(to: coordinator)
        let n = world.settings.currentCounter

        coordinator.retryUpload(recordID: a.id)
        coordinator.retryUpload(recordID: b.id)
        coordinator.retryUpload(recordID: c.id)
        #expect(world.settings.currentCounter == n + 3)
        #expect(world.clop.runningChecks == 3)

        try await eventually { world.clop.isHolding }
        try await eventually { isUploaded(coordinator, a.id) && isUploaded(coordinator, c.id) }
        #expect(coordinator.history.record(id: a.id)?.uploadedKey == "s/\(n + 1).png")
        #expect(coordinator.history.record(id: c.id)?.uploadedKey == "s/\(n + 3).png")
        #expect(coordinator.history.record(id: b.id)?.uploadState == .uploading(fraction: 0))
        #expect(Set(destination.state.withLock { $0.attemptKeys }) == ["s/\(n + 1).png", "s/\(n + 3).png"])

        world.clop.release(.smaller(Data("b".utf8)))
        try await eventually { isUploaded(coordinator, b.id) }
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        #expect(coordinator.history.record(id: b.id)?.uploadedKey == "s/\(n + 2).png")
        #expect(world.clop.requests.count == 3)
        #expect(destination.state.withLock { $0.uploads.count } == 3)
        #expect(world.settings.currentCounter == n + 3)
    }

    /// phase-7-clop:29 (:31). An upload-only capture's upload through Clop fails: while Clop works, `pending/<id>.png`
    /// is the captured PNG, and after the failure it is still there at the captured size, not Clop's, and the record
    /// keeps the captured size. The success leg, the object optimised, is
    /// `turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext`. Entered at `finishSave`, the tail
    /// `save(_:intent:)` shares, since a `CaptureResult` needs an `SCDisplay` or `SCWindow`.
    @Test func aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let file = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .uploading(fraction: 0), byteCount: png.count)
        world.clop.answers = [.hold]
        destination.state.withLock {
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
        }
        let clopBytes = Data("clop".utf8)

        await coordinator.finishSave(record, image: nil, scale: 1, captureDisplayID: 1, notConfiguredWarning: nil,
                                     showsCard: false, upload: coordinator.makeDestination(), payload: { .data(png) },
                                     notification: .none)
        try await eventually { world.clop.isHolding }
        #expect(world.clop.requests == [.png(png)])
        #expect(try Data(contentsOf: file) == png)
        #expect(coordinator.history.record(id: id)?.fileURL == file)
        #expect(coordinator.history.record(id: id)?.fileIsTemporary == true)
        #expect(coordinator.history.record(id: id)?.byteCount == png.count)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)

        world.clop.release(.smaller(clopBytes))
        try await eventually { coordinator.history.record(id: id)?.isFailed == true }
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        #expect(coordinator.history.record(id: id)?.uploadState
            == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied"))
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
        #expect(destination.state.withLock { $0.uploads }.isEmpty)
        #expect(exists(file))
        #expect(try Data(contentsOf: file) == png)
        #expect(coordinator.history.record(id: id)?.byteCount == png.count)
        #expect(world.notifier.errors.last?.title == "Upload failed")
    }

    /// phase-7-clop:41 (:43). Delete while Clop holds an image's request cancels at once: the alert is asked, the
    /// capture leaves history, its pending file goes and the card closes before Clop answers, and Clop's late answer
    /// uploads nothing. The 65,536 px capture is the set-up the held request stands for.
    @Test func deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        world.clop.answers = [.hold]
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let pending = try #require(record.fileURL)

        coordinator.retryUpload(recordID: record.id)
        try await eventually { world.clop.isHolding }
        let uploading = try #require(coordinator.history.record(id: record.id))
        let delete = Task { await coordinator.deleteCapture(recordID: record.id) }
        defer { delete.cancel() }
        let deleteWatch = TaskWatch(delete)
        try await eventually { deleteWatch.hasReturned }

        #expect(world.clop.isHolding)
        #expect(world.confirm.asked == [.delete(uploading)])
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(!exists(pending))
        #expect(coordinator.optimisingIDs[record.id] == nil)
        #expect(coordinator.uploadingIDs.isEmpty)
        #expect(world.cards.closes == [.deleted])

        world.clop.release(.smaller(Data("x".utf8)))
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(await coordinator.queue?.queue.isIdle == true)
        #expect(!coordinator.isUploading)
    }

    /// phase-7-clop:42 (:44). Delete while Clop holds a save-folder capture whose file cannot be removed: the second
    /// alert, declined, keeps the record, which reads `Upload cancelled.` on the card, and Clop's late answer uploads
    /// nothing. Retry then uploads once, one new object under a new counter; Delete again with Remove accepted drops
    /// the record, deletes that object and leaves the file. The failed removal is a read-only save folder, standing
    /// for the line's save-folder change in Settings > General.
    @Test func aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        useCounterTemplate()
        let second = Data("second".utf8)
        world.clop.answers = [.hold, .smaller(second)]
        world.confirm.answers = [true, false]
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record = try addSavedImage(to: coordinator, in: folder)
        let file = try #require(record.fileURL)
        let n = world.settings.currentCounter
        // Reads still work; the removal throws, which is what brings the second alert (+Delete:76-88).
        let folderPath = folder.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folderPath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderPath) }

        coordinator.retryUpload(recordID: record.id)
        try await eventually { world.clop.isHolding }
        let delete = Task { await coordinator.deleteCapture(recordID: record.id) }
        defer { delete.cancel() }
        let deleteWatch = TaskWatch(delete)
        try await eventually { deleteWatch.hasReturned }
        try #require(world.confirm.asked.count == 2)
        if case .removeFromHistory(let message, let informativeText) = world.confirm.asked[1] {
            #expect(message.hasPrefix(CaptureDeletion.fileFailureMessage(reason: "")))
            #expect(informativeText == CaptureDeletion.fileFailureText)
        } else {
            Issue.record("The second alert is \(world.confirm.asked[1]), not Remove from history")
        }
        #expect(coordinator.history.record(id: record.id)?.uploadState == .failed(message: "Upload cancelled."))
        #expect(world.cards.updates(for: record.id).last == .failed(message: "Upload cancelled."))
        #expect(exists(file))
        #expect(coordinator.uploadingIDs.isEmpty)
        #expect(world.clop.isHolding)

        world.clop.release(.smaller(Data("first".utf8)))
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }
        #expect(destination.state.withLock { $0.uploads.map(\.data) } == [second])
        #expect(destination.state.withLock { $0.attemptKeys } == ["s/\(n + 2).png"])
        #expect(coordinator.history.record(id: record.id)?.uploadedKey == "s/\(n + 2).png")
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)

        world.confirm.answers = [true, true]
        let again = Task { await coordinator.deleteCapture(recordID: record.id) }
        defer { again.cancel() }
        let againWatch = TaskWatch(again)
        try await eventually { againWatch.hasReturned }
        #expect(world.confirm.asked.count == 4)
        #expect(coordinator.history.record(id: record.id) == nil)
        #expect(exists(file))
        #expect(destination.state.withLock { $0.deletedKeys } == ["s/\(n + 2).png"])
    }

    /// phase-7-clop:43 (:45). With the file removal failing as in
    /// `aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce`, Delete is declined
    /// at the second alert and Retry comes while Clop still holds the first attempt: exactly one object is uploaded,
    /// from the second attempt under its own new counter, and the first attempt's late answer sends nothing.
    @Test func aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        useCounterTemplate()
        let second = Data("second".utf8)
        world.clop.answers = [.hold, .smaller(second)]
        world.confirm.answers = [true, false]
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record = try addSavedImage(to: coordinator, in: folder)
        let file = try #require(record.fileURL)
        let n = world.settings.currentCounter
        let folderPath = folder.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folderPath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderPath) }

        coordinator.retryUpload(recordID: record.id)
        try await eventually { world.clop.isHolding }
        let delete = Task { await coordinator.deleteCapture(recordID: record.id) }
        defer { delete.cancel() }
        let deleteWatch = TaskWatch(delete)
        try await eventually { deleteWatch.hasReturned }
        #expect(world.confirm.asked.count == 2)
        #expect(coordinator.history.record(id: record.id)?.uploadState == .failed(message: "Upload cancelled."))
        #expect(exists(file))
        #expect(world.clop.isHolding)

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }
        #expect(world.clop.requests.count == 2)
        #expect(world.clop.isHolding)
        #expect(destination.state.withLock { $0.uploads.map(\.data) } == [second])
        #expect(destination.state.withLock { $0.attemptKeys } == ["s/\(n + 2).png"])
        #expect(coordinator.history.record(id: record.id)?.uploadedKey == "s/\(n + 2).png")

        world.clop.release(.smaller(Data("first".utf8)))
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
        #expect(destination.state.withLock { $0.uploads.map(\.data) } == [second])
        #expect(world.clipboard.copies.count == 1)
        #expect(coordinator.history.record(id: record.id)?.uploadedKey == "s/\(n + 2).png")
    }

    /// recording-r1:296 (:328), in part: after a failed upload. A recording's upload of Clop's movie fails: `tmp/Clop`
    /// is empty afterwards and the record's file is untouched; Retry asks Clop again from the original, not from the
    /// first movie, sends the new movie, and `tmp/Clop` is empty after that optimised upload too. The Delete leg is
    /// `deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap`. Stays: the real container's
    /// `tmp/Clop` and the launch sweep of it at `start()` (`TMPDIRS`).
    @Test func aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal() async throws {
        defer { world.removeAll() }
        world.clop.answers = [.smallerMovie(byteCount: 2), .smallerMovie(byteCount: 2)]
        destination.state.withLock {
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
        }
        let coordinator = world.makeCoordinator()
        let record = try addPendingRecording(to: coordinator, byteCount: 3)
        let file = try #require(record.fileURL)

        coordinator.retryUpload(recordID: record.id)
        try await eventually {
            coordinator.history.record(id: record.id)?.uploadState
                == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied")
        }
        try await eventually { world.clop.workFiles.isEmpty }
        #expect(world.clop.requests == [.video(file, duration: 10)])
        let failedAttempts = destination.state.withLock { $0.attemptFiles }
        #expect(failedAttempts.count == 1)
        #expect(failedAttempts.first?.deletingLastPathComponent().lastPathComponent == "Clop")
        #expect(exists(file))

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }
        try await eventually { world.clop.workFiles.isEmpty }
        #expect(world.clop.requests == [.video(file, duration: 10), .video(file, duration: 10)])
        #expect(world.clop.runningChecks == 2)
        #expect(destination.state.withLock { $0.fileUploads.count } == 1)
        let attempts = destination.state.withLock { $0.attemptFiles }
        #expect(attempts.count == 2)
        #expect(attempts.first != attempts.last)
        #expect(coordinator.history.record(id: record.id)?.byteCount == 2)
    }

    /// recording-r1:297 (:329). A recording with Clop off, and with Clop on but not running, uploads its own file: Clop
    /// is never asked, the card never says `Optimizing…`, and only the not-running case logs its `Clop:` line. No
    /// error is posted, and TidyShot never launches Clop (`ClopApp` has no launch call).
    @Test(arguments: [(false, true), (true, false)])
    func aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting: Bool,
                                                                                 running: Bool) async throws {
        defer { world.removeAll() }
        world.settings.optimiseWithClop = setting
        world.clop.isRunning = running
        let coordinator = world.makeCoordinator()
        let record = try addPendingRecording(to: coordinator, byteCount: 3)
        let pending = try #require(record.fileURL)

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }

        #expect(world.clop.requests.isEmpty)
        #expect(world.clop.runningChecks == (setting ? 1 : 0))
        #expect(world.logLines.filter { $0.hasPrefix("Clop:") }
            == (setting ? ["Clop: Clop is not running, uploading the original"] : []))
        #expect(!world.cards.calls.contains(.optimizing(record.id, true)))
        #expect(coordinator.optimizingVideoIDs.isEmpty)
        let sent = destination.state.withLock { $0.fileUploads.map(\.url.lastPathComponent) }
        #expect(sent == [pending.lastPathComponent])
        #expect(world.notifier.errors.isEmpty)
    }

    /// recording-r2:275 (:291), in part: the GIF half. With Clop on, a GIF uploads its own file as `image/gif`, never
    /// asks whether Clop runs and never shows `Optimizing…`; `Clop: GIFs are not sent to Clop` is logged once per
    /// launch (once for two GIFs, once more after a relaunch) and never with Clop off. Stays: `cmp` of the bucket's
    /// object against the saved file and `grep` of the real `tidyshot.err`, by hand. The MP4 half is
    /// `anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie`; the kind rule is
    /// `CaptureRecordTests.onlyAGIFIsNotSentToClop`.
    @Test func aGIFUploadsAsMadeWithOneClopLinePerLaunch() async throws {
        defer { world.removeAll() }
        let line = "Clop: GIFs are not sent to Clop"
        let first = world.makeCoordinator()
        let gif1 = try addGIF(to: first)
        let pending1 = try #require(gif1.fileURL)

        first.retryUpload(recordID: gif1.id)
        try await eventually { isUploaded(first, gif1.id) }
        #expect(world.logLines.filter { $0 == line }.count == 1)
        #expect(destination.state.withLock { $0.fileUploads.map(\.contentType) } == ["image/gif"])
        let sent = destination.state.withLock { $0.fileUploads.map(\.url.lastPathComponent) }
        #expect(sent == [pending1.lastPathComponent])
        #expect(!world.cards.calls.contains(.optimizing(gif1.id, true)))
        #expect(world.clop.runningChecks == 0)
        #expect(world.clop.requests.isEmpty)

        let gif2 = try addGIF(to: first)
        first.retryUpload(recordID: gif2.id)
        try await eventually { isUploaded(first, gif2.id) }
        #expect(world.logLines.filter { $0 == line }.count == 1)

        // The relaunch: a second coordinator over the same world; the first is not called again.
        let second = world.makeCoordinator()
        let gif3 = try addGIF(to: second)
        second.retryUpload(recordID: gif3.id)
        try await eventually { isUploaded(second, gif3.id) }
        #expect(world.logLines.filter { $0 == line }.count == 2)

        world.settings.optimiseWithClop = false
        let third = world.makeCoordinator()
        let gif4 = try addGIF(to: third)
        third.retryUpload(recordID: gif4.id)
        try await eventually { isUploaded(third, gif4.id) }
        #expect(world.logLines.filter { $0 == line }.count == 2)
        #expect(destination.state.withLock { $0.fileUploads.count } == 4)
        #expect(world.clop.runningChecks == 0)
        #expect(world.clop.requests.isEmpty)
    }

    /// recording-r2:275 (:291), in part: the MP4 half; small-tweaks:15 (:18), the optimised size. With Clop on and
    /// running, an MP4 recording shows `Optimizing…` while Clop works, then uploads Clop's movie, not its own file, and
    /// the row takes the movie's size; `tmp/Clop` is empty afterwards. Stays: recording-r2:275, `cmp` against the
    /// bucket's object and `grep` of the real stderr, by hand; real Clop making the object smaller is the line's
    /// set-up.
    @Test func anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie() async throws {
        defer { world.removeAll() }
        defer { world.clop.release(FakeClop.cancelledAnswer) }
        world.clop.answers = [.hold]
        let coordinator = world.makeCoordinator()
        let record = try addPendingRecording(to: coordinator, byteCount: 3)
        let pending = try #require(record.fileURL)

        coordinator.retryUpload(recordID: record.id)
        try await eventually { world.clop.isHolding }
        #expect(coordinator.optimizingVideoIDs == [record.id])
        #expect(world.cards.calls.contains(.optimizing(record.id, true)))
        #expect(coordinator.history.record(id: record.id)?.uploadState == .uploading(fraction: 0))
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)

        world.clop.release(.smallerMovie(byteCount: 2))
        try await eventually { isUploaded(coordinator, record.id) }
        #expect(coordinator.optimizingVideoIDs.isEmpty)
        #expect(lastOptimizing(record.id) == false)
        let sent = destination.state.withLock { $0.fileUploads.map(\.url) }
        #expect(sent.count == 1)
        #expect(sent.first?.pathExtension == "mp4")
        #expect(sent.first?.lastPathComponent != pending.lastPathComponent)
        #expect(sent.first?.deletingLastPathComponent().lastPathComponent == "Clop")
        #expect(coordinator.history.record(id: record.id)?.byteCount == 2)
        try await eventually { world.clop.workFiles.isEmpty }
    }

    /// recording-r4:255 (:269), its second sentence. Clop's movie at the keep threshold cannot be moved into a
    /// read-only `multipart/`: `Upload: Clop's copy could not be kept for resume: <error>` is logged, the job sends
    /// the throwaway copy from `tmp/Clop` in one PUT, nothing is kept, and `tmp/Clop` is empty afterwards. The first
    /// sentence is `aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop`.
    @Test func aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy() async throws {
        defer { world.removeAll() }
        // A lane threshold above Clop's movie, so the job is one PUT and writes no sidecar.
        world.multipartPlan = MultipartPlan(threshold: 1_073_741_824, partSize: 16_777_216, inFlight: 1)
        world.clop.answers = [.smallerMovie(byteCount: threshold)]
        let coordinator = world.makeCoordinator()
        let record = try addPendingRecording(to: coordinator, byteCount: 2 * threshold)
        let keptCopy = coordinator.multipartFiles.keptCopyURL(for: record.id, ext: "mp4")
        let multipart = coordinator.multipartFiles.directory
        try FileManager.default.createDirectory(at: multipart, withIntermediateDirectories: true)
        let multipartPath = multipart.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: multipartPath)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: multipartPath) }

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }

        let prefix = "Upload: Clop's copy could not be kept for resume: "
        let line = try #require(world.logLines.first { $0.hasPrefix(prefix) })
        #expect(line.count > prefix.count)
        let sent = destination.state.withLock { $0.fileUploads.map(\.url) }
        #expect(sent.count == 1)
        #expect(sent.first?.deletingLastPathComponent().lastPathComponent == "Clop")
        #expect(destination.state.withLock { $0.creates }.isEmpty)
        #expect(!exists(keptCopy))
        #expect(coordinator.history.record(id: record.id)?.byteCount == Int(threshold))
        #expect(coordinator.history.record(id: record.id)?.multipart == nil)
        try await eventually { world.clop.workFiles.isEmpty }
    }
}
