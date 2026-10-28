import Foundation
import Synchronization

/// The drag-out download: a signed GET with progress that lands at a path the caller owns.
extension S3Destination {
    /// GET Object through a download task, reporting progress, landing the file at `landing`
    /// (`DragFileStore.landingURL()`). The fraction is over `Content-Length`, or `expectedBytes`
    /// when the response has none. With `resumeData` (a failed download's, from its `URLError`'s
    /// `downloadTaskResumeData`), the task replays the first request, signature and all, from where
    /// it stopped; `key` is then unused. A failure throws as `download(key:to:)` does, except that a
    /// transport error is the session's `URLError` unchanged, with its resume data. Nothing is left
    /// at `landing` on any failure or cancel; URLSession removes its own temporary file. Cancelling
    /// the calling task cancels the URLSession task.
    func download(key: String, to landing: URL, expectedBytes: Int64?, resumeData: Data? = nil,
                  progress: @escaping @Sendable (Double) -> Void) async throws {
        try Task.checkCancellation()
        let task: URLSessionDownloadTask
        if let resumeData {
            task = session.downloadTask(withResumeData: resumeData)
        } else {
            let request = try signedRequest(method: "GET", key: key, payloadHash: S3Signer.emptyPayloadHash,
                                            extraHeaders: [])
            task = session.downloadTask(with: request)
        }
        let delegate = DragDownloadDelegate(landing: landing, expectedBytes: expectedBytes, onProgress: progress)
        task.delegate = delegate
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                delegate.start(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}

/// The drag-out download's task delegate. URLSession removes its temporary file as soon as
/// `didFinishDownloadingTo` returns, so the file is moved to `landing` inside that callback, and the
/// status is read there. Refuses redirects and throttles progress as `UploadProgressDelegate` does.
/// URLSession calls it on its own queue, so its state is locked.
nonisolated final class DragDownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    /// The continuation and the task's result can arrive in either order: a cancel that lands
    /// before `withTaskCancellationHandler` cancels the task before `start`, and URLSession still
    /// completes it. Whichever comes second resumes the continuation.
    private enum Phase {
        case waiting
        case started(CheckedContinuation<Void, any Error>)
        case completed(Result<Void, any Error>)
        case resumed
    }

    private struct State {
        var phase = Phase.waiting
        /// A non-2xx response or a failed move, kept for `didCompleteWithError`.
        var failure: (any Error)?
    }

    private let landing: URL
    private let expectedBytes: Int64?
    private let onProgress: @Sendable (Double) -> Void
    private let gate = ProgressGate()
    private let state = Mutex(State())

    init(landing: URL, expectedBytes: Int64?, onProgress: @escaping @Sendable (Double) -> Void) {
        self.landing = landing
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    /// Set before the task resumes; resumed once, when the task completes, or at once when it
    /// already has.
    func start(_ continuation: CheckedContinuation<Void, any Error>) {
        let result: Result<Void, any Error>? = state.withLock { state in
            switch state.phase {
            case .waiting:
                state.phase = .started(continuation)
                return nil
            case .completed(let result):
                state.phase = .resumed
                return result
            case .started, .resumed:
                preconditionFailure("DragDownloadDelegate started twice")
            }
        }
        if let result {
            continuation.resume(with: result)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : (expectedBytes ?? 0)
        guard expected > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(expected))
        if gate.admits(fraction) {
            onProgress(fraction)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fileManager = FileManager.default
        do {
            try fileManager.moveItem(at: location, to: landing)
        } catch {
            state.withLock { $0.failure = error }
            return
        }
        do {
            guard let response = downloadTask.response else { throw UploadError.noHTTPResponse }
            let http = try S3Destination.httpResponse(response)
            guard (200..<300).contains(http.statusCode) else {
                let body = S3Destination.errorBody(at: landing)
                throw S3Destination.failure(http, bodyText: S3Destination.excerpt(body))
            }
        } catch {
            try? fileManager.removeItem(at: landing)
            state.withLock { $0.failure = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let failure = state.withLock { $0.failure }
        let result: Result<Void, any Error>
        if let error {
            // Only a file that landed before the error could be there.
            try? FileManager.default.removeItem(at: landing)
            result = .failure(error)
        } else if let failure {
            result = .failure(failure)
        } else {
            result = .success(())
        }
        let continuation: CheckedContinuation<Void, any Error>? = state.withLock { state in
            switch state.phase {
            case .waiting:
                state.phase = .completed(result)
                return nil
            case .started(let continuation):
                state.phase = .resumed
                return continuation
            case .completed, .resumed:
                return nil
            }
        }
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
