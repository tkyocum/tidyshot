import Foundation
import Synchronization

// A multipart job's parts: the part list, the parts in flight, Complete, and the part reads and progress. Split from UploadQueue.swift with no body changed (harness design 5.1).
extension UploadQueue {
    /// A part that ran out of tries, or met an error that is not retried. Its description is the
    /// job's failure message.
    private nonisolated struct PartFailure: LocalizedError {
        var number: Int
        var count: Int
        var error: any Error

        var errorDescription: String? { "Part \(number) of \(count): \(error.localizedDescription)" }
    }

    /// The stored sidecar, or one rebuilt from ListParts when it is missing, unreadable or for
    /// another upload id. A listed part is trusted when its size is the one its number should have.
    func partList(of target: MultipartTarget, _ pass: MultipartPass) async throws -> MultipartSidecar {
        if let sidecar = pass.store.readSidecar(id: pass.job.id, uploadID: target.uploadID) {
            return sidecar
        }
        log("Upload: \(pass.name) part list missing, listing parts")
        var trusted: [Int: MultipartPart] = [:]
        for part in try await listParts(of: target, pass) where target.expects(part) {
            trusted[part.number] = part
        }
        let sidecar = MultipartSidecar(uploadID: target.uploadID, completeSent: false,
                                       parts: trusted.values.sorted { $0.number < $1.number })
        try pass.store.writeSidecar(sidecar, id: pass.job.id)
        return sidecar
    }

    /// ListParts, retried. A gone upload id, or any other failure left after the retries (a 403
    /// for a key without `s3:ListMultipartUploadParts`), restarts the job under the same key.
    private func listParts(of target: MultipartTarget, _ pass: MultipartPass) async throws -> [MultipartPart] {
        do {
            return try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                try await self.destination.listParts(key: target.key, uploadID: target.uploadID)
            }
        } catch UploadError.noSuchUpload {
            throw Restart.uploadIDGone(key: target.key)
        } catch {
            throw Restart(cause: error, reason: "part list unavailable", abort: (target.key, target.uploadID),
                          key: target.key)
        }
    }

    /// Sends `numbers` of `target`'s parts, at most `plan.inFlight` at a time and added in order as
    /// each finishes, putting each in the sidecar (rewritten) as it lands. Progress starts at the
    /// sidecar's bytes. A part whose upload id is gone restarts the job under the same key.
    func sendParts(_ numbers: [Int], of target: MultipartTarget, sidecar: inout MultipartSidecar,
                           _ pass: MultipartPass) async throws {
        guard !numbers.isEmpty else { return }
        let doneBytes = sidecar.parts.reduce(0) { $0 + $1.size }
        let sender = PartSender(destination: destination, policy: filePolicy, sleep: sleep, log: log,
                                target: target, pass: pass,
                                progress: MultipartProgress(total: target.byteCount, done: doneBytes))
        do {
            try await withThrowingTaskGroup(of: MultipartPart.self) { group in
                var next = numbers.startIndex
                while next < numbers.endIndex, next - numbers.startIndex < plan.inFlight {
                    let number = numbers[next]
                    group.addTask { try await sender.send(number) }
                    next += 1
                }
                while let part = try await group.next() {
                    sidecar.parts.removeAll { $0.number == part.number }
                    sidecar.parts.append(part)
                    sidecar.parts.sort { $0.number < $1.number }
                    try pass.store.writeSidecar(sidecar, id: pass.job.id)
                    sender.report(sender.progress.finish(part: part.number, size: part.size))
                    if next < numbers.endIndex {
                        let number = numbers[next]
                        group.addTask { try await sender.send(number) }
                        next += 1
                    }
                }
            }
        } catch let failure as PartFailure where (failure.error as? UploadError) == .noSuchUpload {
            throw Restart.uploadIDGone(key: target.key)
        }
    }

    /// Complete, retried, once the sidecar says it was sent. A gone upload id restarts the job,
    /// unless a Complete was sent for it before (before a quit, or a try whose answer was lost)
    /// and the object has the upload's size. The first rejected part list in the job is listed
    /// again and the parts that differ are resent; a second one restarts.
    func complete(_ target: MultipartTarget, sidecar: inout MultipartSidecar, _ pass: MultipartPass,
                          rejectedOnce: inout Bool) async throws {
        while true {
            var sentBefore = sidecar.completeSent
            // Complete never goes before the sidecar says it was sent.
            sidecar.completeSent = true
            try pass.store.writeSidecar(sidecar, id: pass.job.id)
            let parts = sidecar.parts
            do {
                try await Self.withRetries(policy: filePolicy, sleep: sleep, onRetry: { _, _ in sentBefore = true }) {
                    try await self.destination.completeMultipartUpload(key: target.key, uploadID: target.uploadID,
                                                                       parts: parts)
                }
            } catch UploadError.noSuchUpload {
                guard sentBefore else { throw Restart.uploadIDGone(key: target.key) }
                let size = try await Self.withRetries(policy: filePolicy, sleep: sleep) {
                    try await self.destination.objectSize(key: target.key)
                }
                guard size == target.byteCount else { throw Restart.uploadIDGone(key: target.key) }
            } catch let error as UploadError {
                guard case .partsRejected = error else { throw error }
                guard !rejectedOnce else {
                    throw Restart(cause: error, reason: nil, abort: (target.key, target.uploadID), key: target.key)
                }
                rejectedOnce = true
                log("Upload: \(pass.name) part list rejected, listing parts")
                let listed = Set(try await listParts(of: target, pass))
                sidecar.parts.removeAll { !listed.contains($0) }
                try pass.store.writeSidecar(sidecar, id: pass.job.id)
                let kept = Set(sidecar.parts.map(\.number))
                try await sendParts((1..<(target.count + 1)).filter { !kept.contains($0) }, of: target,
                                    sidecar: &sidecar, pass)
                continue
            }
            log("Upload: \(pass.name) multipart completed")
            return
        }
    }

    /// The bytes of `range` in the file at `url`, read off the caller's actor. A file that cannot
    /// be opened or read, or that holds fewer bytes than the range (it shrank), throws
    /// `UploadError.fileUnreadable`.
    @concurrent nonisolated static func readPart(of url: URL, range: Range<Int64>) async throws -> Data {
        let expected = Int(range.upperBound - range.lowerBound)
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(range.lowerBound))
            data = try handle.read(upToCount: expected) ?? Data()
        } catch {
            throw UploadError.fileUnreadable(url.lastPathComponent)
        }
        guard data.count == expected else { throw UploadError.fileUnreadable(url.lastPathComponent) }
        return data
    }

    /// Sends one multipart job's parts: each reads its bytes, then sends them, retrying under
    /// `policy`. Runs in the job's task group, off the queue's actor.
    private nonisolated struct PartSender: Sendable {
        let destination: any Destination
        let policy: RetryPolicy
        let sleep: Sleeper
        let log: Logger
        let target: MultipartTarget
        let pass: MultipartPass
        let progress: MultipartProgress

        /// The job's throttled `.progress` events.
        var report: @Sendable (Double) -> Void { pass.report }

        /// Part `number`, sent. Any failure is thrown as a `PartFailure`.
        @concurrent func send(_ number: Int) async throws -> MultipartPart {
            do {
                // A part the loop adds after a cancel reads and sends nothing (harness design 5.4).
                try Task.checkCancellation()
                let range = MultipartPlan.range(ofPart: number, partSize: target.partSize, byteCount: target.byteCount)
                let data = try await UploadQueue.readPart(of: pass.file, range: range)
                let progress = progress
                let report = pass.report
                let etag = try await UploadQueue.withRetries(policy: policy, sleep: sleep, onRetry: { attempt, error in
                    progress.restart(part: number)
                    log("Upload: \(pass.name) part \(number) failed, retry \(attempt): \(error.localizedDescription)")
                }) {
                    try await destination.uploadPart(key: target.key, uploadID: target.uploadID, number: number, data: data,
                                                     progress: { report(progress.sent($0, part: number)) })
                }
                return MultipartPart(number: number, etag: etag, size: Int64(data.count))
            } catch {
                throw PartFailure(number: number, count: target.count, error: error)
            }
        }
    }
}

