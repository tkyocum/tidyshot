import Foundation
import Synchronization
@testable import TidyShot

/// Scripted destination: records calls, pretends some keys exist, fails a set number of times.
nonisolated final class FakeDestination: Destination, Sendable {
    struct State: Sendable {
        var existingKeys: Set<String> = []
        /// Errors for HEAD, one per call, in order; then HEAD answers.
        var headFailures: [UploadError] = []
        var failuresRemaining = 0
        var failure: UploadError = .httpStatus(503, body: "")
        var headKeys: [String] = []
        var uploads: [(key: String, data: Data, contentType: String, cacheControl: String?)] = []
        /// Every call to `upload`, including ones that throw.
        var uploadAttempts = 0
        /// The key of every call to `upload`, including ones that throw, in order.
        var attemptKeys: [String] = []
        /// This many uploads (after any scripted failures) wait a minute instead of finishing,
        /// so a test can cancel them; the wait throws `CancellationError` when the task is cancelled.
        var blockingUploadsRemaining = 0
        /// This many uploads (after any scripted failures and blocking uploads) wait for
        /// `releaseUploads(throwing:)` even when their task is cancelled, like a PUT that the server
        /// finishes just as it is cancelled.
        var holdingUploadsRemaining = 0
        /// Held uploads waiting for `releaseUploads(throwing:)`.
        var heldUploads: [CheckedContinuation<Void, any Error>] = []
        /// Set by `releaseUploads(throwing:)`; a later held upload finishes at once with this result.
        var heldUploadsRelease: Result<Void, any Error>?
        /// Times a held upload's task was cancelled while it waited.
        var heldUploadCancellations = 0
        /// Every successful `upload(fileAt:)`, with the file it read.
        var fileUploads: [(key: String, url: URL, contentType: String, cacheControl: String?)] = []
        /// The file of every call to `upload(fileAt:)`, including ones that throw, in order.
        var attemptFiles: [URL] = []
        /// This many file uploads wait in their hash until their task is cancelled, as
        /// `S3Signer.sha256Hex(fileAt:)` stops at its next read.
        var blockingHashesRemaining = 0
        /// True once a file upload is waiting in its hash.
        var isHashing = false
        /// What every successful attempt reports to `progress`, in order and at once.
        var progressFractions: [Double] = [0.5, 1]

        // Multipart. Each `…Failures` script throws its errors one per call, in order, then the
        // call succeeds.

        /// Every multipart call in order, as `create`, `part <n>`, `complete`, `abort`, `list`
        /// and `size`, made before the call acts.
        var calls: [String] = []
        /// Called with each entry of `calls` as it is made, outside the lock.
        var onCall: (@Sendable (String) -> Void)?
        var createFailures: [UploadError] = []
        /// Every Create, including ones that throw. Create `n` returns `upload-<n>`.
        var creates: [(key: String, contentType: String, cacheControl: String?)] = []
        /// Each part's errors, one per attempt, keyed by part number.
        var partFailures: [Int: [UploadError]] = [:]
        /// How long each part takes before it answers, so parts overlap.
        var partDelay: Duration = .zero
        /// A part cancelled in its delay takes this long more to stop, outside any cancellation,
        /// like a request tearing down.
        var cancelLinger: TimeInterval = 0
        /// Every part call, including ones that throw.
        var parts: [(uploadID: String, number: Int, size: Int)] = []
        /// The parts that answered with an ETag.
        var sentParts: [Int] = []
        /// For each part call in order: how many parts had answered when it began.
        var answeredAtStart: [Int: [Int]] = [:]
        var partsInFlight = 0
        var maxPartsInFlight = 0
        var completeFailures: [UploadError] = []
        var completes: [(key: String, uploadID: String, parts: [MultipartPart])] = []
        var abortFailures: [UploadError] = []
        var abortResult: MultipartAbortResult = .aborted
        var aborts: [(key: String, uploadID: String)] = []
        var listPartsFailures: [UploadError] = []
        var listedParts: [MultipartPart] = []
        var listPartsCalls: [(key: String, uploadID: String)] = []
        var objectSizeFailures: [UploadError] = []
        var objectSizes: [String: Int64] = [:]
        var objectSizeKeys: [String] = []

        // The coordinator harness (harness design 2.4): the downloads, Delete's DELETEs, a held part
        // and blocked or held Aborts.

        /// What a drag-out download does once any hold is released: reports `downloadFractions`, then
        /// lands `downloadOutcome`'s bytes at the landing path or throws its error.
        var downloadOutcome: DownloadOutcome = .lands(bytes: 4)
        var downloadFractions: [Double] = [0.5, 1]
        /// Each drag-out download's key and resume data, in order.
        var downloads: [(key: String, resumeData: Data?)] = []
        /// When true, each drag-out download waits for `releaseDownloads()`, even when its task is
        /// cancelled, like a transfer that finishes just as it is cancelled.
        var holdsDownloads = false
        let downloadHold = HeldReleases()
        /// Times a held download's task was cancelled while it waited.
        var downloadCancellations: Int { downloadHold.cancellations }
        /// The last drag-out download's progress callback, for a fraction that comes after its end.
        var downloadProgress: (@Sendable (Double) -> Void)?
        /// What `download(key:)` returns, and the keys it was asked for.
        var downloadedData = Data("object".utf8)
        var dataDownloadKeys: [String] = []
        /// Every `delete(key:)`, in order.
        var deletedKeys: [String] = []
        /// This part waits for `releaseParts()` before it reports anything, even when its task is
        /// cancelled, then answers.
        var holdingPart: Int?
        let partHold = HeldReleases()
        var heldPartCancellations: Int { partHold.cancellations }
        /// This many Aborts wait a minute instead of answering; the wait throws `CancellationError`
        /// when the task is cancelled.
        var blockingAbortsRemaining = 0
        /// This many Aborts (after any blocking ones) wait for `releaseAborts()` even when their task
        /// is cancelled, then answer.
        var holdingAbortsRemaining = 0
        let abortHold = HeldReleases()
        var heldAbortCancellations: Int { abortHold.cancellations }
    }

    /// How a drag-out download ends.
    enum DownloadOutcome: Sendable {
        /// A file of this many bytes at the landing path.
        case lands(bytes: Int)
        case fails(any Error & Sendable)
    }

    let state: Mutex<State>

    init(_ state: State = State()) {
        self.state = Mutex(state)
    }

    func exists(key: String) async throws -> Bool {
        let (failure, exists) = state.withLock { state in
            state.headKeys.append(key)
            return (Self.nextFailure(&state.headFailures), state.existingKeys.contains(key))
        }
        if let failure { throw failure }
        return exists
    }

    func upload(_ data: Data, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        try await attempt(key: key, progress: progress)
        state.withLock { $0.uploads.append((key, data, contentType, cacheControl)) }
    }

    func upload(fileAt url: URL, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        state.withLock { $0.attemptFiles.append(url) }
        let hashBlocks = state.withLock {
            guard $0.blockingHashesRemaining > 0 else { return false }
            $0.blockingHashesRemaining -= 1
            $0.isHashing = true
            return true
        }
        if hashBlocks {
            try await Task.sleep(for: .seconds(60))
        }
        try await attempt(key: key, progress: progress)
        state.withLock { $0.fileUploads.append((key, url, contentType, cacheControl)) }
    }

    func download(key: String, to destination: URL) async throws {}

    func download(key: String) async throws -> Data {
        state.withLock { state in
            state.dataDownloadKeys.append(key)
            return state.downloadedData
        }
    }

    func download(key: String, to landing: URL, expectedBytes: Int64?, resumeData: Data?,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        let hold = state.withLock { state in
            state.downloads.append((key, resumeData))
            state.downloadProgress = progress
            return state.holdsDownloads ? state.downloadHold : nil
        }
        await hold?.hold()
        let (fractions, outcome) = state.withLock { ($0.downloadFractions, $0.downloadOutcome) }
        for fraction in fractions {
            progress(fraction)
        }
        switch outcome {
        case .lands(let bytes):
            try Data(count: bytes).write(to: landing)
        case .fails(let error):
            throw error
        }
    }

    /// Lets every held download go on, now and later.
    func releaseDownloads() {
        state.withLock { $0.downloadHold }.release()
    }

    /// Calls the last download's progress callback, after the download has ended.
    func reportLateFraction(_ fraction: Double) {
        state.withLock { $0.downloadProgress }?(fraction)
    }

    /// One upload attempt of either kind: the scripted failures, blocks and holds, then progress.
    private func attempt(key: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let failure: UploadError? = state.withLock {
            $0.uploadAttempts += 1
            $0.attemptKeys.append(key)
            guard $0.failuresRemaining > 0 else { return nil }
            $0.failuresRemaining -= 1
            return $0.failure
        }
        if let failure { throw failure }
        let blocks = state.withLock {
            guard $0.blockingUploadsRemaining > 0 else { return false }
            $0.blockingUploadsRemaining -= 1
            return true
        }
        if blocks {
            try await Task.sleep(for: .seconds(60))
        }
        let holds = state.withLock {
            guard $0.holdingUploadsRemaining > 0 else { return false }
            $0.holdingUploadsRemaining -= 1
            return true
        }
        if holds {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let release: Result<Void, any Error>? = state.withLock {
                        if let release = $0.heldUploadsRelease { return release }
                        $0.heldUploads.append(continuation)
                        return nil
                    }
                    if let release { continuation.resume(with: release) }
                }
            } onCancel: {
                state.withLock { $0.heldUploadCancellations += 1 }
            }
        }
        for fraction in state.withLock({ $0.progressFractions }) {
            progress(fraction)
        }
    }

    /// Finishes every held upload, now and later: successfully, or by throwing `error`.
    func releaseUploads(throwing error: (any Error)? = nil) {
        let release: Result<Void, any Error> = error.map { .failure($0) } ?? .success(())
        let held = state.withLock {
            $0.heldUploadsRelease = release
            defer { $0.heldUploads = [] }
            return $0.heldUploads
        }
        for continuation in held { continuation.resume(with: release) }
    }

    func delete(key: String) async throws {
        state.withLock { $0.deletedKeys.append(key) }
    }

    func publicURL(for key: String) throws -> URL {
        URL(string: "https://snap.tky.io/\(key)")!
    }

    // Multipart

    /// Records `call`, runs `body` under the lock, then tells `onCall`.
    private func record<T>(_ call: String, _ body: (inout State) -> T) -> T {
        let (result, onCall) = state.withLock { state in
            state.calls.append(call)
            return (body(&state), state.onCall)
        }
        onCall?(call)
        return result
    }

    /// The next scripted error of `failures`, removed from the script.
    private static func nextFailure(_ failures: inout [UploadError]) -> UploadError? {
        failures.isEmpty ? nil : failures.removeFirst()
    }

    func createMultipartUpload(key: String, contentType: String, cacheControl: String?) async throws -> String {
        let (failure, count) = record("create") { state in
            state.creates.append((key, contentType, cacheControl))
            return (Self.nextFailure(&state.createFailures), state.creates.count)
        }
        if let failure { throw failure }
        return "upload-\(count)"
    }

    func uploadPart(key: String, uploadID: String, number: Int, data: Data,
                    progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let delay = record("part \(number)") { state in
            state.parts.append((uploadID, number, data.count))
            state.answeredAtStart[number, default: []].append(state.sentParts.count)
            state.partsInFlight += 1
            state.maxPartsInFlight = max(state.maxPartsInFlight, state.partsInFlight)
            return state.partDelay
        }
        defer { state.withLock { $0.partsInFlight -= 1 } }
        let hold = state.withLock { $0.holdingPart == number ? $0.partHold : nil }
        await hold?.hold()
        // Half the bytes, the wait, then the rest, so a job's fraction counts bytes in flight.
        let half = Int64(data.count / 2)
        progress(half)
        if delay > .zero {
            do {
                try await Task.sleep(for: delay)
            } catch {
                let linger = state.withLock { $0.cancelLinger }
                if linger > 0 {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + linger) { continuation.resume() }
                    }
                }
                throw error
            }
        }
        let failure: UploadError? = state.withLock { state in
            guard var script = state.partFailures[number], !script.isEmpty else { return nil }
            let failure = script.removeFirst()
            state.partFailures[number] = script
            return failure
        }
        if let failure { throw failure }
        progress(Int64(data.count) - half)
        state.withLock { $0.sentParts.append(number) }
        return "\"etag-\(number)\""
    }

    /// Lets the held part, and a later one with its number, answer.
    func releaseParts() {
        state.withLock { $0.partHold }.release()
    }

    func completeMultipartUpload(key: String, uploadID: String, parts: [MultipartPart]) async throws {
        let failure = record("complete") { state in
            state.completes.append((key, uploadID, parts))
            return Self.nextFailure(&state.completeFailures)
        }
        if let failure { throw failure }
    }

    func abortMultipartUpload(key: String, uploadID: String) async throws -> MultipartAbortResult {
        let (failure, result, blocks, hold) = record("abort") { state in
            state.aborts.append((key, uploadID))
            let blocks = state.blockingAbortsRemaining > 0
            if blocks { state.blockingAbortsRemaining -= 1 }
            let holds = !blocks && state.holdingAbortsRemaining > 0
            if holds { state.holdingAbortsRemaining -= 1 }
            return (Self.nextFailure(&state.abortFailures), state.abortResult, blocks,
                    holds ? state.abortHold : nil)
        }
        if blocks {
            try await Task.sleep(for: .seconds(60))
        }
        await hold?.hold()
        if let failure { throw failure }
        return result
    }

    /// Lets every held Abort answer, now and later.
    func releaseAborts() {
        state.withLock { $0.abortHold }.release()
    }

    func listParts(key: String, uploadID: String) async throws -> [MultipartPart] {
        let (failure, parts) = record("list") { state in
            state.listPartsCalls.append((key, uploadID))
            return (Self.nextFailure(&state.listPartsFailures), state.listedParts)
        }
        if let failure { throw failure }
        return parts
    }

    func objectSize(key: String) async throws -> Int64? {
        let (failure, size) = record("size") { state in
            state.objectSizeKeys.append(key)
            return (Self.nextFailure(&state.objectSizeFailures), state.objectSizes[key])
        }
        if let failure { throw failure }
        return size
    }
}

/// The hold the download, part and Abort holds share: `hold()` waits for `release()` even when its
/// task is cancelled, like a request the server finishes just as it is cancelled, and counts each
/// cancel. Once released, a later hold ends at once.
nonisolated final class HeldReleases: Sendable {
    private struct State {
        var waiting: [CheckedContinuation<Void, Never>] = []
        var released = false
        var cancellations = 0
    }

    private let state = Mutex(State())

    /// Times a hold's task was cancelled while it waited.
    var cancellations: Int { state.withLock { $0.cancellations } }

    func hold() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let released = state.withLock { state in
                    if state.released { return true }
                    state.waiting.append(continuation)
                    return false
                }
                if released { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.cancellations += 1 }
        }
    }

    /// Ends every hold, now and later.
    func release() {
        let held = state.withLock { state in
            state.released = true
            defer { state.waiting = [] }
            return state.waiting
        }
        for continuation in held { continuation.resume() }
    }
}
