import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// Answers requests from a per-test handler and records what was sent. State is keyed by the
/// `X-Stub-Session` header that each test's URLSession adds, so tests running in parallel never
/// see each other's handlers or requests. Entries are never removed; a test run makes a few dozen.
nonisolated final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) -> (status: Int, body: Data)
    /// Like `Handler`, plus response headers. A 3xx with a `Location` header is reported to
    /// URLSession as a redirect, so the session's redirect handling runs as it would for real.
    typealias HeaderHandler = @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)

    static let sessionHeader = "X-Stub-Session"
    /// Return this status from a handler to make the request fail with `URLError(.cannotFindHost)`.
    static let transportFailureStatus = -1

    struct Entry: Sendable {
        var handler: HeaderHandler
        var requests: [URLRequest] = []
    }

    static let entries = Mutex<[String: Entry]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let id = request.value(forHTTPHeaderField: Self.sessionHeader) ?? ""
        let handler = Self.entries.withLock { entries -> HeaderHandler? in
            entries[id]?.requests.append(request)
            return entries[id]?.handler
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let (status, headers, body) = handler(request)
        if status == Self.transportFailureStatus {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        if (300..<400).contains(status), let location = headers["Location"], let target = URL(string: location) {
            var redirect = request
            redirect.url = target
            client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// One test's stub: a URLSession routed through `StubURLProtocol` and the requests it sent.
nonisolated final class StubSession: Sendable {
    let id: String

    private init(id: String) {
        self.id = id
    }

    /// Registers `handler` under a fresh id and returns a session whose requests carry that id.
    static func make(handler: @escaping StubURLProtocol.Handler) -> (URLSession, StubSession) {
        make(headerHandler: { request in
            let (status, body) = handler(request)
            return (status, [:], body)
        })
    }

    /// Like `make(handler:)`, for stubs that need response headers.
    static func make(headerHandler handler: @escaping StubURLProtocol.HeaderHandler) -> (URLSession, StubSession) {
        let stub = StubSession(id: UUID().uuidString)
        StubURLProtocol.entries.withLock { $0[stub.id] = StubURLProtocol.Entry(handler: handler) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [StubURLProtocol.sessionHeader: stub.id]
        return (URLSession(configuration: configuration), stub)
    }

    /// Requests sent through this stub's session, in order.
    var requests: [URLRequest] {
        StubURLProtocol.entries.withLock { $0[id]?.requests ?? [] }
    }
}

struct S3DestinationTests {
    let credentials = AWSCredentials(accessKeyID: "AKIAIOSFODNN7EXAMPLE",
                                     secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    /// 2026-10-19T12:00:00Z
    let date = Date(timeIntervalSince1970: 1_792_411_200)
    let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                     publicURLTemplate: "https://snap.tky.io/{key}")
    let body = Data("hello".utf8)

    func destination(_ config: S3DestinationConfig, session: URLSession) -> S3Destination {
        S3Destination(config: config, credentials: credentials, session: session, now: { date })
    }

    /// Expected signature computed independently with a reference implementation.
    @Test func putIsSignedWithContentTypeAndNoACLByDefault() async throws {
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        try await destination(config, session: session).upload(body, key: "aSIS7.png", contentType: "image/png") { _ in }

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.absoluteString == "https://snap.s3.us-east-1.amazonaws.com/aSIS7.png")
        #expect(request.value(forHTTPHeaderField: "content-type") == "image/png")
        #expect(request.value(forHTTPHeaderField: "x-amz-acl") == nil)
        #expect(request.value(forHTTPHeaderField: "x-amz-date") == "20261019T120000Z")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=3ae54c07f6b6d4782a0ad2debd05c43fb93bcb0a1400d61138f78b140d700de9")
    }

    @Test func aclHeaderIsSentAndSignedWhenEnabled() async throws {
        var acl = config
        acl.sendPublicReadACL = true
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        try await destination(acl, session: session).upload(body, key: "aSIS7.png", contentType: "image/png") { _ in }

        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "x-amz-acl") == "public-read")
        #expect(request.value(forHTTPHeaderField: "authorization")?.hasSuffix("SignedHeaders=content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date, Signature=5a73cf67b570cbc19fd956f9a79769a4e94ba9415f3ff138609de89785481d5f") == true)
    }

    /// A replace asks caches to revalidate. The header is signed like the ACL. Expected signature
    /// computed independently with a reference implementation.
    @Test func cacheControlHeaderIsSignedWhenSet() async throws {
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        try await destination(config, session: session).upload(body, key: "aSIS7.png", contentType: "image/png",
                                                               cacheControl: "no-cache") { _ in }

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "cache-control") == "no-cache")
        #expect(request.value(forHTTPHeaderField: "content-type") == "image/png")
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=cache-control;content-type;host;x-amz-content-sha256;x-amz-date, Signature=fe15f0f7a62489905cb08be4bc4e9e1e48bbfe919082923c2815b55b122d49ed")
    }

    /// The four-argument call (template uploads, the connection test) and an explicit nil send no
    /// Cache-Control and do not sign one.
    @Test func noCacheControlByDefault() async throws {
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        try await destination(config, session: session).upload(body, key: "aSIS7.png", contentType: "image/png") { _ in }
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "cache-control") == nil)
        #expect(request.value(forHTTPHeaderField: "authorization")?.contains("SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date,") == true)

        let (explicitSession, explicitStub) = StubSession.make { _ in (200, Data()) }
        try await destination(config, session: explicitSession).upload(body, key: "aSIS7.png", contentType: "image/png",
                                                                       cacheControl: nil) { _ in }
        let explicit = try #require(explicitStub.requests.first)
        #expect(explicit.value(forHTTPHeaderField: "cache-control") == nil)
        #expect(explicit.value(forHTTPHeaderField: "authorization") == request.value(forHTTPHeaderField: "authorization"))
    }

    @Test func headUsesPathStyleAndPortedHost() async throws {
        var minio = config
        minio.endpoint = "http://localhost:9000"
        minio.usePathStyle = true
        let (session, stub) = StubSession.make { _ in (404, Data()) }
        let exists = try await destination(minio, session: session).exists(key: "aSIS7.png")

        #expect(exists == false)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "HEAD")
        #expect(request.url?.absoluteString == "http://localhost:9000/snap/aSIS7.png")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == S3Signer.emptyPayloadHash)
        #expect(request.value(forHTTPHeaderField: "authorization")?.hasSuffix("Signature=ea41793386c929fe127e31d41a7a6c0afa254275a313db5f86a9132ea8e68793") == true)
    }

    @Test func existsMapsStatusCodes() async throws {
        let (found, _) = StubSession.make { _ in (200, Data()) }
        #expect(try await destination(config, session: found).exists(key: "a.png") == true)

        let (broken, _) = StubSession.make { _ in (500, Data()) }
        await #expect(throws: UploadError.httpStatus(500, body: "")) {
            try await destination(config, session: broken).exists(key: "a.png")
        }
    }

    /// AWS S3 answers HEAD on a missing key with 403 when the key lacks s3:ListBucket.
    @Test func headTreats403AsMissing() async throws {
        let (session, stub) = StubSession.make { _ in (403, Data()) }
        #expect(try await destination(config, session: session).exists(key: "a.png") == false)
        #expect(stub.requests.map(\.httpMethod) == ["HEAD"])
    }

    @Test func uploadThrowsRetryableErrorOnServerFailure() async throws {
        let (session, _) = StubSession.make { _ in (500, Data("<Error>InternalError</Error>".utf8)) }
        await #expect(throws: UploadError.httpStatus(500, body: "<Error>InternalError</Error>")) {
            try await destination(config, session: session).upload(body, key: "a.png", contentType: "image/png") { _ in }
        }
        #expect(UploadError.httpStatus(500, body: "").isRetryable)
        #expect(!UploadError.httpStatus(403, body: "").isRetryable)
    }

    @Test func deleteAccepts204() async throws {
        let (session, stub) = StubSession.make { _ in (204, Data()) }
        try await destination(config, session: session).delete(key: "a.png")
        #expect(stub.requests.map(\.httpMethod) == ["DELETE"])
    }

    @Test func deleteAccepts404() async throws {
        let (session, stub) = StubSession.make { _ in (404, Data()) }
        try await destination(config, session: session).delete(key: "a.png")
        #expect(stub.requests.map(\.httpMethod) == ["DELETE"])
    }

    /// Delete builds its destination from the record's stored location. A dotted bucket is always
    /// addressed path-style, because a TLS wildcard cannot cover `snap.tky.io.s3.amazonaws.com`.
    @Test func deleteForDottedBucketUsesPathStyle() async throws {
        var dotted = config
        dotted.bucket = "snap.tky.io"
        let location = ObjectLocation(config: dotted)
        #expect(location.usePathStyle)
        let (session, stub) = StubSession.make { _ in (204, Data()) }
        try await destination(location.config, session: session).delete(key: "aB3dE9.png")

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://s3.us-east-1.amazonaws.com/snap.tky.io/aB3dE9.png")
        #expect(request.url?.path() == "/snap.tky.io/aB3dE9.png")
    }

    /// Copy Image downloads upload-only captures. Expected signature computed independently with
    /// a reference implementation.
    @Test func downloadIsASignedGetThatReturnsTheBody() async throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let (session, stub) = StubSession.make { _ in (200, png) }
        let data = try await destination(config, session: session).download(key: "aSIS7.png")

        #expect(data == png)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://snap.s3.us-east-1.amazonaws.com/aSIS7.png")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == S3Signer.emptyPayloadHash)
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=2b2032e36f0ecee5dda47c71b2b5cb033deed81114e1626e47639929cb0f7162")
    }

    @Test func downloadThrowsTheSummarisedErrorOnFailure() async throws {
        let xml = "<Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message></Error>"
        let (session, stub) = StubSession.make { _ in (404, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(404, body: "NoSuchKey: The specified key does not exist.")) {
            try await destination(config, session: session).download(key: "gone.png")
        }
        #expect(stub.requests.map(\.httpMethod) == ["GET"])
    }

    /// A downloaded capture must not stay in the container's on-disk URL cache after Delete. The
    /// request's cache policy only governs loading, not storing, so the session the app uses (the
    /// default) has no URL cache at all, and it is one shared session, not one per destination.
    @Test func defaultSessionHasNoURLCache() {
        let destination = S3Destination(config: config, credentials: credentials)
        #expect(destination.session === S3Destination.uncachedSession)
        #expect(destination.session.configuration.urlCache == nil)
    }

    @Test func errorBodyIsSummarisedFromS3XML() async throws {
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Error><Code>AccessDenied</Code><Message>Access Denied</Message><RequestId>x</RequestId></Error>"
        let (session, _) = StubSession.make { _ in (403, Data(xml.utf8)) }
        let error = await #expect(throws: UploadError.self) {
            try await destination(config, session: session).upload(body, key: "a.png", contentType: "image/png") { _ in }
        }
        #expect(error == .httpStatus(403, body: "AccessDenied: Access Denied"))
        let description = error?.localizedDescription ?? ""
        #expect(description.contains("AccessDenied: Access Denied"))
        #expect(!description.contains("RequestId"))
    }

    @Test func errorBodyIsTruncatedWhenNotXML() async throws {
        let plain = String(repeating: "x", count: 1000)
        let (session, _) = StubSession.make { _ in (400, Data(plain.utf8)) }
        let error = await #expect(throws: UploadError.self) {
            try await destination(config, session: session).upload(body, key: "a.png", contentType: "image/png") { _ in }
        }
        guard case .httpStatus(400, let summary) = error else {
            Issue.record("expected httpStatus(400, …), got \(String(describing: error))")
            return
        }
        #expect(summary.count == 200)
        let description = error?.localizedDescription ?? ""
        #expect(description.count(where: { $0 == "x" }) <= 200)
    }

    @Test func redirectIsNotFollowed() async throws {
        let (session, stub) = StubSession.make(headerHandler: { _ in
            (307, ["Location": "https://snap.s3.eu-west-1.amazonaws.com/a.png"], Data())
        })
        await #expect(throws: UploadError.httpStatus(307, body: "redirected to https://snap.s3.eu-west-1.amazonaws.com/a.png; check the endpoint and region")) {
            try await destination(config, session: session).upload(body, key: "a.png", contentType: "image/png") { _ in }
        }
        #expect(stub.requests.count == 1)
    }

    @Test func headErrorNamesBucketRegion() async throws {
        let (session, _) = StubSession.make(headerHandler: { _ in (301, ["x-amz-bucket-region": "eu-west-1"], Data()) })
        await #expect(throws: UploadError.httpStatus(301, body: "the bucket is in region eu-west-1")) {
            try await destination(config, session: session).exists(key: "a.png")
        }
    }
}