/// A multipart job's progress: the bytes of completed parts plus what each in-flight part has sent
/// so far, over the file's size. Parts report from the transport's threads, so it is locked.
nonisolated final class MultipartProgress: Sendable {
    private struct Counts {
        var done: Int64 = 0
        var inFlight: [Int: Int64] = [:]
    }

    private let counts: Mutex<Counts>
    private let total: Int64

    /// `done` is the bytes of parts already sent, as a resume starts.
    init(total: Int64, done: Int64 = 0) {
        self.total = total
        counts = Mutex(Counts(done: done))
    }

    /// Adds `delta` bytes sent by part `number`, and returns the job's fraction.
    func sent(_ delta: Int64, part number: Int) -> Double {
        counts.withLock { counts in
            counts.inFlight[number, default: 0] += delta
            return fraction(counts)
        }
    }

    /// Forgets what part `number` has sent, before it is sent again.
    func restart(part number: Int) {
        counts.withLock { $0.inFlight[number] = nil }
    }

    /// Counts part `number` as done with `size` bytes, and returns the job's fraction.
    func finish(part number: Int, size: Int64) -> Double {
        counts.withLock { counts in
            counts.inFlight[number] = nil
            counts.done += size
            return fraction(counts)
        }
    }

    private func fraction(_ counts: Counts) -> Double {
        MultipartPlan.fraction(doneBytes: counts.done, inFlightBytes: counts.inFlight.values.reduce(0, +), total: total)
    }
}
