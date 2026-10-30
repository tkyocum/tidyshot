import AppKit

// Uploads: the destination, the lanes, the multipart resume decision, Clop, the size check, retry and the queue's events. Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// An upload queue and where its destination writes. Upload events carry no destination, so
    /// the location travels with the queue and is stored on the records it uploads.
    struct UploadLane {
        let queue: UploadQueue
        let location: ObjectLocation
        let keyTemplate: String
    }

    /// What `makeDestination()` returns (harness design 2.2): the destination, where it writes and its
    /// key template, from one configuration. A lane is made from it.
    struct UploadTarget {
        let destination: any Destination
        let location: ObjectLocation
        let keyTemplate: String
    }

    var isUploading: Bool { !uploadingIDs.isEmpty }

    /// Posts "Upload not configured" the first time per launch only. With the default
    /// after-capture action set to upload, a user without a destination would otherwise get a
    /// notification for every capture.
    func warnUploadNotConfiguredOnce(_ message: String) {
        guard !warnedUploadNotConfigured else { return }
        warnedUploadNotConfigured = true
        notifier.notifyError(message, title: "Upload not configured")
    }

    /// `Upload not configured`'s body when an upload the user asked for finds no destination: the
    /// editor's Upload, Save and Upload and `Upload Trimmed`.
    nonisolated static let uploadNotConfiguredBody = "Set up a destination in Settings > Upload, then upload again."

    /// The configured destination, or nil when the Upload tab is incomplete, no credentials are
    /// stored, or the keychain could not be read. "No item" is the normal not-configured case and
    /// stays silent here; any other keychain error is logged and reported once per launch.
    func makeDestination() -> UploadTarget? {
        guard let config = settings.s3Config, config.isComplete, let credentials = loadCredentials() else { return nil }
        // The live destination normalizes its configuration; the lane's location and template were read from that.
        let clean = config.normalized
        return UploadTarget(destination: environment.makeDestination(config, credentials),
                            location: ObjectLocation(config: clean), keyTemplate: clean.keyTemplate)
    }

    /// The stored credentials, or nil when there are none or the keychain could not be read
    /// (logged and reported once per launch).
    func loadCredentials() -> AWSCredentials? {
        do {
            return try storedCredentials()
        } catch {
            log("Keychain read failed: \(error.localizedDescription)")
            warnUploadNotConfiguredOnce(Self.keychainReadFailure(error))
            return nil
        }
    }

    /// The credentials in the Keychain, or nil when none (or only blank ones) are stored. Throws
    /// when the Keychain read itself fails, so a caller can tell that apart from "none saved".
    func storedCredentials() throws -> AWSCredentials? {
        guard let credentials = try credentialStore.load(account: KeychainCredentialStore.defaultAccount),
              !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            return nil
        }
        return credentials
    }

    static func keychainReadFailure(_ error: any Error) -> String {
        "Could not read S3 credentials from the keychain: \(error.localizedDescription)"
    }

    /// Called by the Upload settings tab after saving or forgetting credentials, so the next
    /// upload builds a queue from the new settings, and the shown cards' Trim items follow. The
    /// old queue is not dropped while it has work: it moves to `drainingQueues` until it reports
    /// idle, so its jobs still deliver their events (and finish against the destination they
    /// started with) and Delete can cancel them.
    func destinationDidChange() {
        // `Trim…` and `Upload Trimmed` follow whether a destination is set.
        refreshCardTrimStates()
        guard let old = queue else { return }
        queue = nil
        drainingQueues.append(old)
        let clock = environment.clock
        Task { [weak self] in
            // An upload still waiting for Clop has no job in the queue yet, so the queue can look
            // idle while one is coming. No new wait starts on a replaced lane.
            while true {
                if (self?.clopWaitsPerLane[ObjectIdentifier(old.queue)] ?? 0) == 0, await old.queue.isIdle { break }
                try? await clock.sleep(for: .milliseconds(500))
            }
            self?.drainingQueues.removeAll { $0.queue === old.queue }
        }
    }

    /// The last steps of an upload over a plan the caller has checked, shared by the editor's Upload
    /// and Trim's upload half: the record goes to uploading, with its prior link and any superseded
    /// object, in one write (`EditorUploadPlan.startingUpload`); the card and the editor show
    /// `Uploading…` now, as `startUpload` skips that refresh for a record already uploading; and the
    /// job goes through the live lane (`uploadingIDs`, progress, cancel, Delete and the menu bar
    /// icon), over the link's own key for a replace or under a new template key.
    func startPlannedUpload(recordID: UUID, plan: EditorUploadPlan.Plan, payload: UploadPayload,
                            destination: UploadTarget) {
        history.update(id: recordID) { $0 = EditorUploadPlan.startingUpload($0, plan: plan) }
        refreshOverlay(for: recordID)
        if case .replace(let key) = plan {
            startUpload(recordID: recordID, payload: payload, destination: destination, fixedKey: key)
        } else {
            startUpload(recordID: recordID, payload: payload, destination: destination)
        }
    }

    /// A queue for `target` whose events are handled with the location it uploads to.
    private func makeLane(for target: UploadTarget) -> UploadLane {
        let location = target.location
        let keyTemplate = target.keyTemplate
        let queue = UploadQueue(destination: target.destination,
                                keyNamer: ObjectKeyNamer(template: keyTemplate),
                                sleep: environment.uploadSleep,
                                plan: environment.multipartPlan,
                                store: multipartFiles,
                                now: environment.now,
                                log: environment.log,
                                events: { [weak self] event in self?.handle(event, at: location) })
        return UploadLane(queue: queue, location: location, keyTemplate: keyTemplate)
    }

    /// Enqueues `payload` for `recordID`, with the content type and extension of the record's
    /// media kind. `destination` is only used when the queue has to be created (first upload, or
    /// after the Upload tab was saved); callers read it once. With `fixedKey` the job PUTs that
    /// exact key with `Cache-Control: no-cache` and draws no counter (an editor replace, or a retry
    /// of one); otherwise the key is named from the template. A record with a stored multipart
    /// upload first decides whether it resumes (design, Resume): a resume sends the stored file
    /// with no Clop and no counter, and a start over runs as a fresh upload that aborts the stored
    /// one. With Clop on and running, Clop optimises a copy first: a PNG on its image queue, an MP4
    /// on its video queue; a GIF is never sent. A recording's file is then checked against the
    /// 625 GiB limit, and one over it is never enqueued (`refuseOversizedUpload`).
    func startUpload(recordID: UUID, payload: UploadPayload, destination: UploadTarget, fixedKey: String? = nil) {
        // Look the record up before marking it uploading, so a missing record never leaves an
        // id in `uploadingIDs` (and the menu bar icon spinning) with no job to clear it.
        guard let record = history.record(id: recordID) else { return }
        // A backstop: every caller a user drives has refused with its own notice already, and Retry
        // Failed Uploads skips the record. Nothing changes and nothing posts.
        if let refusal = Self.uploadRefusal(for: record, isTrimming: trimmingIDs.contains(recordID)) {
            log("Upload: refused for \(record.fileURL?.lastPathComponent ?? recordID.uuidString): \(refusal)")
            return
        }
        let lane = queue ?? makeLane(for: destination)
        queue = lane
        uploadingIDs.insert(recordID)
        // `save` and `editorUpload` mark their records uploading and refresh the overlay
        // themselves, so only a retry (a record in another state) needs the write and the refresh.
        if !record.isUploading {
            history.update(id: recordID) { $0.uploadState = .uploading(fraction: 0) }
            refreshOverlay(for: recordID)
        }
        // The key is named now, not at capture time: a capture taken while no destination was
        // set up, and every retry, get a counter drawn when their upload starts. The date stays
        // the capture's own, so a retried upload lands in the capture's date folder. An image's
        // counter is drawn before Clop runs, so counters follow the order uploads start. A
        // recording's is drawn just before its enqueue, after the size check, so an upload refused
        // for its size draws none. A resume draws none and names a new key, if it needs one, with
        // counter 0 (Gap 9).
        let kind = record.mediaKind
        let isFile = if case .file = payload { true } else { false }
        let settings = settings
        let drawCounter = { lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0 }
        let imageCounter = fixedKey == nil && !isFile ? drawCounter() : nil
        let makeJob: (UploadPayload, Bool) -> UploadJob = { sent, drawsCounter in
            if let fixedKey {
                return UploadJob(id: recordID, payload: sent, contentType: kind.contentType, fileExtension: kind.fileExtension,
                                 fixedKey: fixedKey, cacheControl: "no-cache")
            }
            let counter = drawsCounter ? imageCounter ?? drawCounter() : 0
            let naming = TemplateContext(date: record.timestamp, counter: counter)
            return UploadJob(id: recordID, payload: sent, contentType: kind.contentType, fileExtension: kind.fileExtension,
                             naming: naming)
        }
        if isFile {
            // The activity starts here, at the Clop request or at the enqueue when Clop is off.
            fileUploadIDs.insert(recordID)
        }
        // A GIF uploads as made, so it never asks whether Clop runs (design, GIF, Clop).
        if !kind.isSentToClop, settings.optimiseWithClop, !loggedGIFNotSentToClop {
            loggedGIFNotSentToClop = true
            log("Clop: GIFs are not sent to Clop")
        }
        // A file decides on Clop in its task, after the resume decision.
        let optimisesImage = !isFile && kind.isSentToClop && settings.optimiseWithClop && clopIsRunning()
        guard optimisesImage || isFile else {
            if case .data(let data) = payload {
                sentByteCounts[recordID] = data.count
            }
            Task { await lane.queue.enqueue(makeJob(payload, true)) }
            return
        }
        // Clop rewrites a throwaway copy: the save-folder file, the pending file and the editor's
        // file stay as captured, so a Retry optimises the original again. A recording also waits
        // for its resume decision and its size check, with Clop or without. The record stays
        // `.uploading(fraction: 0)` meanwhile, and Delete's cancel takes the token back.
        let token = UUID()
        optimisingIDs[recordID] = token
        let laneID = ObjectIdentifier(lane.queue)
        clopWaitsPerLane[laneID, default: 0] += 1
        let duration = record.durationSeconds ?? 0
        let stored = isFile ? record.multipart : nil
        let name = record.fileURL?.lastPathComponent ?? recordID.uuidString
        Task {
            defer {
                clopWaitsPerLane[laneID, default: 1] -= 1
                if clopWaitsPerLane[laneID] == 0 { clopWaitsPerLane[laneID] = nil }
            }
            // A stored multipart upload resumes or starts over, decided before Clop runs and before
            // any counter is drawn, on the file the stored upload sends.
            var step = MultipartPlan.startStep(decision: nil)
            if let stored {
                let sourceURL = URL(filePath: stored.sourcePath)
                let sourceScope = UploadPayload.scope(for: sourceURL, isTemporary: false, saveFolder: saveLocation.currentURL)
                var source = await Self.sourceAttributes(of: sourceURL, scope: sourceScope)
                // A kept Clop copy is checked against the record's own file too: a trim since the
                // upload started leaves the copy matching itself but holding the earlier trim.
                let keptCopyFolder = multipartFiles.directory
                if SaveLocation.contains(sourceURL, inFolder: keptCopyFolder) {
                    let (_, recordFileModified) = await Self.byteCount(of: payload)
                    if MultipartPlan.keptCopyIsOutdated(stored: stored, keptCopyFolder: keptCopyFolder,
                                                        recordFileModified: recordFileModified) {
                        source = nil
                    }
                }
                // Delete cancelled the upload during the reads (`cancelUpload` did the bookkeeping).
                guard optimisingIDs[recordID] == token else { return }
                let decision = MultipartPlan.resumeDecision(stored: stored, location: lane.location, fixedKey: fixedKey,
                                                            source: source)
                step = MultipartPlan.startStep(decision: decision)
                if case .startOver(let reason, _) = decision {
                    log("Upload: \(name) \(reason.logText), starting again")
                }
                if let state = step.resume {
                    guard endUploadWait(of: recordID, token: token, clopResult: nil) else { return }
                    // The stored size fitted at Create, so there is no size check.
                    var job = makeJob(.file(sourceURL, scope: sourceScope), step.drawsCounter)
                    job.multipartSource = MultipartSource(location: state.location, path: state.sourcePath,
                                                          byteCount: state.byteCount, modified: state.sourceModified)
                    job.resume = state
                    sentByteCounts[recordID] = Int(state.byteCount)
                    await lane.queue.enqueue(job)
                    return
                }
                // A destination change: the stored upload is aborted where it was created, best
                // effort and not awaited; a failure is only logged.
                if let ref = step.abortElsewhere {
                    Task { _ = await abortUploads([ref], name: name) }
                }
            }
            let optimises = !isFile || (step.runsClop && kind.isSentToClop && settings.optimiseWithClop && clopIsRunning())
            if isFile && optimises {
                optimizingVideoIDs.insert(recordID)
                refreshOverlay(for: recordID)
            }
            let (optimised, clopResult) = optimises ? await optimisedForUpload(payload, duration: duration) : (payload, nil)
            // On the bytes actually sent: Clop's result when Clop's result was accepted.
            let (sentBytes, sentModified) = await Self.byteCount(of: optimised)
            let fits = Self.fitsUpload(optimised, byteCount: sentBytes)
            // Delete cancelled the upload while Clop or the size check ran, or a newer retry is
            // waiting now. Nothing will upload this attempt's movie.
            guard endUploadWait(of: recordID, token: token, clopResult: clopResult) else { return }
            guard fits else {
                if let clopResult { removeClopFile(clopResult) }
                await refuseOversizedUpload(of: recordID)
                return
            }
            var sent = optimised
            if let clopResult {
                if MultipartPlan.standard.uses(payload: sent, byteCount: sentBytes.map(Int64.init)) {
                    // Kept in `multipart/` so a Retry, also after a relaunch, resumes from the same
                    // bytes. A rename within the container, so nothing waits between the token and
                    // the enqueue.
                    do {
                        sent = .file(try multipartFiles.keepClopCopy(clopResult, id: recordID, ext: kind.fileExtension),
                                     scope: nil)
                    } catch {
                        log("Upload: Clop's copy could not be kept for resume: \(error.localizedDescription)")
                        clopResults[recordID] = clopResult
                    }
                } else {
                    // Owned until the upload ends (the top of `handle(_:at:)`).
                    clopResults[recordID] = clopResult
                }
            }
            sentByteCounts[recordID] = sentBytes
            var job = makeJob(sent, step.drawsCounter)
            if case .file(let url, _) = sent, let sentBytes, let sentModified {
                // A rename keeps the modification date, so the kept copy has the attributes read.
                job.multipartSource = MultipartSource(location: lane.location, path: url.path(percentEncoded: false),
                                                      byteCount: Int64(sentBytes), modified: sentModified)
            }
            job.abortFirst = step.abortFirst
            await lane.queue.enqueue(job)
        }
    }

    /// The end of an upload's wait for its resume decision, Clop or its size check: true when the
    /// upload goes on. False when Delete cancelled it meanwhile (`cancelUpload` did the
    /// bookkeeping), a newer retry is waiting, or the record left history; Clop's movie is then
    /// removed, as nothing will upload it.
    private func endUploadWait(of recordID: UUID, token: UUID, clopResult: URL?) -> Bool {
        guard optimisingIDs[recordID] == token else {
            if let clopResult { removeClopFile(clopResult) }
            return false
        }
        optimisingIDs[recordID] = nil
        if optimizingVideoIDs.remove(recordID) != nil {
            refreshOverlay(for: recordID)
        }
        guard history.record(id: recordID) != nil else {
            // Removed from history meanwhile: nothing would point at the object.
            uploadingIDs.remove(recordID)
            fileUploadIDs.remove(recordID)
            if let clopResult { removeClopFile(clopResult) }
            return false
        }
        return true
    }

    /// The size of what `payload` sends, and a file's modification date: the data's length, or
    /// the file's attributes, read in a detached task holding the save folder's scope when it has
    /// one. Either is nil when it cannot be read.
    nonisolated private static func byteCount(of payload: UploadPayload) async -> (byteCount: Int?, modified: Date?) {
        switch payload {
        case .data(let data):
            return (data.count, nil)
        case .file(let url, let scope):
            return await Task.detached(priority: .utility) {
                fileAttributes(of: url, scope: scope)
            }.value
        }
    }

    /// The size and modification date of the file a stored multipart upload sends, read as
    /// `byteCount(of:)` reads them. Nil when the file is gone or either cannot be read.
    nonisolated private static func sourceAttributes(of url: URL, scope: URL?) async -> MultipartSourceAttributes? {
        let (byteCount, modified) = await Task.detached(priority: .utility) {
            fileAttributes(of: url, scope: scope)
        }.value
        guard let byteCount, let modified else { return nil }
        return MultipartSourceAttributes(byteCount: Int64(byteCount), modified: modified)
    }

    nonisolated private static func fileAttributes(of fileURL: URL, scope: URL?) -> (byteCount: Int?, modified: Date?) {
        let accessing = scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scope?.stopAccessingSecurityScopedResource() } }
        var url = fileURL
        url.removeAllCachedResourceValues()
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return (values?.fileSize, values?.contentModificationDate)
    }

    /// Whether `payload`, of `byteCount` bytes, can be uploaded: up to 625 GiB
    /// (`MultipartPlan.maxBytes`). Only a recording's file is checked. A size that cannot be read
    /// counts as fitting; the queue then reports the file unreadable.
    nonisolated private static func fitsUpload(_ payload: UploadPayload, byteCount: Int?) -> Bool {
        guard case .file = payload, let byteCount else { return true }
        return MultipartPlan.fits(byteCount: Int64(byteCount))
    }

    /// A recording over 625 GiB (design, Parts): no job, no key and no counter. The
    /// record gets `.none`, never `.failed`, which would keep offering Retry and running Clop
    /// again. Where the file is decides, not the action: a pending file moves into the save
    /// folder, asking for one when none is set, and a save-folder file stays. With no folder
    /// chosen, or a failed move, the file stays in `pending/`. `Not uploaded` always posts first.
    private func refuseOversizedUpload(of recordID: UUID) async {
        uploadingIDs.remove(recordID)
        fileUploadIDs.remove(recordID)
        guard let record = history.record(id: recordID) else { return }
        // Before the folder prompt, so nothing offers Retry while it is open.
        history.update(id: recordID) { $0.uploadState = .none }
        refreshOverlay(for: recordID)
        RecordingLog.note("Recording: \(record.fileURL?.lastPathComponent ?? recordID.uuidString) is too large to upload (over 625 GB)")

        var move: RecordingFileResult?
        var movedURL: URL?
        if RecordingSavePlan.oversizedMoves(fileIsTemporary: record.fileIsTemporary), let source = record.fileURL {
            let folder = await saveLocation.ensureFolder()
            // Deleted, or being deleted, while the prompt was open: leave the file to Delete.
            guard history.record(id: recordID) != nil, !deletingIDs.contains(recordID) else { return }
            if let folder {
                let baseName = recordingBaseName(startedAt: record.timestamp)
                let ext = record.mediaKind.fileExtension
                do {
                    movedURL = try await Task.detached(priority: .utility) {
                        try SaveLocation.moveInScoped(source, baseName: baseName, ext: ext, folder: folder)
                    }.value
                    move = .saveFolder
                } catch {
                    RecordingLog.note("Recording: \(source.lastPathComponent) could not be moved into the save folder: \(error.localizedDescription)")
                    move = .fallback(reason: error.localizedDescription)
                }
            } else {
                move = .fallback(reason: RecordingSavePlan.noFolderReason)
            }
        }
        let plan = RecordingSavePlan.oversized(fileIsTemporary: record.fileIsTemporary, move: move)
        history.update(id: recordID) { current in
            current.uploadState = plan.uploadState
            current.fileIsTemporary = plan.fileIsTemporary
            if let movedURL {
                current.fileURL = movedURL
            }
        }
        refreshOverlay(for: recordID)
        for notice in plan.notices {
            notifier.notifyError(notice.body, title: notice.title)
        }
    }

    /// Removes a movie Clop made, in `tmp/Clop` or kept in `multipart/`, detached. The launch
    /// sweeps of both folders are the backstop.
    private func removeClopFile(_ url: URL) {
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// True when a Clop build is running. Otherwise logs why the original uploads (spec 2.7).
    private func clopIsRunning() -> Bool {
        guard ClopApp.runningBundleID() != nil else {
            log("Clop: \(ClopSkipReason.notRunning.summary), uploading the original")
            return false
        }
        return true
    }

    /// What the upload sends: Clop's smaller PNG or movie, or `payload` itself with one `Clop: ` log
    /// line saying why. A movie Clop made is also returned as `clopResult`, for the caller to own.
    /// Never fails and never posts an error: a capture is never lost to Clop (spec 2.7).
    private func optimisedForUpload(_ payload: UploadPayload, duration: TimeInterval)
        async -> (payload: UploadPayload, clopResult: URL?) {
        let reason: ClopSkipReason
        switch payload {
        case .data(let data):
            switch await clopOptimiser.optimisedPNG(data) {
            case .optimised(let bytes, _, _):
                return (.data(bytes), nil)
            case .original(let skipped):
                reason = skipped
            }
        case .file(let url, let scope):
            switch await clopOptimiser.optimisedVideo(at: url, duration: duration, scope: scope) {
            case .optimised(let result, _, _):
                // In the container, so it needs no scope.
                return (.file(result, scope: nil), result)
            case .original(let skipped):
                reason = skipped
            }
        }
        log("Clop: \(reason.summary), uploading the original")
        return (payload, nil)
    }

    /// Re-reads the file and uploads it again. A record `uploadRefusal` refuses posts `Not uploaded`
    /// with the reason before the destination is read, so it is never marked failed for want of one.
    func retryUpload(recordID: UUID) {
        // Ignore a second click while the record is already in flight; otherwise it would upload twice.
        guard let record = history.record(id: recordID), !uploadingIDs.contains(recordID),
              !deletingIDs.contains(recordID) else { return }
        if let refusal = Self.uploadRefusal(for: record, isTrimming: trimmingIDs.contains(recordID)) {
            notifier.notifyError(refusal, title: "Not uploaded")
            return
        }
        guard let destination = makeDestination() else {
            markFailed(recordID, message: UploadError.notConfigured.localizedDescription)
            return
        }
        retry(recordID: recordID, destination: destination)
    }

    /// Why the record must not be uploaded, or nil: a Trim pass runs on it (`isTrimming`, design,
    /// Write-time checks), or it is a recording marked `Sound not muted`, whose file still holds the
    /// sound its user muted (design, Privacy rule).
    nonisolated static func uploadRefusal(for record: CaptureRecord, isTrimming: Bool = false) -> String? {
        if isTrimming { return EditorAvailability.trimmingRefusal }
        return record.uploadBlockedReason
    }

    /// The failed records Retry Failed Uploads starts again: not one being deleted, and not one
    /// `uploadRefusal` refuses (being trimmed, or marked), which is skipped without a notice.
    nonisolated static func failedRecordsToRetry(_ records: [CaptureRecord], deletingIDs: Set<UUID>,
                                                 trimmingIDs: Set<UUID> = []) -> [CaptureRecord] {
        records.filter {
            !deletingIDs.contains($0.id) && uploadRefusal(for: $0, isTrimming: trimmingIDs.contains($0.id)) == nil
        }
    }

    /// Retries every failed upload with one keychain read. Without a destination, posts one
    /// notification instead of one per record.
    func retryFailedUploads() {
        let failed = Self.failedRecordsToRetry(history.failedRecords, deletingIDs: deletingIDs, trimmingIDs: trimmingIDs)
        guard !failed.isEmpty else { return }
        guard let destination = makeDestination() else {
            notifier.notifyError("Set up a destination in Settings > Upload, then retry.", title: "Upload not configured")
            return
        }
        for record in failed {
            retry(recordID: record.id, destination: destination)
        }
    }

    /// Starts the record's upload again from its file with `destination`. A record whose delete
    /// is in progress is never re-enqueued, so a retry cannot re-upload what Delete is removing.
    /// An interrupted or failed replace re-PUTs its own key, so its URL stays. A record
    /// `uploadRefusal` refuses posts `Not uploaded` with the reason instead.
    private func retry(recordID: UUID, destination: UploadTarget) {
        if let refusal = history.record(id: recordID).flatMap({
            Self.uploadRefusal(for: $0, isTrimming: trimmingIDs.contains(recordID))
        }) {
            notifier.notifyError(refusal, title: "Not uploaded")
            return
        }
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        let payload: UploadPayload
        do {
            payload = try uploadPayload(for: record)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL?.lastPathComponent ?? "no local file").localizedDescription)
            return
        }
        // The location the lane writes to: the same expression `startUpload` uses for its lane.
        let location = queue?.location ?? destination.location
        let policy = EditorUploadPlan.retryPolicy(record: record, currentLocation: location,
                                                  others: history.records.filter { $0.id != recordID })
        let started = EditorUploadPlan.startingRetry(record, policy: policy)
        if started != record {
            history.update(id: recordID) { $0 = started }
        }
        if case .fixed(let key) = policy {
            startUpload(recordID: recordID, payload: payload, destination: destination, fixedKey: key)
        } else {
            startUpload(recordID: recordID, payload: payload, destination: destination)
        }
    }

    /// What an upload of the record sends. An image's PNG is read into memory: straight from the
    /// container for a temporary file, through the save folder's security scope otherwise. A video
    /// or a GIF is never read here: it streams from its file, once the file is found (holding the
    /// folder's scope to look) and a save-folder file is inside the current folder. Throws when the
    /// record has no file it can reach.
    func uploadPayload(for record: CaptureRecord) throws -> UploadPayload {
        switch record.mediaKind {
        case .image:
            guard let fileURL = record.fileURL else { throw UploadError.fileUnreadable("no local file") }
            return .data(record.fileIsTemporary ? try Data(contentsOf: fileURL) : try saveLocation.read(contentsOf: fileURL))
        case .video, .gif:
            return try UploadPayload.video(for: record, saveFolder: saveLocation.currentURL) { url, folder in
                let accessing = folder?.startAccessingSecurityScopedResource() ?? false
                defer { if accessing { folder?.stopAccessingSecurityScopedResource() } }
                return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            }
        }
    }

    /// Stops the upload for `recordID` in whichever queue has it: the current one, or one that
    /// a settings change replaced and that is still finishing its jobs. Returns after that
    /// queue's `.cancelled` event has been handled, so the record holds the reserved key.
    func cancelUpload(of recordID: UUID) async {
        guard uploadingIDs.contains(recordID) else { return }
        // The queue's `.cancelled` event also takes it out; this covers the Clop wait.
        defer { fileUploadIDs.remove(recordID) }
        // Still waiting for the resume decision, Clop or the size check: nothing is enqueued and no
        // key is reserved, so this is the whole cancel, as the queue's `.cancelled` event would do
        // it. Clop's movie, when it comes, is removed by the waiting task, whose token no longer
        // matches.
        if optimisingIDs.removeValue(forKey: recordID) != nil {
            optimizingVideoIDs.remove(recordID)
            uploadingIDs.remove(recordID)
            history.update(id: recordID) { $0.uploadState = .failed(message: "Upload cancelled.") }
            refreshOverlay(for: recordID)
            return
        }
        for lane in [queue].compactMap({ $0 }) + drainingQueues {
            if case .stopped = await lane.queue.cancel(recordID: recordID) {
                return
            }
        }
    }

    func markFailed(_ recordID: UUID, message: String) {
        uploadingIDs.remove(recordID)
        history.update(id: recordID) { $0.uploadState = .failed(message: message) }
        refreshOverlay(for: recordID)
        notifier.notifyError(message, title: "Upload failed")
    }

    /// `location` is where the queue that sent `event` uploads to.
    private func handle(_ event: UploadEvent, at location: ObjectLocation) {
        var sentBytes: Int?
        switch event {
        case .uploaded(let id, _, _), .failed(let id, _), .cancelled(let id, _):
            // The upload has ended, before any early return below: Clop's movie has done its
            // job, and the activity ends with the last recording's upload.
            if let clopResult = clopResults.removeValue(forKey: id) {
                removeClopFile(clopResult)
            }
            sentBytes = sentByteCounts.removeValue(forKey: id)
            if optimizingVideoIDs.remove(id) != nil {
                refreshOverlay(for: id)
            }
            fileUploadIDs.remove(id)
        case .started, .progress, .multipartStarted:
            break
        }
        switch event {
        case .started(let id, let attempt, let fraction):
            if attempt > 1 {
                log("Upload retry \(attempt) for \(id)")
            }
            // Every attempt sets the bar: a fresh one starts again at 0 rather than leaving the
            // failed attempt's fraction, and a resume shows its parts done at once.
            if history.setProgress(id: id, fraction: fraction) {
                refreshOverlay(for: id)
            }
        case .multipartStarted(let id, let state):
            let older = history.record(id: id)?.multipart
            history.update(id: id) { $0.multipart = state }
            // A start over that sends another file (Clop off now, say) drops the older upload's
            // kept Clop copy now. Only a file in `multipart/` is a kept copy, never the record's own.
            // The queue has already rewritten the sidecar for the new upload id.
            if let older, older.sourcePath != state.sourcePath,
               SaveLocation.contains(URL(filePath: older.sourcePath), inFolder: multipartFiles.directory) {
                removeClopFile(URL(filePath: older.sourcePath))
            }
        case .progress(let id, let fraction):
            if history.setProgress(id: id, fraction: fraction) {
                refreshOverlay(for: id)
            }
        case .uploaded(let id, let url, let key):
            uploadingIDs.remove(id)
            // A multipart upload's part list and any kept Clop copy have done their job.
            let multipartFiles = multipartFiles
            Task.detached(priority: .utility) { multipartFiles.remove(id: id) }
            guard let before = history.record(id: id) else {
                // The record disappeared while its upload was running. Nothing would point at the
                // new object, so remove it again instead of copying or announcing its URL.
                deleteOrphanedObject(key: key, at: location)
                return
            }
            // Upload-only mode: the temporary file has done its job. While a card shows the
            // capture it moves into the drag folder under the key's name, so the card can still be
            // dragged out (spec 2.9); otherwise it is removed. Either way the record drops it
            // below. If it can be neither moved nor removed the record keeps pointing at it, so
            // Delete can still remove it later.
            var removedTemporaryFile = false
            if before.fileIsTemporary, let fileURL = before.fileURL {
                removedTemporaryFile = keepForDragOut(fileURL, record: before, url: url, key: key)
                    || removePendingFile(at: fileURL, context: "after upload")
            }
            history.update(id: id) { record in
                record.uploadState = .uploaded(url: url, key: key)
                if record.objectLocation != location {
                    // A reserved key from another destination named an object there, not here.
                    record.pendingObjectKey = nil
                } else if record.pendingObjectKey == key {
                    record.pendingObjectKey = nil
                }
                record.objectLocation = location
                // The size shown is now the uploaded object's.
                if let sentBytes {
                    record.byteCount = sentBytes
                }
                if removedTemporaryFile {
                    record.fileURL = nil
                    record.fileIsTemporary = false
                }
                // Finished: nothing to resume or abort.
                record.multipart = nil
                record = EditorUploadPlan.applyingSuccess(to: record)
            }
            // A screenshot's URL always replaces the clipboard. A recording's does only while the
            // clipboard still holds what the save left there: an upload can take minutes, and the
            // user may have copied something since.
            let replacesClipboard = !before.isTimeBased
                || RecordingSavePlan.replacesClipboard(savedChangeCount: videoClipboardCounts.removeValue(forKey: id),
                                                       currentChangeCount: clipboard.changeCount)
            // The first same-key replace of this launch posts the cache note in place of the usual
            // notification, also with Show notification off, whether or not the URL was copied.
            let postsCacheNote = EditorUploadPlan.shouldPostCacheNote(prior: before.priorUpload, uploadedKey: key,
                                                                      at: location, alreadyPosted: postedCacheNote)
            if postsCacheNote {
                postedCacheNote = true
            }
            if !replacesClipboard {
                linkNotCopiedIDs.insert(id)
                if postsCacheNote {
                    notifier.notify(title: "Uploaded", body: EditorUploadPlan.cacheNote)
                } else if settings.showNotification {
                    notifier.notifyUploaded(url: url, copied: false)
                }
            } else {
                linkNotCopiedIDs.remove(id)
                clipboard.copy(url: url)
                if postsCacheNote {
                    notifier.notify(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)
                } else if settings.showNotification {
                    notifier.notifyUploaded(url: url)
                }
            }
            refreshOverlay(for: id)
            Task { [weak self] in await self?.deleteSupersededObjects(of: id) }
        case .failed(let id, let message):
            guard let failing = history.record(id: id), failing.priorUpload != nil else {
                markFailed(id, message: message)
                return
            }
            // An upload of a record that has a link: the old object is untouched, so the record
            // goes back to it, and keeps the edited or trimmed file and the stale note.
            log("Upload failed, the earlier link is kept: \(message)")
            uploadingIDs.remove(id)
            history.update(id: id) { $0 = EditorUploadPlan.applyingFailure(to: $0, message: message) }
            refreshOverlay(for: id)
            notifier.notifyError(EditorUploadPlan.failedReplaceMessage(for: failing.mediaKind), title: "Not uploaded")
        case .cancelled(let id, let reservedKey):
            // Requested by the delete flow, which removes the record next; no notification.
            uploadingIDs.remove(id)
            history.update(id: id) { record in
                record.uploadState = .failed(message: "Upload cancelled.")
                if let reservedKey {
                    // The PUT may have landed as it was cancelled. Persisted, so Delete removes
                    // this key even if its first DELETE fails and it is tried again later.
                    record.pendingObjectKey = reservedKey
                    record.objectLocation = location
                }
            }
            refreshOverlay(for: id)
        }
    }

    /// Best-effort `DELETE` of an object whose record vanished mid-upload, built from where the
    /// object went (as Delete does) and the credentials stored now. The outcome is only logged.
    private func deleteOrphanedObject(key: String, at location: ObjectLocation) {
        // A collision-prone template can give a live record the same key; never delete that.
        guard CaptureDeletion.sharedKeys([key], at: location, with: history.records).isEmpty else {
            log("Uploaded \(key) for a record that no longer exists, but another capture shares it; kept")
            return
        }
        guard let credentials = loadCredentials() else {
            log("Uploaded \(key) for a record that no longer exists; no credentials to delete it")
            return
        }
        let destination = environment.makeDestination(location.config, credentials)
        Task {
            do {
                try await destination.delete(key: key)
                log("Deleted \(key), uploaded for a record that no longer exists")
            } catch {
                log("Could not delete \(key), uploaded for a record that no longer exists: \(error.localizedDescription)")
            }
        }
    }
}
