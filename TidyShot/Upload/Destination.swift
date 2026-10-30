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
    /// Uploads the file at `url` to `key`, streamed from disk and never loaded into memory. The
    /// caller holds any security scope the file needs for the whole call. Otherwise as `upload`.
    func upload(fileAt url: URL, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws
    /// Downloads the object at `key` into a file at `destination`, replacing any file there. A
    /// failure leaves `destination` as it was. Never loads the object into memory.
    func download(key: String, to destination: URL) async throws
    /// Removes the object at `key`. Used by Delete (the capture's object, and any key its
    /// cancelled upload had reserved), by the cleanup of an object uploaded for a record that no
    /// longer exists, and by the connection test to remove its probe object.
    func delete(key: String) async throws
    /// Where `key` can be read from after upload.
    func publicURL(for key: String) throws -> URL

    // Multipart (R4). Each request is signed with its payload's SHA-256 and refuses redirects.

    /// CreateMultipartUpload at `key`, with the object's headers as `upload` sends them. Returns
    /// the upload id.
    func createMultipartUpload(key: String, contentType: String, cacheControl: String?) async throws -> String
    /// UploadPart: sends `data` as part `number` and returns the `ETag` S3 gave it, quotes included.
    /// `progress` receives the bytes sent since its last call, from the transport thread.
    /// Throws `UploadError.noSuchUpload` when the server no longer knows `uploadID`.
    func uploadPart(key: String, uploadID: String, number: Int, data: Data,
                    progress: @escaping @Sendable (Int64) -> Void) async throws -> String
    /// CompleteMultipartUpload with `parts` in ascending order. Throws `.completeError` for a 200
    /// that carries an `<Error>`, `.noSuchUpload`, and `.partsRejected` for `InvalidPart` or
    /// `InvalidPartOrder`.
    func completeMultipartUpload(key: String, uploadID: String, parts: [MultipartPart]) async throws
    /// AbortMultipartUpload. Both answers that leave nothing behind count as done; the result says which.
    func abortMultipartUpload(key: String, uploadID: String) async throws -> MultipartAbortResult
    /// Every part the server holds for `uploadID`, over as many ListParts pages as it takes.
    /// Throws `.noSuchUpload` when the server no longer knows `uploadID`.
    func listParts(key: String, uploadID: String) async throws -> [MultipartPart]
    /// The size of the object at `key` (HEAD), or nil when it is missing (404, or 403 for a key
    /// without `s3:ListBucket`, as `exists` reads it).
    func objectSize(key: String) async throws -> Int64?
}

/// What `abortMultipartUpload` got: 204 (`aborted`) or 404 (`notFound`, nothing left to abort).
nonisolated enum MultipartAbortResult: Equatable, Sendable {
    case aborted
    case notFound
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
    /// The bytes, or the file they stream from. It also picks the retry policy.
    let payload: UploadPayload
    let contentType: String
    /// Without a dot, for example `png`. Only template keys use it.
    let fileExtension: String
    let key: KeyPolicy
    /// Sent as a signed `Cache-Control` header on the PUT; nil sends none.
    let cacheControl: String?
    /// The file a `.file` job sends, as the coordinator read it. A job that has it and is at or
    /// over the plan's threshold goes multipart; without it the job uses the single PUT.
    var multipartSource: MultipartSource? = nil
    /// A stored multipart upload to resume.
    var resume: MultipartUploadState? = nil
    /// A stored multipart upload to abort before this job creates its own.
    var abortFirst: MultipartRef? = nil

    /// A job whose key is named from the template. It sends no `Cache-Control`.
    init(id: UUID, payload: UploadPayload, contentType: String, fileExtension: String,
         naming: TemplateContext = TemplateContext()) {
        self.id = id
        self.payload = payload
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.key = .template(naming)
        self.cacheControl = nil
    }

    /// A job that PUTs `fixedKey` as is. By default it sends `Cache-Control: no-cache`, so a cache
    /// that honours it revalidates the replaced object from now on. A copy a cache already holds
    /// stays until its own TTL expires.
    init(id: UUID, payload: UploadPayload, contentType: String, fileExtension: String, fixedKey: String,
         cacheControl: String? = "no-cache") {
        self.id = id
        self.payload = payload
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.key = .fixed(fixedKey)
        self.cacheControl = cacheControl
    }

    /// A template job for bytes in memory.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, naming: TemplateContext = TemplateContext()) {
        self.init(id: id, payload: .data(data), contentType: contentType, fileExtension: fileExtension, naming: naming)
    }

    /// A fixed-key job for bytes in memory.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, fixedKey: String,
         cacheControl: String? = "no-cache") {
        self.init(id: id, payload: .data(data), contentType: contentType, fileExtension: fileExtension,
                  fixedKey: fixedKey, cacheControl: cacheControl)
    }
}

nonisolated enum UploadEvent: Sendable, Equatable {
    /// `fraction` is where the bar starts: 0 for a single PUT and for a fresh multipart attempt.
    case started(id: UUID, attempt: Int, fraction: Double)
    /// A multipart upload was created, before any of its parts is sent. The record keeps `state`
    /// so a Retry can resume it and Delete knows what to abort.
    case multipartStarted(id: UUID, state: MultipartUploadState)
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
    /// The server no longer knows the multipart upload id (aborted, completed, or removed by a
    /// lifecycle rule). The queue handles it apart from the retry rule.
    case noSuchUpload
    /// Complete's `InvalidPart` or `InvalidPartOrder`; `body` as for `httpStatus`. The queue
    /// handles it apart from the retry rule.
    case partsRejected(body: String)
    /// A Complete answered 200 with an `<Error>` in its body; `body` as for `httpStatus`.
    case completeError(code: String, body: String)

    /// The `<Error>` codes of a 200 Complete that a 5xx or a 429 would carry.
    private static let retryableCompleteCodes: Set<String> = ["InternalError", "SlowDown", "ServiceUnavailable"]

    /// Server-side and transport failures are retried; client errors (bad credentials,
    /// missing bucket, forbidden) and a file that cannot be read are not.
    var isRetryable: Bool {
        switch self {
        case .httpStatus(let status, _): status >= 500 || status == 429
        case .noHTTPResponse: true
        case .completeError(let code, _): Self.retryableCompleteCodes.contains(code)
        case .keyCollisionsExhausted, .notConfigured, .fileUnreadable, .noSuchUpload, .partsRejected: false
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
        case .noSuchUpload: "The upload was no longer known to the server."
        case .partsRejected(let body): "The server rejected the upload's part list: \(body)"
        case .completeError(_, let body): "The server could not complete the upload: \(body)"
        }
    }

    /// The `URLError` codes for a file body URLSession cannot read. Retrying cannot help.
    private static let fileURLErrorCodes: Set<URLError.Code> = [.fileDoesNotExist, .noPermissionsToReadFile,
                                                                .cannotOpenFile, .fileIsDirectory]

    /// Whether an arbitrary error thrown during an upload attempt is worth retrying.
    /// Cancellation (`CancellationError` or `URLError(.cancelled)`) and an unreadable file
    /// (`fileURLErrorCodes`) are never retried; other `URLError`s are transport failures and are.
    static func isRetryable(_ error: Error) -> Bool {
        if let uploadError = error as? UploadError { return uploadError.isRetryable }
        if error is CancellationError { return false }
        guard let urlError = error as? URLError else { return false }
        return urlError.code != .cancelled && !fileURLErrorCodes.contains(urlError.code)
    }
}
