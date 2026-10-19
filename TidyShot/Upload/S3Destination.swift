import Foundation

/// PUT, HEAD and DELETE Object over URLSession with SigV4 headers. Works with AWS S3,
/// Cloudflare R2, Backblaze B2 and MinIO, which all speak the same three requests.
nonisolated struct S3Destination: Destination {
    let config: S3DestinationConfig
    let credentials: AWSCredentials
    let session: URLSession
    let now: @Sendable () -> Date

    init(config: S3DestinationConfig, credentials: AWSCredentials,
         session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
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
    func exists(key: String) async throws -> Bool {
        let request = try signedRequest(method: "HEAD", key: key, body: nil, extraHeaders: [])
        let (_, response) = try await session.data(for: request)
        let status = try Self.status(of: response)
        switch status {
        case 200: return true
        case 403, 404: return false
        default: throw UploadError.httpStatus(status, body: "")
        }
    }

    func upload(_ data: Data, key: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        var headers = [(name: "content-type", value: contentType)]
        if config.sendPublicReadACL {
            headers.append((name: "x-amz-acl", value: "public-read"))
        }
        let request = try signedRequest(method: "PUT", key: key, body: data, extraHeaders: headers)
        let delegate = UploadProgressDelegate(onProgress: progress)
        let (body, response) = try await session.upload(for: request, from: data, delegate: delegate)
        let status = try Self.status(of: response)
        guard (200..<300).contains(status) else {
            throw UploadError.httpStatus(status, body: Self.excerpt(body))
        }
    }

    func delete(key: String) async throws {
        let request = try signedRequest(method: "DELETE", key: key, body: nil, extraHeaders: [])
        let (body, response) = try await session.data(for: request)
        let status = try Self.status(of: response)
        guard (200..<300).contains(status) || status == 404 else {
            throw UploadError.httpStatus(status, body: Self.excerpt(body))
        }
    }

    func publicURL(for key: String) throws -> URL {
        try config.publicURL(for: key)
    }

    /// Builds the request for `key` and signs it. `host` and `x-amz-content-sha256` are always
    /// signed; `extraHeaders` are signed too. Visible for tests.
    func signedRequest(method: String, key: String, body: Data?,
                       extraHeaders: [(name: String, value: String)]) throws -> URLRequest {
        let url = try config.objectURL(for: key)
        let payloadHash = body.map(S3Signer.sha256Hex) ?? S3Signer.emptyPayloadHash
        var headers = extraHeaders
        headers.append((name: "host", value: config.hostHeader(for: url)))
        headers.append((name: "x-amz-content-sha256", value: payloadHash))

        let signed = S3Signer.sign(
            S3Signer.Request(method: method, path: config.objectPath(for: key), headers: headers, payloadHash: payloadHash),
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

    private static func status(of response: URLResponse) throws -> Int {
        guard let http = response as? HTTPURLResponse else { throw UploadError.noHTTPResponse }
        return http.statusCode
    }

    /// First 200 characters of an error body, so notifications never show a wall of S3 XML.
    private static func excerpt(_ body: Data) -> String {
        String(String(decoding: body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(200))
    }
}
