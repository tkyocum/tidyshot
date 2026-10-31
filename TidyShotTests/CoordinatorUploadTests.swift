import Foundation
import Testing
@testable import TidyShot

/// Uploads on a built coordinator, through the real `UploadQueue` over `FakeDestination` (R4 design,
/// Multipart and Resume; R1's clipboard rule; Phase 3's cancel and draining; harness design 3.2). The
/// lanes use a 1 MiB threshold and 256 KiB parts, as `UploadQueueTests` does, and never sleep.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorUploadTests {
    let world: CoordinatorWorld
    let mib: Int64 = 1_048_576

    init() throws {
        world = try CoordinatorWorld()
        world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 3)
    }

    var destination: FakeDestination { world.factory.standard }

    /// `pending/<id>.mp4`, sparse, of `byteCount` bytes.
    func pendingFile(in coordinator: AppCoordinator, id: UUID, byteCount: Int64) throws -> URL {
        let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
        try CoordinatorWorld.writeSparseFile(at: url, byteCount: byteCount)
        return url
    }

    /// A recording whose file is `file` in `pending/`, added to history: failed, so a Retry starts it.
    @discardableResult
    func addRecording(to coordinator: AppCoordinator, id: UUID, file: URL, byteCount: Int64,
                      state: CaptureRecord.UploadState = .failed(message: "Upload was interrupted."),
                      multipart: MultipartUploadState? = nil, unmutedIntervals: [MuteInterval] = []) -> CaptureRecord {
        let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                   appName: nil, uploadState: state, mediaKind: .video, durationSeconds: 10,
                                   byteCount: Int(byteCount), unmutedIntervals: unmutedIntervals, multipart: multipart)
        coordinator.history.add(record)
        return record
    }

    /// An upload-only screenshot in `pending/`, added to history.
    func addPendingImage(to coordinator: AppCoordinator,
                         state: CaptureRecord.UploadState = .failed(message: "Upload was interrupted."),
                         priorUpload: PriorUpload? = nil, uploadIsStale: Bool = false) throws -> CaptureRecord {
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: state, uploadIsStale: uploadIsStale,
                                   priorUpload: priorUpload, byteCount: png.count)
        coordinator.history.add(record)
        return record
    }

    /// A stored upload `stored-1` of `file` at `key`: the file's own size and modification date unless
    /// `byteCount` says otherwise, at the world's location unless `location` does.
    func storedState(of file: URL, key: String = "s/STORED.mp4", byteCount: Int64? = nil,
                     location: ObjectLocation? = nil,
                     startedAt: Date = Date(timeIntervalSinceNow: -60)) throws -> MultipartUploadState {
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = try #require(values.fileSize)
        let modified = try #require(values.contentModificationDate)
        return MultipartUploadState(uploadID: "stored-1", key: key, location: location ?? world.location,
                                    partSize: 262_144, byteCount: byteCount ?? Int64(size),
                                    sourceModified: modified, sourcePath: file.path(percentEncoded: false),
                                    startedAt: startedAt)
    }

    func part(_ number: Int) -> MultipartPart {
        MultipartPart(number: number, etag: "\"etag-\(number)\"", size: 262_144)
    }

    /// Parts 1 and 2 of `stored-1` in the sidecar, as an interrupted upload leaves them.
    func writeSidecar(_ coordinator: AppCoordinator, id: UUID) throws {
        try coordinator.multipartFiles.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: false,
                                                                     parts: [part(1), part(2)]), id: id)
    }

    func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
        if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
        return false
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// 17 (harness design 3.2). R4 checklist, Multipart: Retry resumes, from the sidecar's parts, with no Create, no
    /// ListParts and no counter drawn; the record stores the stored size.
    @Test func aStoredUploadWhoseSourceMatchesResumes() async throws {
        defer { world.removeAll() }
        var config = CoordinatorWorld.config
        config.keyTemplate = "s/{counter}-{random:6}"
        world.settings.s3Config = config
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        try writeSidecar(coordinator, id: id)
        // The record starts at 1 byte, so the size it ends with is the one `.uploaded` stored.
        addRecording(to: coordinator, id: id, file: file, byteCount: 1, multipart: try storedState(of: file))
        let counter = world.settings.currentCounter

        coordinator.retryUpload(recordID: id)
        try await eventually { isUploaded(coordinator, id) }

        let calls = destination.state.withLock { $0.calls }
        #expect(!calls.contains("create"))
        #expect(!calls.contains("list"))
        #expect(Set(calls.filter { $0.hasPrefix("part") }) == ["part 3", "part 4"])
        #expect(calls.last == "complete")
        #expect(coordinator.history.record(id: id)?.uploadedKey == "s/STORED.mp4")
        #expect(coordinator.history.record(id: id)?.byteCount == Int(mib))
        #expect(world.settings.currentCounter == counter)
    }

    /// 18 (harness design 3.2). R4 design, Resume: the bar is at the done fraction at once (R4 checklist, Multipart, the
    /// bar at that fraction at once). Part 3 waits, so nothing else moves the bar meanwhile.
    @Test func aResumesStartSetsTheBarAtItsDoneFraction() async throws {
        defer { world.removeAll() }
        world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 1)
        destination.state.withLock { $0.holdingPart = 3 }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        try writeSidecar(coordinator, id: id)
        addRecording(to: coordinator, id: id, file: file, byteCount: mib, multipart: try storedState(of: file))

        coordinator.retryUpload(recordID: id)
        try await eventually { coordinator.history.record(id: id)?.uploadState == .uploading(fraction: 0.5) }

        #expect(world.cards.updates(for: id).contains(.uploading(fraction: 0.5)))
        destination.releaseParts()
        try await eventually { isUploaded(coordinator, id) }
    }

    /// 19 (harness design 3.2). A retried attempt (`.started(attempt: 2)`, a single PUT's retry) is logged.
    @Test func aRetriedAttemptIsLogged() async throws {
        defer { world.removeAll() }
        destination.state.withLock {
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(503, body: "")
        }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }

        #expect(world.logLines.contains("Upload retry 2 for \(record.id)"))
    }

    /// 20 (harness design 3.2). R4 checklist, Multipart: after Settings names another bucket, `destination changed, starting
    /// again`; the old upload is aborted where it was created (twice: a 204 is repeated, test 38), and
    /// the new bucket gets a fresh upload with no abort.
    @Test func aStoredUploadAtAnotherLocationIsAbortedThereAndStartsAgain() async throws {
        defer { world.removeAll() }
        let old = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                 bucket: "old.tky.io", usePathStyle: true)
        let oldDestination = FakeDestination()
        world.factory.add(oldDestination, at: old)
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                     multipart: try storedState(of: file, location: old))

        coordinator.retryUpload(recordID: id)
        try await eventually { isUploaded(coordinator, id) }
        try await eventually { oldDestination.state.withLock { $0.aborts.count } == 2 }

        #expect(world.logLines.contains("Upload: \(file.lastPathComponent) destination changed, starting again"))
        #expect(world.factory.askedLocations.contains(old))
        #expect(oldDestination.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1", "stored-1"])
        #expect(!destination.state.withLock { $0.calls }.contains("abort"))
        #expect(destination.state.withLock { $0.calls }.first == "create")
    }

    /// 21 (harness design 3.2). R4 checklist, Multipart: after the file changed, `source changed, starting again`, and the
    /// old upload is aborted first.
    @Test func aSourceWhoseSizeChangedStartsAgainAbortingFirst() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                     multipart: try storedState(of: file, byteCount: 2 * mib))

        coordinator.retryUpload(recordID: id)
        try await eventually { isUploaded(coordinator, id) }

        #expect(world.logLines.contains("Upload: \(file.lastPathComponent) source changed, starting again"))
        #expect(Array(destination.state.withLock { $0.calls }.prefix(2)) == ["abort", "create"])
        #expect(destination.state.withLock { $0.aborts.first?.uploadID } == "stored-1")
    }

    /// 22 (harness design 3.2). A fixed key other than the stored one starts again (`key changed`).
    @Test func aDifferentFixedKeyStartsAgain() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        let record = addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                                  multipart: try storedState(of: file))
        let target = try #require(coordinator.makeDestination())

        coordinator.startUpload(recordID: id, payload: try coordinator.uploadPayload(for: record), destination: target,
                                fixedKey: "s/OTHER.mp4")
        try await eventually { isUploaded(coordinator, id) }

        #expect(world.logLines.contains("Upload: \(file.lastPathComponent) key changed, starting again"))
        #expect(destination.state.withLock { $0.creates.map(\.key) } == ["s/OTHER.mp4"])
        #expect(Array(destination.state.withLock { $0.calls }.prefix(2)) == ["abort", "create"])
    }

    /// 23 (harness design 3.2). R4 checklist, call B: a kept Clop copy older than the record's file counts as changed.
    @Test func anOutdatedKeptClopCopyCountsAsAChangedSource() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let keptCopy = coordinator.multipartFiles.keptCopyURL(for: id, ext: "mp4")
        try CoordinatorWorld.writeSparseFile(at: keptCopy, byteCount: mib)
        // Written now, after the stored upload started an hour ago: a trim since.
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                     multipart: try storedState(of: keptCopy, startedAt: Date(timeIntervalSinceNow: -3600)))

        coordinator.retryUpload(recordID: id)
        try await eventually { isUploaded(coordinator, id) }

        #expect(world.logLines.contains("Upload: \(file.lastPathComponent) source changed, starting again"))
        #expect(destination.state.withLock { $0.calls }.contains("create"))
    }

    /// 24 (harness design 3.2). R1's clipboard rule: a recording's link replaces the clipboard only while it holds what the
    /// save left there; otherwise the card says `Uploaded`.
    @Test(arguments: [false, true])
    func anUploadedRecordingReplacesTheClipboardOnlyWhileItHoldsWhatTheSaveLeft(clipboardMoved: Bool) async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
        addRecording(to: coordinator, id: id, file: file, byteCount: 3)
        coordinator.videoClipboardCounts[id] = world.clipboard.changeCount
        if clipboardMoved {
            world.clipboard.changeCount += 1
        }

        coordinator.retryUpload(recordID: id)
        try await eventually { isUploaded(coordinator, id) }

        let url = try #require(coordinator.history.record(id: id)?.uploadedURL)
        if clipboardMoved {
            #expect(world.clipboard.copies.isEmpty)
            #expect(world.notifier.calls.contains(.uploaded(url: url, copied: false)))
            #expect(coordinator.linkNotCopiedIDs.contains(id))
        } else {
            #expect(world.clipboard.copies == [.url(url)])
            #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
            #expect(!coordinator.linkNotCopiedIDs.contains(id))
        }
    }

    /// 25 (harness design 3.2). R4 checklist, Multipart: after `.uploaded`, `multipart/` holds neither the sidecar nor a kept
    /// copy; the record's state is gone and its size is the sent size.
    @Test func anUploadedResumeClearsItsStateSidecarAndKeptCopy() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        let keptCopy = coordinator.multipartFiles.keptCopyURL(for: id, ext: "mp4")
        try CoordinatorWorld.writeSparseFile(at: keptCopy, byteCount: mib)
        try writeSidecar(coordinator, id: id)
        // Started after the record's file was written: the kept copy is current. The record starts at
        // 1 byte, so the size it ends with is the one `.uploaded` stored.
        addRecording(to: coordinator, id: id, file: file, byteCount: 1,
                     multipart: try storedState(of: keptCopy, startedAt: Date(timeIntervalSinceNow: 3600)))

        coordinator.retryUpload(recordID: id)
        try await eventually { isUploaded(coordinator, id) }

        #expect(coordinator.history.record(id: id)?.multipart == nil)
        #expect(coordinator.history.record(id: id)?.byteCount == Int(mib))
        #expect(!destination.state.withLock { $0.calls }.contains("create"))
        try await eventually {
            !exists(coordinator.multipartFiles.sidecarURL(for: id)) && !exists(keptCopy)
        }
    }

    /// 26 (harness design 3.2). Spec 2.9: an upload-only screenshot's pending file moves into its drag folder under the key's
    /// name while its card shows; with no card it is removed. Either way the record has no file.
    @Test(arguments: [true, false])
    func anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard(cardShowing: Bool) async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let pending = try #require(record.fileURL)
        if cardShowing {
            world.cards.showing.insert(record.id)
        }

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }

        let uploaded = try #require(coordinator.history.record(id: record.id))
        #expect(uploaded.fileURL == nil)
        #expect(!exists(pending))
        let dragged = coordinator.dragFiles.stagedFile(id: record.id)
        if cardShowing {
            let key = try #require(uploaded.uploadedKey)
            #expect(dragged?.lastPathComponent == key.split(separator: "/").last.map(String.init))
            #expect(world.cards.dragFiles(for: record.id).map { $0?.lastPathComponent } == [dragged?.lastPathComponent])
        } else {
            #expect(dragged == nil)
            #expect(world.cards.dragFiles(for: record.id).isEmpty)
        }
    }

    /// 27 (harness design 3.2). A failed upload with no link is marked failed and posts `Upload failed`; one over a link goes
    /// back to the link, keeps `uploadIsStale`, and posts `Not uploaded` with the replace's text.
    @Test func aFailedUploadMarksTheRecordOrReturnsItToItsLink() async throws {
        defer { world.removeAll() }
        destination.state.withLock {
            $0.failuresRemaining = 2
            $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
        }
        let coordinator = world.makeCoordinator()
        let message = "Server returned HTTP 403: AccessDenied: Access Denied"

        let plain = try addPendingImage(to: coordinator)
        coordinator.retryUpload(recordID: plain.id)
        try await eventually { coordinator.history.record(id: plain.id)?.uploadState == .failed(message: message) }
        #expect(world.notifier.calls.contains(.error(title: "Upload failed", message: message)))

        let prior = PriorUpload(url: URL(string: "https://snap.tky.io/s/OLD.png")!, key: "s/OLD.png",
                                location: world.location, isReplace: false)
        let linked = try addPendingImage(to: coordinator, state: .uploading(fraction: 0), priorUpload: prior,
                                         uploadIsStale: true)
        coordinator.startUpload(recordID: linked.id, payload: try coordinator.uploadPayload(for: linked),
                                destination: try #require(coordinator.makeDestination()))
        try await eventually {
            coordinator.history.record(id: linked.id)?.uploadState == .uploaded(url: prior.url, key: prior.key)
        }
        #expect(coordinator.history.record(id: linked.id)?.uploadIsStale == true)
        #expect(world.notifier.calls.contains(.error(title: "Not uploaded", message: EditorUploadPlan.failedReplaceMessage)))
    }

    /// 28 (harness design 3.2). Phase 3's cancel: during the resume and size wait, the token is taken, the record reads
    /// `Upload cancelled.`, and nothing reaches the queue.
    @Test func cancellingDuringTheWaitEndsTheUploadWithoutTheQueue() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
        addRecording(to: coordinator, id: id, file: file, byteCount: 3)

        coordinator.retryUpload(recordID: id)
        #expect(coordinator.optimisingIDs[id] != nil)
        await coordinator.cancelUpload(of: id)

        #expect(coordinator.optimisingIDs[id] == nil)
        #expect(coordinator.history.record(id: id)?.uploadState == .failed(message: "Upload cancelled."))
        #expect(!coordinator.uploadingIDs.contains(id))
        try await eventually { coordinator.clopWaitsPerLane.isEmpty }
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        // The lane exists (`startUpload` makes it before the wait) but was never given the job, so the
        // cancel ended before `queue.cancel`; a queue cancel of a job it does not hold changes nothing.
        #expect(await coordinator.queue?.queue.isIdle == true)
        #expect(coordinator.fileUploadIDs.isEmpty)
    }

    /// 29 (harness design 3.2). Phase 3's cancel: a job in flight is cancelled in its lane, and the record keeps the key the
    /// job reserved, so Delete removes it too.
    @Test func cancellingAQueuedJobKeepsItsReservedKey() async throws {
        defer { world.removeAll() }
        destination.state.withLock { $0.blockingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
        addRecording(to: coordinator, id: id, file: file, byteCount: 3)

        coordinator.retryUpload(recordID: id)
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
        await coordinator.cancelUpload(of: id)

        let key = try #require(destination.state.withLock { $0.attemptKeys.first })
        let record = try #require(coordinator.history.record(id: id))
        #expect(record.pendingObjectKey == key)
        #expect(record.objectLocation == world.location)
        #expect(record.uploadState == .failed(message: "Upload cancelled."))
        #expect(coordinator.fileUploadIDs.isEmpty)
        #expect(coordinator.uploadingIDs.isEmpty)
    }

    /// 30 (harness design 3.2). Phase 3's draining: a lane the Upload tab replaced stays in `drainingQueues` while it has work,
    /// polling every 500 ms on the clock, and goes once it is idle.
    @Test func aReplacedLaneDrainsUntilIdle() async throws {
        defer { world.removeAll() }
        destination.state.withLock { $0.blockingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
        addRecording(to: coordinator, id: id, file: file, byteCount: 3)
        coordinator.retryUpload(recordID: id)
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        coordinator.destinationDidChange()
        #expect(coordinator.queue == nil)
        #expect(coordinator.drainingQueues.count == 1)
        try await world.clock.run(for: .seconds(1))
        #expect(coordinator.drainingQueues.count == 1)

        await coordinator.cancelUpload(of: id)
        try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
        #expect(coordinator.drainingQueues.isEmpty)
    }

    /// 31 (harness design 3.2). A Retry of a record being trimmed says why and reads no destination; of a record already
    /// uploading, nothing.
    @Test func aRetryOfATrimmingOrUploadingRecordDoesNothingButSay() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let trimming = try addPendingImage(to: coordinator)
        let uploading = try addPendingImage(to: coordinator)
        coordinator.trimmingIDs.insert(trimming.id)
        coordinator.uploadingIDs.insert(uploading.id)

        coordinator.retryUpload(recordID: trimming.id)
        coordinator.retryUpload(recordID: uploading.id)

        #expect(world.notifier.calls == [.error(title: "Not uploaded", message: "This capture is being trimmed.")])
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(coordinator.queue == nil)
    }

    /// 32 (harness design 3.2). Retry Failed Uploads with no credentials says so once; with them, every failed record goes.
    @Test func retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem() async throws {
        defer { world.removeAll() }
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let coordinator = world.makeCoordinator()
        let first = try addPendingImage(to: coordinator)
        let second = try addPendingImage(to: coordinator)

        coordinator.retryFailedUploads()
        #expect(world.notifier.calls == [.error(title: "Upload not configured",
                                                 message: "Set up a destination in Settings > Upload, then retry.")])
        #expect(coordinator.uploadingIDs.isEmpty)

        try world.credentials.save(CoordinatorWorld.awsCredentials, account: KeychainCredentialStore.defaultAccount)
        coordinator.retryFailedUploads()
        #expect(coordinator.uploadingIDs == [first.id, second.id])
        try await eventually { isUploaded(coordinator, first.id) && isUploaded(coordinator, second.id) }
    }

    /// 33 (harness design 3.2). `Upload not configured` posts once per launch, that is once per coordinator.
    @Test func notConfiguredIsPostedOncePerCoordinator() {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        coordinator.warnUploadNotConfiguredOnce("first")
        coordinator.warnUploadNotConfiguredOnce("second")
        let relaunched = world.makeCoordinator()
        relaunched.warnUploadNotConfiguredOnce("third")

        #expect(world.notifier.calls == [.error(title: "Upload not configured", message: "first"),
                                         .error(title: "Upload not configured", message: "third")])
    }

    /// 34 (harness design 3.2). R2's privacy rule's backstop: `startUpload` of a recording marked `Sound not muted` logs and
    /// changes nothing.
    @Test func aRefusedRecordIsLoggedAndLeftAlone() throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
        let record = addRecording(to: coordinator, id: id, file: file, byteCount: 3,
                                  unmutedIntervals: [MuteInterval(start: 0, end: 1)])
        let target = try #require(coordinator.makeDestination())

        coordinator.startUpload(recordID: id, payload: .file(file, scope: nil), destination: target)

        #expect(world.logLines == ["Upload: refused for \(file.lastPathComponent): \(CaptureRecord.soundNotMutedBody)"])
        #expect(coordinator.history.record(id: id) == record)
        #expect(coordinator.uploadingIDs.isEmpty)
        #expect(coordinator.queue == nil)
    }

    /// phase-2 :39. While an upload runs, the card is pushed `.uploading` with a fraction between 0 and 1, then
    /// `.uploaded`. A recording in parts with part 3 held, so the bar has moved and nothing ends the upload
    /// before the test has seen it (D8). How the ring draws the fraction is
    /// `QuickAccessModelTests.uploadingShowsTheFraction`.
    @Test func anUploadShowsItsFractionOnTheCardThenUploaded() async throws {
        defer { world.removeAll() }
        world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 1)
        destination.state.withLock { $0.holdingPart = 3 }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        addRecording(to: coordinator, id: id, file: file, byteCount: mib)

        coordinator.retryUpload(recordID: id)
        try await eventually {
            world.cards.updates(for: id).contains { state in
                if case .uploading(let fraction) = state { return fraction > 0 && fraction < 1 }
                return false
            }
        }
        destination.releaseParts()
        try await eventually { isUploaded(coordinator, id) }

        let uploaded = try #require(coordinator.history.record(id: id)?.uploadState)
        let updates = world.cards.updates(for: id)
        #expect(updates.first == .uploading(fraction: 0))
        #expect(updates.last == uploaded)
    }

    /// phase-2 :49, recording-r1 :279. Retry succeeds and copies the URL, and a screenshot's URL replaces the
    /// clipboard even after something else was copied meanwhile.
    @Test(arguments: [false, true])
    func aScreenshotsURLReplacesTheClipboardEvenAfterACopyElsewhere(clipboardMoved: Bool) async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        if clipboardMoved {
            world.clipboard.changeCount += 1
        }

        coordinator.retryUpload(recordID: record.id)
        try await eventually { isUploaded(coordinator, record.id) }

        let url = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
        #expect(world.clipboard.copies == [.url(url)])
        #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
    }

    /// phase-3 :46, small-tweaks :19. An upload-only screenshot whose upload fails reads failed and keeps
    /// `pending/<id>.png` and its size; Retry Failed Uploads sends it, and the pending file goes.
    @Test func aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt() async throws {
        defer { world.removeAll() }
        destination.state.withLock {
            $0.failuresRemaining = 1
            $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
        }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        let pending = try #require(record.fileURL)
        let size = try #require(record.byteCount)

        coordinator.retryUpload(recordID: record.id)
        try await eventually {
            coordinator.history.record(id: record.id)?.uploadState
                == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied")
        }
        #expect(coordinator.history.record(id: record.id)?.byteCount == size)
        #expect(exists(pending))

        coordinator.retryFailedUploads()
        try await eventually { isUploaded(coordinator, record.id) }
        #expect(!exists(pending))
        #expect(coordinator.history.record(id: record.id)?.fileURL == nil)
    }

    /// phase-3 :59. A retried upload lands under the capture's own date, with a counter drawn when the retry
    /// starts; an upload-only capture taken while no destination existed gets a real counter, not 0, when
    /// it is retried.
    @Test func aRetryIsNamedForTheCapturesDateWithANewlyDrawnCounter() async throws {
        defer { world.removeAll() }
        var config = CoordinatorWorld.config
        config.keyTemplate = "{date}/{counter}"
        world.settings.s3Config = config
        let coordinator = world.makeCoordinator()
        let taken = Date(timeIntervalSinceNow: -3 * 86_400)
        let day = TemplateExpander().expand("{date}", context: TemplateContext(date: taken), style: .objectKey)
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let oldID = UUID()
        let oldFile = try coordinator.pendingFiles.write(png, id: oldID, ext: "png")
        coordinator.history.add(CaptureRecord(id: oldID, timestamp: taken, fileURL: oldFile, fileIsTemporary: true,
                                              pixelWidth: 4, pixelHeight: 2, appName: nil,
                                              uploadState: .failed(message: "Upload was interrupted.")))
        let before = world.settings.currentCounter

        coordinator.retryUpload(recordID: oldID)
        try await eventually { isUploaded(coordinator, oldID) }
        #expect(coordinator.history.record(id: oldID)?.uploadedKey == "\(day)/\(before + 1).png")
        #expect(world.settings.currentCounter == before + 1)

        // Taken while no destination was set up: its retry fails as not configured, then, once
        // credentials exist, draws a counter.
        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        let notConfigured = UploadError.notConfigured.localizedDescription
        let waiting = try addPendingImage(to: coordinator, state: .failed(message: notConfigured))
        coordinator.retryUpload(recordID: waiting.id)
        #expect(coordinator.history.record(id: waiting.id)?.uploadState == .failed(message: notConfigured))
        try world.credentials.save(CoordinatorWorld.awsCredentials, account: KeychainCredentialStore.defaultAccount)
        coordinator.retryUpload(recordID: waiting.id)
        try await eventually { isUploaded(coordinator, waiting.id) }
        let key = try #require(coordinator.history.record(id: waiting.id)?.uploadedKey)
        #expect(key.hasSuffix("/\(before + 2).png"))
        #expect(!key.hasSuffix("/0.png"))
    }

    /// recording-r4 :352 (call 9). A resumed template upload whose key another capture took (the key holds an
    /// object of another size) starts again under a new key named with a counter of 0, and draws no counter.
    @Test func aResumedTemplateJobWhoseKeyIsTakenRedrawsItWithCounterZero() async throws {
        defer { world.removeAll() }
        var config = CoordinatorWorld.config
        config.keyTemplate = "s/{counter}-{random:6}"
        world.settings.s3Config = config
        destination.state.withLock { $0.objectSizes["s/STORED.mp4"] = 5 }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
        try writeSidecar(coordinator, id: id)
        addRecording(to: coordinator, id: id, file: file, byteCount: mib, multipart: try storedState(of: file))
        let counter = world.settings.currentCounter

        coordinator.retryUpload(recordID: id)
        try await eventually { isUploaded(coordinator, id) }

        let key = try #require(coordinator.history.record(id: id)?.uploadedKey)
        #expect(key.hasPrefix("s/0-"))
        #expect(world.logLines.contains("Upload: \(file.lastPathComponent) key taken, starting again"))
        #expect(world.settings.currentCounter == counter)
    }

    /// phase-3 :63. Forget Credentials while an upload runs: that upload still finishes and copies its URL, the
    /// menu bar icon (`isUploading`) goes back, and the replaced lane drains.
    @Test func forgettingCredentialsMidUploadLetsThatUploadFinish() async throws {
        defer { world.removeAll() }
        destination.state.withLock { $0.holdingUploadsRemaining = 1 }
        let coordinator = world.makeCoordinator()
        let record = try addPendingImage(to: coordinator)
        coordinator.retryUpload(recordID: record.id)
        try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

        try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
        coordinator.destinationDidChange()
        // A held upload finishes on its release even when cancelled, and the queue then reports it uploaded, so
        // only the fake's cancel count shows that Forget Credentials left the upload running. A cancel the
        // queue (an actor) started would land after this call returns, so the check waits for started work
        // while the upload is still held, then releases it (D31).
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(destination.state.withLock { $0.heldUploadCancellations } == 0)
        #expect(coordinator.uploadingIDs.contains(record.id))
        destination.releaseUploads()
        try await eventually { isUploaded(coordinator, record.id) }
        #expect(destination.state.withLock { $0.heldUploadCancellations } == 0)
        let url = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
        #expect(world.clipboard.copies.last == .url(url))
        #expect(!coordinator.isUploading)
        try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
    }

    /// phase-4a :126, phase-4a :128. Upload as New sends the capture under a new template key, copies the new link
    /// and deletes the old object; the same after an interrupted replace read back at a relaunch, whose link
    /// is its prior upload.
    @Test(arguments: [false, true])
    func uploadAsNewCopiesTheNewLinkAndDeletesTheOldObject(afterAnInterruptedReplace: Bool) async throws {
        defer { world.removeAll() }
        let first = world.makeCoordinator()
        let oldURL = URL(string: "https://snap.tky.io/s/OLD.png")!
        let record: CaptureRecord
        if afterAnInterruptedReplace {
            let prior = PriorUpload(url: oldURL, key: "s/OLD.png", location: world.location, isReplace: true)
            record = try addPendingImage(to: first, state: .uploading(fraction: 0.4), priorUpload: prior,
                                         uploadIsStale: true)
        } else {
            record = try addPendingImage(to: first, state: .uploaded(url: oldURL, key: "s/OLD.png"), uploadIsStale: true)
            first.history.update(id: record.id) { $0.objectLocation = world.location }
        }
        // The relaunch: an upload that was running reads as interrupted, its link kept.
        let coordinator = world.makeCoordinator()
        coordinator.history.load()
        let current = try #require(coordinator.history.record(id: record.id))
        #expect(current.linkURL == oldURL)
        let plan = EditorUploadPlan.plan(record: current, currentLocation: world.location, others: [], asNew: true)
        #expect(plan == .newObject(supersede: ObjectRef(key: "s/OLD.png", location: world.location), notice: nil))

        let payload = try coordinator.uploadPayload(for: current)
        let target = try #require(coordinator.makeDestination())
        coordinator.startPlannedUpload(recordID: record.id, plan: plan, payload: payload, destination: target)
        try await eventually { isUploaded(coordinator, record.id) }

        let uploaded = try #require(coordinator.history.record(id: record.id))
        let newKey = try #require(uploaded.uploadedKey)
        let newURL = try #require(uploaded.uploadedURL)
        #expect(newKey != "s/OLD.png")
        #expect(destination.state.withLock { $0.uploads.map(\.key) } == [newKey])
        #expect(world.clipboard.copies.last == .url(newURL))
        try await eventually { destination.state.withLock { $0.deletedKeys } == ["s/OLD.png"] }
    }

    /// phase-4a :134. A quit during a replace leaves the record uploading; after the relaunch it reads failed and
    /// its link still copies, and Retry Failed Uploads PUTs the link's own key again with `no-cache`, so the
    /// URL is unchanged.
    @Test func anInterruptedReplaceRetriesOverItsOwnKeyAfterARelaunch() async throws {
        defer { world.removeAll() }
        let first = world.makeCoordinator()
        let oldURL = URL(string: "https://snap.tky.io/s/OLD.png")!
        let prior = PriorUpload(url: oldURL, key: "s/OLD.png", location: world.location, isReplace: true)
        let record = try addPendingImage(to: first, state: .uploading(fraction: 0.4), priorUpload: prior,
                                         uploadIsStale: true)
        let coordinator = world.makeCoordinator()
        coordinator.history.load()
        #expect(coordinator.history.record(id: record.id)?.uploadState == .failed(message: "Upload was interrupted."))
        #expect(coordinator.history.record(id: record.id)?.linkURL == oldURL)

        coordinator.retryFailedUploads()
        try await eventually { isUploaded(coordinator, record.id) }

        let last = try #require(destination.state.withLock { $0.uploads.last })
        #expect(last.key == "s/OLD.png")
        #expect(last.cacheControl == "no-cache")
        #expect(coordinator.history.record(id: record.id)?.uploadState == .uploaded(url: oldURL, key: "s/OLD.png"))
    }

    /// phase-4a :142. The first replace of a launch posts the cache note, also with Show notification off; a second
    /// replace in that launch and an upload to a new object post none; after a relaunch the next replace
    /// posts it again.
    @Test func onlyTheFirstReplaceOfALaunchPostsTheCacheNote() async throws {
        defer { world.removeAll() }
        world.settings.showNotification = false
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let note = FakeNotifier.Call.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/LINK.png")!,
                                                          key: "s/LINK.png"),
                                   objectLocation: world.location)
        var notices: [FakeNotifier.Call] {
            world.notifier.calls.filter { if case .notice = $0 { return true } else { return false } }
        }
        func upload(_ coordinator: AppCoordinator, _ plan: (CaptureRecord) -> EditorUploadPlan.Plan) async throws {
            let current = try #require(coordinator.history.record(id: record.id))
            let target = try #require(coordinator.makeDestination())
            coordinator.startPlannedUpload(recordID: record.id, plan: plan(current), payload: .data(png),
                                           destination: target)
            try await eventually { isUploaded(coordinator, record.id) && coordinator.uploadingIDs.isEmpty }
        }
        let replace: (CaptureRecord) -> EditorUploadPlan.Plan = { .replace(key: $0.uploadedKey ?? "") }

        let coordinator = world.makeCoordinator()
        coordinator.history.add(record)
        try await upload(coordinator, replace)
        #expect(notices == [note])
        try await upload(coordinator, replace)
        #expect(notices == [note])

        let relaunched = world.makeCoordinator()
        relaunched.history.load()
        try await upload(relaunched) { _ in .newObject(supersede: nil, notice: nil) }
        #expect(notices == [note])
        try await upload(relaunched, replace)
        #expect(notices == [note, note])
    }
}
