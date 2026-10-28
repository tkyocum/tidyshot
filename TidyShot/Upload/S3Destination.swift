import Foundation

/// PUT, HEAD, GET and DELETE Object over URLSession with SigV4 headers. Works with AWS S3,
/// Cloudflare R2, Backblaze B2 and MinIO, which all speak the same four requests. The multipart
/// calls are in `S3Destination+Multipart.swift`.
nonisolated struct S3Destination: Destination {
    let config: S3DestinationConfig
    let credentials: AWSCredentials
    let session: URLSession
    let now: @Sendable () -> Date

    /// The session every request uses unless a test passes its own. It has no URL cache: a GET's
    /// response (a capture downloaded for Copy Image, often sensitive) would otherwise be stored in
    /// the container's on-disk cache and stay there after Delete. The request's
    /// `reloadIgnoringLocalAndRemoteCacheData` only governs loading, not storing, and a per-task
    /// `willCacheResponse` is never called for `data(for:delegate:)`, so only a session without a
    /// cache prevents it. Ephemeral, so cookies and credentials are not persisted either. One
    /// session for all destinations, because a URLSession lives until it is invalidated.
    static let uncachedSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    init(config: S3DestinationConfig, credentials: AWSCredentials,
         session: URLSession = S3Destination.uncachedSession, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config.normalized
        self.credentials = credentials
        self.session = session
        self.now = now
    }

    /// HEAD Object. 200 means the key is taken; 404 and 403 both mean "use it".
    ///
    /// 403 counts as missing because AWS S3 answers HEAD on a missing key with 403, not 404,
    /// when the caller lacks `s3:ListBucket`, which is the normal setup for an upload-only IAM
    /// key. Cloudflare R2, Backblaze B2 and MinIO answer 404. A key that also lacks
    /// `s3:GetObject` gets 403 even for keys that exist, so for such a key the collision check
    /// cannot see collisions; with 62^6 possible names that risk is accepted. Wrong credentials
    /// are not hidden by this: the PUT that follows fails with its own 403.
    ///
    /// Any other status is an error. HEAD has no body, so when S3 sends `x-amz-bucket-region`
    /// (as it does when the configured region is wrong) that region becomes the error text.
    func exists(key: String) async throws -> Bool {
        let request = try signedRequest(method: "HEAD", key: key, body: nil, extraHeaders: [])
        let (_, response) = try await session.data(for: request, delegate: UploadProgressDelegate())
        let http = try Self.httpResponse(response)
        switch http.statusCode {
        case 200: return true
        case 403, 404: return false
        default:
            let regionHint = http.value(forHTTPHeaderField: "x-amz-bucket-region").map { "the bucket is in region \($0)" }
            throw Self.failure(http, bodyText: regionHint ?? "")
        }
    }

    func upload(_ data: Data, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        let headers = putHeaders(contentType: contentType, cacheControl: cacheControl)
        let request = try signedRequest(method: "PUT", key: key, body: data, extraHeaders: headers)
        let delegate = UploadProgressDelegate(onProgress: progress)
        let (body, response) = try await session.upload(for: request, from: data, delegate: delegate)
        try Self.checkPut(body, response)
    }

    /// Hashes the file off the actor, signs with that hash, and streams the file as the body.
    /// URLSession sets `Content-Length` itself for a file body, so it is neither set nor signed.
    func upload(fileAt url: URL, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        let payloadHash = try await S3Signer.sha256Hex(fileAt: url)
        let headers = putHeaders(contentType: contentType, cacheControl: cacheControl)
        let request = try signedRequest(method: "PUT", key: key, payloadHash: payloadHash, extraHeaders: headers)
        let delegate = UploadProgressDelegate(onProgress: progress)
        let (body, response) = try await session.upload(for: request, fromFile: url, delegate: delegate)
        try Self.checkPut(body, response)
    }

    /// The PUT's extra headers, all signed, so a change in transit fails the signature.
    private func putHeaders(contentType: String, cacheControl: String?) -> [(name: String, value: String)] {
        var headers = [(name: "content-type", value: contentType)]
        if let cacheControl {
            headers.append((name: "cache-control", value: cacheControl))
        }
        if config.sendPublicReadACL {
            headers.append((name: "x-amz-acl", value: "public-read"))
        }
        return headers
    }

    private static func checkPut(_ body: Data, _ response: URLResponse) throws {
        let http = try httpResponse(response)
        guard (200..<300).contains(http.statusCode) else {
            throw failure(http, bodyText: excerpt(body))
        }
    }

    func delete(key: String) async throws {
        let request = try signedRequest(method: "DELETE", key: key, body: nil, extraHeaders: [])
        let (body, response) = try await session.data(for: request, delegate: UploadProgressDelegate())
        let http = try Self.httpResponse(response)
        guard (200..<300).contains(http.statusCode) || http.statusCode == 404 else {
            throw Self.failure(http, bodyText: Self.excerpt(body))
        }
    }

    /// GET Object, signed like the other requests (the bucket need not be public). Copy Image uses
    /// it for captures that have no local file. Unlike `delete`, a 404 is an error: there is
    /// nothing to copy.
    func download(key: String) async throws -> Data {
        let request = try signedRequest(method: "GET", key: key, body: nil, extraHeaders: [])
        let (body, response) = try await session.data(for: request, delegate: UploadProgressDelegate())
        let http = try Self.httpResponse(response)
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(http, bodyText: Self.excerpt(body))
        }
        return body
    }

    /// GET Object streamed to a temporary file, for a recording, which is never loaded into
    /// memory. On 2xx the file moves to `destination` through `FileReplacement`, replacing any
    /// file there (the save panel already asked). Otherwise the error body, which is small, is
    /// read from the temporary file for the usual error, and the temporary file is removed.
    /// Redirects are refused. The file work runs where the caller runs, so callers on the main
    /// actor call it from a detached task.
    func download(key: String, to destination: URL) async throws {
        let request = try signedRequest(method: "GET", key: key, payloadHash: S3Signer.emptyPayloadHash, extraHeaders: [])
        let (temporary, response) = try await session.download(for: request, delegate: UploadProgressDelegate())
        // The async download leaves its file for the caller; nothing else removes it.
        defer { try? FileManager.default.removeItem(at: temporary) }
        let http = try Self.httpResponse(response)
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(http, bodyText: Self.excerpt(Self.errorBody(at: temporary)))
        }
        try FileReplacement.put(at: destination) { try FileManager.default.moveItem(at: temporary, to: $0) }
    }

    /// The first 64 KiB of an error response saved to a file. An S3 error body is far smaller, and
    /// `excerpt` keeps only 200 characters, so a large body from elsewhere is never read whole.
    private static func errorBody(at url: URL) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 64 * 1024)) ?? Data()
    }

    func publicURL(for key: String) throws -> URL {
        try config.publicURL(for: key)
    }

    /// Builds the request for `key` and signs it with the hash of `body` (none for HEAD, GET and
    /// DELETE). Visible for tests.
    func signedRequest(method: String, key: String, body: Data?,
                       extraHeaders: [(name: String, value: String)]) throws -> URLRequest {
        try signedRequest(method: method, key: key, payloadHash: body.map(S3Signer.sha256Hex) ?? S3Signer.emptyPayloadHash,
                          extraHeaders: extraHeaders)
    }

    /// Builds the request for `key` and signs it with a payload hash worked out already (a file's,
    /// from `S3Signer.sha256Hex(fileAt:)`). Visible for tests.
    func signedRequest(method: String, key: String, payloadHash: String,
                       extraHeaders: [(name: String, value: String)]) throws -> URLRequest {
        try signedRequest(method: method, key: key, query: [], payloadHash: payloadHash, extraHeaders: extraHeaders)
    }

    /// Builds the request for `key` with `query` (decoded pairs) and signs it with `payloadHash`.
    /// The URL's query and the canonical query both come from `query`, so they cannot disagree.
    /// `host` and `x-amz-content-sha256` are always signed; `extraHeaders` are signed too.
    /// Visible for tests.
    func signedRequest(method: String, key: String, query: [(name: String, value: String)], payloadHash: String,
                       extraHeaders: [(name: String, value: String)]) throws -> URLRequest {
        let url = try config.objectURL(for: key, query: query)
        var headers = extraHeaders
        headers.append((name: "host", value: config.hostHeader(for: url)))
        headers.append((name: "x-amz-content-sha256", value: payloadHash))

        let signed = S3Signer.sign(
            S3Signer.Request(method: method, path: config.objectPath(for: key), query: query, headers: headers,
                             payloadHash: payloadHash),
            credentials: credentials, region: config.region, date: now())

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // URLSession sets Host itself from the URL; setting it here is ignored, so skip it.
        for header in headers where header.name != "host" {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        for header in signed.headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }

    static func httpResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw UploadError.noHTTPResponse }
        return http
    }

    /// The error for a non-success response. Redirects are never followed (see
    /// `UploadProgressDelegate`), so a 3xx with a `Location` names where the server pointed,
    /// which usually means the endpoint or region is wrong.
    static func failure(_ http: HTTPURLResponse, bodyText: String) -> UploadError {
        let status = http.statusCode
        if (300..<400).contains(status), let location = http.value(forHTTPHeaderField: "Location") {
            return .httpStatus(status, body: "redirected to \(location.prefix(200)); check the endpoint and region")
        }
        return .httpStatus(status, body: bodyText)
    }

    /// A short, readable summary of an error body for notifications and the settings tab.
    ///
    /// SECURITY: the 200-character cap is load-bearing. A `SignatureDoesNotMatch` body echoes
    /// the canonical request and string to sign, and the canonical request can include the
    /// `x-amz-security-token` header, that is, the session token. The structured parse below
    /// must only ever read `<Code>` and `<Message>`; never add `<CanonicalRequest>`,
    /// `<StringToSign>` or any other element to it. A body without a usable `<Code>` falls back
    /// to its first 200 characters.
    static func excerpt(_ body: Data) -> String {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = elementText("Code", in: text) {
            let summary = elementText("Message", in: text).map { "\(code): \($0)" } ?? code
            return String(summary.prefix(200))
        }
        return String(text.prefix(200))
    }

    /// The text of the first `<name>…</name>` in `text`, or nil when it is missing, empty, or
    /// contains markup (which would mean other elements are nested inside it).
    private static func elementText(_ name: String, in text: String) -> String? {
        guard let open = text.firstRange(of: "<\(name)>"),
              let close = text[open.upperBound...].firstRange(of: "</\(name)>") else { return nil }
        let value = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("<") else { return nil }
        return value
    }
}
