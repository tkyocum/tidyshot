import Foundation

// A multipart job's pass: its steps, a new upload and a resumed one. Split from UploadQueue.swift with no body changed (harness design 5.1).
extension UploadQueue {
    /// Where a multipart job goes next: on with a stored upload, or a new one (at `reusing`, or a
    /// key drawn afresh).
    private nonisolated enum MultipartStep: Sendable {
        case resume(MultipartUploadState)
        case create(reusing: String?)
    }

    /// Why a multipart job drops its upload and creates another (design, Resume).
    nonisolated struct Restart: Error {
        /// The job's failure when it has no restart left.
        var cause: any Error
        /// The log line's reason, before `, starting again`; nil logs none.
        var reason: String?
        /// The upload to abort first, when it may still exist.
        var abort: (key: String, uploadID: String)?
        /// The key to create under: nil draws a new one.
        var key: String?

        /// The server no longer knows the upload id: nothing to abort, and the same key.
        static func uploadIDGone(key: String) -> Restart {
            Restart(cause: UploadError.noSuchUpload, reason: "upload id gone", abort: nil, key: key)
        }
    }

    /// One upload id and how its file is cut into parts.
    nonisolated struct MultipartTarget: Sendable {
        var key: String
        var uploadID: String
        var partSize: Int64
        var byteCount: Int64

        var count: Int { MultipartPlan.partCount(byteCount: byteCount, partSize: partSize) }

        /// True when `part` has a number of this upload and the size that number should have.
        func expects(_ part: MultipartPart) -> Bool {
            guard part.number >= 1, part.number <= count else { return false }
            let range = MultipartPlan.range(ofPart: part.number, partSize: partSize, byteCount: byteCount)
            return part.size == range.upperBound - range.lowerBound
        }
    }

    /// What every step of one multipart job shares.
    nonisolated struct MultipartPass: Sendable {
        var job: UploadJob
        /// For the log: the file's name.
        var name: String
        var file: URL
        var source: MultipartSource
        var store: MultipartStore
        /// The job's throttled `.progress` events.
        var report: @Sendable (Double) -> Void
    }

