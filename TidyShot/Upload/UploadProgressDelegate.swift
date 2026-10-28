import Foundation

/// Per-task delegate for every S3 request. Forwards upload progress to closures and refuses
/// HTTP redirects, so a signed request is never replayed to another host; the 3xx response is
/// returned to the caller instead. URLSession calls delegates on its own queue, so the class is
/// `nonisolated` and the closures must be `@Sendable`.
nonisolated final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void
    /// The bytes sent since the last call, for a multipart part, whose job adds up its own fraction.
    private let onBytesSent: @Sendable (Int64) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void = { _ in },
         onBytesSent: @escaping @Sendable (Int64) -> Void = { _ in }) {
        self.onProgress = onProgress
        self.onBytesSent = onBytesSent
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        onBytesSent(bytesSent)
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
