import Foundation

/// An upload target. One implementation today (`S3Destination`); the protocol keeps the queue,
/// tests, and a future second backend independent of S3 details.
nonisolated protocol Destination: Sendable {
    /// True when an object already exists at `key` (HTTP 200 on HEAD), false when it does not
    /// (404, or 403 from AWS S3 when the caller lacks `s3:ListBucket`; see `S3Destination.exists`).
    func exists(key: String) async throws -> Bool
    /// Uploads `data` to `key`. A non-nil `cacheControl` goes with the PUT as a signed
    /// `Cache-Control` header, which S3 stores with the object and returns on every GET.
    /// `progress` receives fractions in 0...1 from the transport thread.
    func upload(_ data: Data, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws
    /// Removes the object at `key`. Used by Delete (the capture's object, and any key its
    /// cancelled upload had reserved), by the cleanup of an object uploaded for a record that no
    /// longer exists, and by the connection test to remove its probe object.
    func delete(key: String) async throws
    /// Where `key` can be read from after upload.
    func publicURL(for key: String) throws -> URL
}

extension Destination {
    /// Uploads with no `Cache-Control`: every template upload and the connection test's probe.
    nonisolated func upload(_ data: Data, key: String, contentType: String,
                            progress: @escaping @Sendable (Double) -> Void) async throws {
        try await upload(data, key: key, contentType: contentType, cacheControl: nil, progress: progress)
    }
}

nonisolated struct UploadJob: Sendable, Identifiable {
    /// How the queue picks the object key.
    enum KeyPolicy: Sendable, Equatable {
        /// Named from the destination's key template when the upload starts, expanded against
        /// this context afresh for every key attempt (only `{random}` changes on a collision),
        /// and reserved with HEAD.
        case template(TemplateContext)
        /// Exactly this key, with no HEAD and nothing drawn from the template: the editor's
        /// replace of the record's own object at its own location. Every retry PUTs it again.
        case fixed(String)
    }

    /// Matches the `CaptureRecord.id` this upload belongs to.
    let id: UUID
    let data: Data
    let contentType: String
    /// Without a dot, for example `png`. Only template keys use it.
    let fileExtension: String
    let key: KeyPolicy
    /// Sent as a signed `Cache-Control` header on the PUT; nil sends none.
    let cacheControl: String?

    /// A job whose key is named from the template. It sends no `Cache-Control`.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, naming: TemplateContext = TemplateContext()) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.key = .template(naming)
        self.cacheControl = nil
    }

    /// A job that PUTs `fixedKey` as is. By default it sends `Cache-Control: no-cache`, so a cache
    /// that honours it revalidates the replaced object from now on. A copy a cache already holds
    /// stays until its own TTL expires.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, fixedKey: String,
         cacheControl: String? = "no-cache") {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.key = .fixed(fixedKey)
        self.cacheControl = cacheControl
    }
}

nonisolated enum UploadEvent: Sendable, Equatable {
    case started(id: UUID, attempt: Int)
    case progress(id: UUID, fraction: Double)
    case uploaded(id: UUID, url: URL, key: String)
    case failed(id: UUID, message: String)
    /// Terminal, like `.failed`, after `UploadQueue.cancel(recordID:)`. Never followed by `.failed`.
    /// `reservedKey` is the key the job had claimed (its fixed key, or the template key HEAD
    /// found free), nil when it was cancelled before it had one. Its PUT may have completed on
    /// the server, so a delete removes it too.
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
