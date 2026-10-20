import Foundation

/// An upload target. One implementation today (`S3Destination`); the protocol keeps the queue,
/// tests, and a future second backend independent of S3 details.
nonisolated protocol Destination: Sendable {
    /// True when an object already exists at `key` (HTTP 200 on HEAD), false when it does not
    /// (404, or 403 from AWS S3 when the caller lacks `s3:ListBucket`; see `S3Destination.exists`).
    func exists(key: String) async throws -> Bool
    /// Uploads `data` to `key`. `progress` receives fractions in 0...1 from the transport thread.
    func upload(_ data: Data, key: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws
    /// Removes the object at `key`. Used by Delete (the capture's object, and any key its
    /// cancelled upload had reserved), by the cleanup of an object uploaded for a record that no
    /// longer exists, and by the connection test to remove its probe object.
    func delete(key: String) async throws
    /// Where `key` can be read from after upload.
    func publicURL(for key: String) throws -> URL
}

nonisolated struct UploadJob: Sendable, Identifiable {
    /// Matches the `CaptureRecord.id` this upload belongs to.
    let id: UUID
    let data: Data
    let contentType: String
    /// Without a dot, for example `png`.
    let fileExtension: String
    /// What the object key template is expanded against (capture time, app, counter, hostname).
    /// The queue expands it afresh for every key attempt, so only `{random}` changes on a collision.
    let naming: TemplateContext

    init(id: UUID, data: Data, contentType: String, fileExtension: String, naming: TemplateContext = TemplateContext()) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.naming = naming
    }
}

nonisolated enum UploadEvent: Sendable, Equatable {
    case started(id: UUID, attempt: Int)
    case progress(id: UUID, fraction: Double)
    case uploaded(id: UUID, url: URL, key: String)
    case failed(id: UUID, message: String)
    /// Terminal, like `.failed`, after `UploadQueue.cancel(recordID:)`. Never followed by `.failed`.
    /// `reservedKey` is the key the job had claimed, nil when it was cancelled before HEAD
    /// found one; its PUT may have completed on the server, so a delete removes it too.
    case cancelled(id: UUID, reservedKey: String?)
}

nonisolated enum UploadError: LocalizedError, Equatable, Sendable {
    /// `body` is already a short summary (see `S3Destination.excerpt`), for example
    /// `AccessDenied: Access Denied`, never the raw response body.
    case httpStatus(Int, body: String)
    case noHTTPResponse
    case keyCollisionsExhausted
    case notConfigured
    case fileUnreadable(String)

    /// Server-side and transport failures are retried; client errors (bad credentials,
    /// missing bucket, forbidden) are not.
    var isRetryable: Bool {
        switch self {
        case .httpStatus(let status, _): status >= 500 || status == 429
        case .noHTTPResponse: true
        case .keyCollisionsExhausted, .notConfigured, .fileUnreadable: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status, let body):
            body.isEmpty ? "Server returned HTTP \(status)." : "Server returned HTTP \(status): \(body)"
        case .noHTTPResponse: "No HTTP response."
        case .keyCollisionsExhausted: "Could not find an unused object key after 5 tries."
        case .notConfigured: "No upload destination is configured."
        case .fileUnreadable(let path): "The file could not be read: \(path)"
        }
    }

    /// Whether an arbitrary error thrown during an upload attempt is worth retrying.
    /// Cancellation (`CancellationError` or `URLError(.cancelled)`) is never retried; other
    /// `URLError`s are transport failures and are.
    static func isRetryable(_ error: Error) -> Bool {
        if let uploadError = error as? UploadError { return uploadError.isRetryable }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return false }
        return error is URLError
    }
}