    /// A multipart job's one pass, holding `folder`'s scope throughout. A fresh job creates its
    /// upload; a job with `resume` carries on with the stored one. Each request retries on its own
    /// under `filePolicy`; the job as a whole is not retried. A cause in `Restart` drops the upload
    /// and creates another, at most `MultipartPlan.restartLimit` times. The sidecar is rewritten
    /// after each part, and marks Complete as sent before it goes; a sidecar that cannot be written
    /// fails the job with the write's error.
    func processMultipart(_ job: UploadJob, file url: URL, holding folder: URL?,
                                  source: MultipartSource, store: MultipartStore) async -> JobOutcome {
        let name = url.lastPathComponent
        let accessing = folder.map(scope.start) ?? false
        defer {
            if accessing, let folder { scope.stop(folder) }
        }
        let pass = MultipartPass(job: job, name: name, file: url, source: source, store: store,
                                 report: throttledProgress(for: job.id))
        // A resume starts its bar once it knows the parts done.
        if job.resume == nil {
            await events(.started(id: job.id, attempt: 1, fraction: 0))
        }
        do {
            guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
                throw UploadError.fileUnreadable(name)
            }
            if let ref = job.abortFirst {
                await abortUpload(key: ref.key, uploadID: ref.uploadID, name: name)
                try Task.checkCancellation()
            }
            var step: MultipartStep = job.resume.map { .resume($0) } ?? .create(reusing: nil)
            var restarts = 0
            var rejectedOnce = false
            while true {
                do {
                    let key: String
                    switch step {
                    case .resume(let stored):
                        key = try await resumeUpload(stored, pass, rejectedOnce: &rejectedOnce)
                    case .create(let reusing):
                        key = try await createUpload(pass, reusing: reusing, rejectedOnce: &rejectedOnce)
                    }
                    let publicURL = try destination.publicURL(for: key)
                    reservedKeys[job.id] = nil
                    await events(.uploaded(id: job.id, url: publicURL, key: key))
                    return .uploaded
                } catch let restart as Restart {
                    if cancelledIDs.contains(job.id) { return await deliverCancelled(job.id) }
                    guard restarts < MultipartPlan.restartLimit else { throw restart.cause }
                    restarts += 1
                    reservedKeys[job.id] = nil
                    if let abort = restart.abort {
                        await abortUpload(key: abort.key, uploadID: abort.uploadID, name: name)
                    }
                    if let reason = restart.reason {
                        log("Upload: \(name) \(reason), starting again")
                    }
                    try Task.checkCancellation()
                    // `attempt` counts restarts.
                    await events(.started(id: job.id, attempt: restarts + 1, fraction: 0))
                    step = .create(reusing: restart.key)
                }
            }
        } catch {
            // The task group has awaited every part by now, so a cancel's event comes after the last.
            if cancelledIDs.contains(job.id) {
                return await deliverCancelled(job.id)
            }
            reservedKeys[job.id] = nil
            await events(.failed(id: job.id, message: error.localizedDescription))
            return .failed
        }
    }

    /// A new upload: the key (drawn and reserved, or `reusing` HEADed again), Create, the state
    /// and an empty sidecar, then every part and Complete. Returns the key the object landed at.
    private func createUpload(_ pass: MultipartPass, reusing: String?, rejectedOnce: inout Bool) async throws -> String {
        let job = pass.job
        // The coordinator refuses a file over the plan's limit, so a nil part size cannot happen.
        guard let partSize = plan.partSize(for: pass.source.byteCount) else {
            throw UploadError.fileUnreadable(pass.name)
        }
        let key = if let reusing { try await reserveAgain(reusing, for: job) } else {
            try await objectKey(for: job, retryingHEADs: true)
        }
        reservedKeys[job.id] = key
        let uploadID: String
        do {
            uploadID = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                try await self.destination.createMultipartUpload(key: key, contentType: job.contentType,
                                                                 cacheControl: job.cacheControl)
            }
        } catch {
            if !cancelledIDs.contains(job.id) {
                log("Upload: \(pass.name) create failed: \(error.localizedDescription)")
            }
            throw error
        }
        let source = pass.source
        let state = MultipartUploadState(uploadID: uploadID, key: key, location: source.location,
                                         partSize: partSize, byteCount: source.byteCount,
                                         sourceModified: source.modified, sourcePath: source.path,
                                         startedAt: now())
        let target = MultipartTarget(key: key, uploadID: uploadID, partSize: partSize, byteCount: source.byteCount)
        var sidecar = MultipartSidecar(uploadID: uploadID, completeSent: false, parts: [])
        try pass.store.writeSidecar(sidecar, id: job.id)
        await events(.multipartStarted(id: job.id, state: state))
        log("Upload: \(pass.name) multipart, \(target.count) parts of \(Self.mebibytes(partSize)) MiB, upload id \(uploadID)")
        try await sendParts(Array(1..<(target.count + 1)), of: target, sidecar: &sidecar, pass)
        try await complete(target, sidecar: &sidecar, pass, rejectedOnce: &rejectedOnce)
        return key
    }

    /// Carries on with a stored upload, at its key, id and part size. A template key is HEADed
    /// first: absent goes on, the stored size means an earlier Complete landed, and another size
    /// means another capture took the key, which restarts under a new one. Then the parts the
    /// sidecar (or ListParts) lacks, and Complete. Returns the key the object landed at.
    private func resumeUpload(_ stored: MultipartUploadState, _ pass: MultipartPass,
                              rejectedOnce: inout Bool) async throws -> String {
        let target = MultipartTarget(key: stored.key, uploadID: stored.uploadID, partSize: stored.partSize,
                                     byteCount: stored.byteCount)
        if case .template = pass.job.key {
            let size = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                try await self.destination.objectSize(key: stored.key)
            }
            if size == stored.byteCount { return stored.key }
            if size != nil {
                // A resume's first step, so never a third cause.
                throw Restart(cause: UploadError.keyCollisionsExhausted, reason: "key taken",
                              abort: (stored.key, stored.uploadID), key: nil)
            }
        }
        reservedKeys[pass.job.id] = stored.key
        var sidecar = try await partList(of: target, pass)
        let numbers = Set(sidecar.parts.map(\.number))
        let missing = (1..<(target.count + 1)).filter { !numbers.contains($0) }
        let doneBytes = sidecar.parts.reduce(0) { $0 + $1.size }
        await events(.started(id: pass.job.id, attempt: 1,
                              fraction: MultipartPlan.fraction(doneBytes: doneBytes, inFlightBytes: 0, total: target.byteCount)))
        log("Upload: \(pass.name) resumes at \(sidecar.parts.count) of \(target.count) parts")
        try await sendParts(missing, of: target, sidecar: &sidecar, pass)
        try await complete(target, sidecar: &sidecar, pass, rejectedOnce: &rejectedOnce)
        return stored.key
    }

    /// `key` again for a restart: a fixed key as is; a template key HEADed again, and kept when
    /// free, else a new one drawn and reserved.
    private func reserveAgain(_ key: String, for job: UploadJob) async throws -> String {
        guard case .template(let context) = job.key else { return key }
        let taken = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
            try await self.destination.exists(key: key)
        }
        return taken ? try await reserveKey(ext: job.fileExtension, context: context, retryingHEADs: true) : key
    }

    /// `bytes` in MiB for the log: whole for every real part size, decimal for a test's.
    private static func mebibytes(_ bytes: Int64) -> String {
        let mib: Int64 = 1_048_576
        return bytes % mib == 0 ? "\(bytes / mib)" : "\(Double(bytes) / Double(mib))"
    }
}
