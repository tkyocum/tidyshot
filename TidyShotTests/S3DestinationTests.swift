import Foundation
import Synchronization
import Testing
@testable import TidyShot

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

    // MARK: Files

    /// A fresh folder for one test; the caller removes it.
    func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "S3DestinationTests-\(UUID().uuidString)",
                                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The PUT streams the file's bytes, signed with the file's hash. The signature equals the
    /// in-memory upload's for the same bytes (`putIsSignedWithContentTypeAndNoACLByDefault`).
    @Test func fileUploadSendsTheFilesBytes() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Recording.mp4")
        try body.write(to: file)
        let received = Mutex<Data?>(nil)
        let (session, stub) = StubSession.make { request in
            received.withLock { $0 = StubURLProtocol.bodyBytes(of: request) }
            return (200, Data())
        }
        let fractions = Mutex<[Double]>([])
        try await destination(config, session: session).upload(fileAt: file, key: "aSIS7.png", contentType: "image/png",
                                                                cacheControl: nil) { fraction in
            fractions.withLock { $0.append(fraction) }
        }

        #expect(received.withLock { $0 } == body)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "content-type") == "image/png")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=3ae54c07f6b6d4782a0ad2debd05c43fb93bcb0a1400d61138f78b140d700de9")
        // The file is still there: the upload never moves or removes it.
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    /// A video's PUT signs `Cache-Control` and the ACL like an image's.
    @Test func fileUploadSignsCacheControlAndACL() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Recording.mp4")
        try body.write(to: file)
        var acl = config
        acl.sendPublicReadACL = true
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        try await destination(acl, session: session).upload(fileAt: file, key: "a.mp4", contentType: "video/mp4",
                                                             cacheControl: "no-cache") { _ in }

        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "content-type") == "video/mp4")
        #expect(request.value(forHTTPHeaderField: "cache-control") == "no-cache")
        #expect(request.value(forHTTPHeaderField: "x-amz-acl") == "public-read")
        #expect(request.value(forHTTPHeaderField: "authorization")?
            .contains("SignedHeaders=cache-control;content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date,") == true)
    }

    @Test func fileUploadThrowsTheSummarisedError() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "Recording.mp4")
        try body.write(to: file)
        let xml = "<Error><Code>EntityTooLarge</Code><Message>Your proposed upload exceeds the maximum allowed size</Message></Error>"
        let (session, _) = StubSession.make { _ in (400, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(400, body: "EntityTooLarge: Your proposed upload exceeds the maximum allowed size")) {
            try await destination(config, session: session).upload(fileAt: file, key: "a.mp4", contentType: "video/mp4",
                                                                   cacheControl: nil) { _ in }
        }
    }

    /// A file that is gone fails before any request is sent, and is not retried.
    @Test func fileUploadOfAMissingFileSendsNothing() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        let error = await #expect(throws: (any Error).self) {
            try await destination(config, session: session).upload(fileAt: folder.appending(path: "gone.mp4"), key: "a.mp4",
                                                                   contentType: "video/mp4", cacheControl: nil) { _ in }
        }
        #expect(stub.requests.isEmpty)
        #expect(error.map(UploadError.isRetryable) == false)
    }

    @Test func downloadToAFileWritesTheBody() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        let movie = Data((0..<100_000).map { UInt8(truncatingIfNeeded: $0) })
        let (session, stub) = StubSession.make { _ in (200, movie) }
        try await destination(config, session: session).download(key: "aSIS7.png", to: target)

        #expect(try Data(contentsOf: target) == movie)
        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://snap.s3.us-east-1.amazonaws.com/aSIS7.png")
        // The same signed GET as `download(key:)`.
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=2b2032e36f0ecee5dda47c71b2b5cb033deed81114e1626e47639929cb0f7162")
    }

    /// The save panel already asked to replace it.
    @Test func downloadToAFileReplacesAnExistingFile() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        try Data("old contents that are longer".utf8).write(to: target)
        let (session, _) = StubSession.make { _ in (200, Data("new".utf8)) }
        try await destination(config, session: session).download(key: "a.mp4", to: target)

        #expect(try Data(contentsOf: target) == Data("new".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Recording.mp4"])
    }

    @Test func downloadFailureLeavesNoFile() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        let xml = "<Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message></Error>"
        let (session, _) = StubSession.make { _ in (404, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(404, body: "NoSuchKey: The specified key does not exist.")) {
            try await destination(config, session: session).download(key: "gone.mp4", to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).isEmpty)
    }

    /// A failed download leaves an existing file as it was.
    @Test func downloadFailureKeepsAnExistingFile() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        try Data("mine".utf8).write(to: target)
        let (session, _) = StubSession.make { _ in (403, Data()) }
        await #expect(throws: UploadError.httpStatus(403, body: "")) {
            try await destination(config, session: session).download(key: "a.mp4", to: target)
        }
        #expect(try Data(contentsOf: target) == Data("mine".utf8))
    }

    @Test func downloadToAFileRefusesRedirects() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        let (session, stub) = StubSession.make(headerHandler: { _ in
            (307, ["Location": "https://snap.s3.eu-west-1.amazonaws.com/a.mp4"], Data())
        })
        await #expect(throws: UploadError.httpStatus(307, body: "redirected to https://snap.s3.eu-west-1.amazonaws.com/a.mp4; check the endpoint and region")) {
            try await destination(config, session: session).download(key: "a.mp4", to: target)
        }
        #expect(stub.requests.count == 1)
        #expect(!FileManager.default.fileExists(atPath: target.path(percentEncoded: false)))
    }

    // MARK: Multipart

    /// Tim's dotted bucket, addressed path-style, with the ACL on.
    var multipartConfig: S3DestinationConfig {
        var dotted = config
        dotted.bucket = "snap.tky.io"
        dotted.sendPublicReadACL = true
        return dotted
    }

    func multipartDestination(_ bucket: StubMultipartBucket) -> S3Destination {
        destination(multipartConfig, session: bucket.session)
    }

    func makeBucket(_ state: StubMultipartBucket.State = .init()) -> StubMultipartBucket {
        StubMultipartBucket(bucket: "snap.tky.io", credentials: credentials, region: "us-east-1", date: date, state: state)
    }

    /// Every request the bucket saw carried the hash of its own body and a signature over its own
    /// URL's query, so what was sent and what was signed agree.
    func expectEverySignatureHolds(_ bucket: StubMultipartBucket) {
        let received = bucket.state.withLock { $0.received }
        #expect(!received.isEmpty)
        for request in received {
            #expect(request.contentSHA256 == S3Signer.sha256Hex(request.body), "\(request.method) \(request.query)")
            #expect(request.signatureMatches, "\(request.method) \(request.query)")
        }
    }

    @Test func createReturnsAnIDAndStoresTheSignedHeaders() async throws {
        let bucket = makeBucket()
        let id = try await multipartDestination(bucket).createMultipartUpload(key: "r/Recording.mp4", contentType: "video/mp4",
                                                                              cacheControl: "no-cache")

        let upload = try #require(bucket.state.withLock { $0.uploads[id] })
        #expect(upload.key == "r/Recording.mp4")
        #expect(upload.headers == ["content-type": "video/mp4", "cache-control": "no-cache", "x-amz-acl": "public-read"])
        let request = try #require(bucket.state.withLock { $0.received.first })
        #expect(request.method == "POST")
        #expect(request.query == ["uploads": ""])
        #expect(request.signedHeaders == "cache-control;content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date")
        expectEverySignatureHolds(bucket)
    }

    /// Without a cache control and without the ACL, neither is sent or signed.
    @Test func createWithoutCacheControlOrACL() async throws {
        let bucket = makeBucket()
        var plain = multipartConfig
        plain.sendPublicReadACL = false
        let id = try await destination(plain, session: bucket.session).createMultipartUpload(
            key: "r/Recording.mp4", contentType: "image/gif", cacheControl: nil)

        #expect(bucket.state.withLock { $0.uploads[id]?.headers } == ["content-type": "image/gif"])
        #expect(bucket.state.withLock { $0.received.first?.signedHeaders } == "content-type;host;x-amz-content-sha256;x-amz-date")
    }

    @Test func createWithoutUploadIDFails() async throws {
        let (session, _) = StubSession.make { _ in (200, Data("<InitiateMultipartUploadResult/>".utf8)) }
        await #expect(throws: UploadError.httpStatus(200, body: "no UploadId")) {
            try await destination(multipartConfig, session: session).createMultipartUpload(
                key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        }
    }

    @Test func createFailureIsSummarised() async throws {
        let xml = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>"
        let (session, _) = StubSession.make { _ in (403, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(403, body: "AccessDenied: Access Denied")) {
            try await destination(multipartConfig, session: session).createMultipartUpload(
                key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        }
    }

    @Test func partIsStoredWithAnETagAndReplacesAnEarlierPart() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)

        let first = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("first".utf8)) { _ in }
        #expect(bucket.state.withLock { $0.uploads[id]?.parts[1] } == StubMultipartBucket.Part(etag: first, data: Data("first".utf8)))
        let second = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("again".utf8)) { _ in }
        #expect(second != first)
        #expect(bucket.state.withLock { $0.uploads[id]?.parts } == [1: StubMultipartBucket.Part(etag: second, data: Data("again".utf8))])

        let part = try #require(bucket.state.withLock { $0.received.last })
        #expect(part.method == "PUT")
        #expect(part.query == ["partNumber": "1", "uploadId": id])
        #expect(part.body == Data("again".utf8))
        expectEverySignatureHolds(bucket)
    }

    @Test func partWithoutETagFails() async throws {
        let (session, _) = StubSession.make { _ in (200, Data()) }
        await #expect(throws: UploadError.httpStatus(200, body: "no ETag")) {
            try await destination(multipartConfig, session: session).uploadPart(key: "r/a.mp4", uploadID: "u", number: 1,
                                                                                data: Data("x".utf8)) { _ in }
        }
    }

    @Test func partServerFailureIsRetryable() async throws {
        let (session, _) = StubSession.make { _ in (503, Data("<Error><Code>SlowDown</Code></Error>".utf8)) }
        let error = await #expect(throws: UploadError.self) {
            try await destination(multipartConfig, session: session).uploadPart(key: "r/a.mp4", uploadID: "u", number: 1,
                                                                                data: Data("x".utf8)) { _ in }
        }
        #expect(error == .httpStatus(503, body: "SlowDown"))
        #expect(error?.isRetryable == true)
    }

    /// A whole upload: three parts out of order, ListParts, Complete, then the object's size.
    @Test func completeJoinsThePartsInOrder() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: "no-cache")
        var parts: [MultipartPart] = []
        for (number, text) in [(3, "ccc"), (1, "aaaaa"), (2, "bbbbb")] {
            let etag = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: number, data: Data(text.utf8)) { _ in }
            parts.append(MultipartPart(number: number, etag: etag, size: Int64(text.utf8.count)))
        }

        #expect(try await destination.listParts(key: "r/a.mp4", uploadID: id) == parts.sorted { $0.number < $1.number })
        try await destination.completeMultipartUpload(key: "r/a.mp4", uploadID: id, parts: parts)

        let object = try #require(bucket.state.withLock { $0.objects["r/a.mp4"] })
        #expect(object.data == Data("aaaaabbbbbccc".utf8))
        #expect(object.headers["cache-control"] == "no-cache")
        #expect(object.headers["x-amz-acl"] == "public-read")
        #expect(bucket.state.withLock { $0.uploads.isEmpty })
        #expect(try await destination.objectSize(key: "r/a.mp4") == 13)

        let complete = try #require(bucket.state.withLock { $0.received.first { $0.method == "POST" && $0.query["uploads"] == nil } })
        #expect(complete.contentType == "application/xml")
        #expect(complete.query == ["uploadId": id])
        expectEverySignatureHolds(bucket)
    }

    /// The bucket, as AWS does, refuses a Complete with no type or URLSession's form type, so the
    /// passing Complete above shows the call sends its own.
    @Test(arguments: [nil, "application/x-www-form-urlencoded"])
    func completeWithoutTheXMLTypeFails(contentType: String?) async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        let etag = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }

        let call = MultipartRequests.complete(uploadID: id, parts: [MultipartPart(number: 1, etag: etag, size: 1)])
        let headers = contentType.map { [(name: "content-type", value: $0)] } ?? []
        let request = try destination.signedRequest(method: "POST", key: "r/a.mp4", query: call.query,
                                                    payloadHash: call.payloadHash, extraHeaders: headers)
        let (answer, response) = try await bucket.session.upload(for: request, from: call.body)
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
        #expect(MultipartXML.error(in: answer)?.code == "MalformedXML")
        #expect(bucket.state.withLock { $0.objects.isEmpty })
        expectEverySignatureHolds(bucket)
    }

    @Test func completeWithAWrongETagIsPartsRejected() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        _ = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }

        let error = await #expect(throws: UploadError.self) {
            try await destination.completeMultipartUpload(key: "r/a.mp4", uploadID: id,
                                                          parts: [MultipartPart(number: 1, etag: "\"stale\"", size: 1)])
        }
        guard case .partsRejected(let body) = error else {
            Issue.record("expected partsRejected, got \(String(describing: error))")
            return
        }
        #expect(body.hasPrefix("InvalidPart: "))
        #expect(error?.isRetryable == false)
    }

    @Test func completeWithAMissingPartIsPartsRejected() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        let etag = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }

        let error = await #expect(throws: UploadError.self) {
            try await destination.completeMultipartUpload(key: "r/a.mp4", uploadID: id, parts: [
                MultipartPart(number: 1, etag: etag, size: 1), MultipartPart(number: 2, etag: etag, size: 1),
            ])
        }
        guard case .partsRejected(let body) = error else {
            Issue.record("expected partsRejected, got \(String(describing: error))")
            return
        }
        #expect(body.hasPrefix("InvalidPart: "))
    }

    /// `MultipartRequests` always sorts, so the order check is reached with a hand-made body.
    @Test func bucketRefusesPartsOutOfOrder() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        let one = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }
        let two = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 2, data: Data("b".utf8)) { _ in }

        let body = Data("<CompleteMultipartUpload><Part><PartNumber>2</PartNumber><ETag>\(two)</ETag></Part><Part><PartNumber>1</PartNumber><ETag>\(one)</ETag></Part></CompleteMultipartUpload>".utf8)
        let request = try destination.signedRequest(method: "POST", key: "r/a.mp4", query: [(name: "uploadId", value: id)],
                                                    payloadHash: S3Signer.sha256Hex(body),
                                                    extraHeaders: [(name: "content-type", value: "application/xml")])
        let (answer, response) = try await bucket.session.upload(for: request, from: body)
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
        #expect(MultipartXML.error(in: answer)?.code == "InvalidPartOrder")
        expectEverySignatureHolds(bucket)
    }

    /// The one test with S3's 5 MiB minimum on: every part but the last must reach it.
    @Test func completeWithASmallPartIsEntityTooSmall() async throws {
        let bucket = makeBucket(.init(minimumPartSize: 5 * 1024 * 1024))
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        let small = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }
        let last = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 2, data: Data("b".utf8)) { _ in }

        let error = await #expect(throws: UploadError.self) {
            try await destination.completeMultipartUpload(key: "r/a.mp4", uploadID: id, parts: [
                MultipartPart(number: 1, etag: small, size: 1), MultipartPart(number: 2, etag: last, size: 1),
            ])
        }
        guard case .httpStatus(400, let body) = error else {
            Issue.record("expected httpStatus(400, …), got \(String(describing: error))")
            return
        }
        #expect(body.hasPrefix("EntityTooSmall: "))
        #expect(error?.isRetryable == false)
    }

    /// With the minimum on, a large first part and a small last part complete.
    @Test func completeAcceptsASmallLastPart() async throws {
        let bucket = makeBucket(.init(minimumPartSize: 5 * 1024 * 1024))
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        let big = Data(count: 5 * 1024 * 1024)
        let first = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: big) { _ in }
        let last = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 2, data: Data("b".utf8)) { _ in }

        try await destination.completeMultipartUpload(key: "r/a.mp4", uploadID: id, parts: [
            MultipartPart(number: 1, etag: first, size: Int64(big.count)), MultipartPart(number: 2, etag: last, size: 1),
        ])
        #expect(bucket.state.withLock { $0.objects["r/a.mp4"]?.data.count } == big.count + 1)
        expectEverySignatureHolds(bucket)
    }

    @Test(arguments: ["InternalError", "EntityTooLarge"])
    func completeAnswering200WithAnErrorThrowsCompleteError(code: String) async throws {
        let answer = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\n<Error><Code>\(code)</Code><Message>Please try again.</Message><RequestId>656c</RequestId></Error>"
        let bucket = makeBucket(.init(completeAnswer: (status: 200, body: Data(answer.utf8))))
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        let etag = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }

        await #expect(throws: UploadError.completeError(code: code, body: "\(code): Please try again.")) {
            try await destination.completeMultipartUpload(key: "r/a.mp4", uploadID: id,
                                                          parts: [MultipartPart(number: 1, etag: etag, size: 1)])
        }
        #expect(UploadError.completeError(code: code, body: "").isRetryable == (code == "InternalError"))
    }

    @Test func completeOtherFailureIsHTTPStatus() async throws {
        let xml = "<Error><Code>EntityTooLarge</Code><Message>Your proposed upload exceeds the maximum allowed size</Message></Error>"
        let (session, _) = StubSession.make { _ in (400, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(400, body: "EntityTooLarge: Your proposed upload exceeds the maximum allowed size")) {
            try await destination(multipartConfig, session: session).completeMultipartUpload(
                key: "r/a.mp4", uploadID: "u", parts: [MultipartPart(number: 1, etag: "\"e\"", size: 1)])
        }
    }

    @Test func abortGives204Then404() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        _ = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }

        #expect(try await destination.abortMultipartUpload(key: "r/a.mp4", uploadID: id) == .aborted)
        #expect(bucket.state.withLock { $0.uploads.isEmpty })
        #expect(try await destination.abortMultipartUpload(key: "r/a.mp4", uploadID: id) == .notFound)
        #expect(bucket.state.withLock { $0.received.suffix(2).map(\.method) } == ["DELETE", "DELETE"])
        #expect(bucket.state.withLock { $0.received.last?.query } == ["uploadId": id])
        expectEverySignatureHolds(bucket)
    }

    @Test func abortOtherFailureThrows() async throws {
        let xml = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>"
        let (session, _) = StubSession.make { _ in (403, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(403, body: "AccessDenied: Access Denied")) {
            try await destination(multipartConfig, session: session).abortMultipartUpload(key: "r/a.mp4", uploadID: "u")
        }
    }

    /// Five parts at a page size of 2 take three pages, each asking from the last page's marker.
    /// The bucket sends `NextPartNumberMarker` on the last page too, as AWS does.
    @Test func listPartsPagesUntilNotTruncated() async throws {
        let bucket = makeBucket(.init(listPageSize: 2))
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        var parts: [MultipartPart] = []
        for number in 1...5 {
            let data = Data(repeating: UInt8(number), count: number)
            let etag = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: number, data: data) { _ in }
            parts.append(MultipartPart(number: number, etag: etag, size: Int64(number)))
        }

        #expect(try await destination.listParts(key: "r/a.mp4", uploadID: id) == parts)
        let lists = bucket.state.withLock { $0.received.filter { $0.method == "GET" } }
        #expect(lists.map { $0.query["part-number-marker"] } == [nil, "2", "4"])
        #expect(lists.allSatisfy { $0.query["uploadId"] == id })
        expectEverySignatureHolds(bucket)
    }

    @Test func listPartsOfAnEmptyUpload() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        #expect(try await destination.listParts(key: "r/a.mp4", uploadID: id) == [])
    }

    @Test func unreadablePartListFails() async throws {
        let (session, _) = StubSession.make { _ in (200, Data("<html>gateway</html>".utf8)) }
        await #expect(throws: UploadError.httpStatus(200, body: "unreadable part list")) {
            try await destination(multipartConfig, session: session).listParts(key: "r/a.mp4", uploadID: "u")
        }
    }

    /// A 403 (a key without `s3:ListMultipartUploadParts`) is an ordinary failure.
    @Test func listPartsForbiddenIsHTTPStatus() async throws {
        let xml = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>"
        let (session, _) = StubSession.make { _ in (403, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(403, body: "AccessDenied: Access Denied")) {
            try await destination(multipartConfig, session: session).listParts(key: "r/a.mp4", uploadID: "u")
        }
    }

    /// An id the server no longer knows: a part, ListParts and Complete throw `noSuchUpload`, and
    /// Abort counts it as done.
    @Test func noSuchUploadOnEveryCall() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        let etag = try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 1, data: Data("a".utf8)) { _ in }
        bucket.state.withLock { _ = $0.missingUploads.insert(id) }

        await #expect(throws: UploadError.noSuchUpload) {
            try await destination.uploadPart(key: "r/a.mp4", uploadID: id, number: 2, data: Data("b".utf8)) { _ in }
        }
        await #expect(throws: UploadError.noSuchUpload) {
            try await destination.listParts(key: "r/a.mp4", uploadID: id)
        }
        await #expect(throws: UploadError.noSuchUpload) {
            try await destination.completeMultipartUpload(key: "r/a.mp4", uploadID: id,
                                                          parts: [MultipartPart(number: 1, etag: etag, size: 1)])
        }
        #expect(try await destination.abortMultipartUpload(key: "r/a.mp4", uploadID: id) == .notFound)
        expectEverySignatureHolds(bucket)
    }

    /// A 404 that is not `NoSuchUpload` stays an ordinary failure.
    @Test func otherNotFoundOnAPartIsHTTPStatus() async throws {
        let xml = "<Error><Code>NoSuchBucket</Code><Message>The specified bucket does not exist</Message></Error>"
        let (session, _) = StubSession.make { _ in (404, Data(xml.utf8)) }
        await #expect(throws: UploadError.httpStatus(404, body: "NoSuchBucket: The specified bucket does not exist")) {
            try await destination(multipartConfig, session: session).uploadPart(key: "r/a.mp4", uploadID: "u", number: 1,
                                                                                data: Data("x".utf8)) { _ in }
        }
    }

    @Test func objectSizeOfAPresentAndAMissingKey() async throws {
        let bucket = makeBucket()
        bucket.state.withLock { $0.objects["r/here.mp4"] = .init(data: Data(count: 1234), headers: [:]) }
        let destination = multipartDestination(bucket)

        #expect(try await destination.objectSize(key: "r/here.mp4") == 1234)
        #expect(try await destination.objectSize(key: "r/gone.mp4") == nil)
        #expect(bucket.state.withLock { $0.received.map(\.method) } == ["HEAD", "HEAD"])
        expectEverySignatureHolds(bucket)
    }

    /// AWS answers a missing key with 403 for a key without `s3:ListBucket`.
    @Test func objectSizeTreats403AsMissing() async throws {
        let (session, _) = StubSession.make { _ in (403, Data()) }
        #expect(try await destination(multipartConfig, session: session).objectSize(key: "r/a.mp4") == nil)

        let (broken, _) = StubSession.make { _ in (500, Data()) }
        await #expect(throws: UploadError.httpStatus(500, body: "")) {
            try await destination(multipartConfig, session: broken).objectSize(key: "r/a.mp4")
        }
    }

    /// No multipart call follows a redirect: each sends one request and names where it pointed.
    @Test func multipartCallsRefuseRedirects() async throws {
        let (session, stub) = StubSession.make(headerHandler: { _ in
            (301, ["Location": "https://snap.s3.eu-west-1.amazonaws.com/r/a.mp4"], Data())
        })
        let refusing = destination(multipartConfig, session: session)
        let refused = UploadError.httpStatus(301, body: "redirected to https://snap.s3.eu-west-1.amazonaws.com/r/a.mp4; check the endpoint and region")
        let part = MultipartPart(number: 1, etag: "\"e\"", size: 1)

        await #expect(throws: refused) {
            try await refusing.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        }
        await #expect(throws: refused) {
            try await refusing.uploadPart(key: "r/a.mp4", uploadID: "u", number: 1, data: Data("x".utf8)) { _ in }
        }
        await #expect(throws: refused) {
            try await refusing.completeMultipartUpload(key: "r/a.mp4", uploadID: "u", parts: [part])
        }
        await #expect(throws: refused) { try await refusing.abortMultipartUpload(key: "r/a.mp4", uploadID: "u") }
        await #expect(throws: refused) { try await refusing.listParts(key: "r/a.mp4", uploadID: "u") }
        await #expect(throws: refused) { try await refusing.objectSize(key: "r/a.mp4") }
        #expect(stub.requests.count == 6)
    }

    /// The bucket's signature check is real: a URL whose query differs from the signed one is refused.
    @Test func bucketRefusesAQueryThatWasNotSigned() async throws {
        let bucket = makeBucket()
        let destination = multipartDestination(bucket)
        let id = try await destination.createMultipartUpload(key: "r/a.mp4", contentType: "video/mp4", cacheControl: nil)
        var request = try destination.signedRequest(method: "GET", key: "r/a.mp4", query: [(name: "uploadId", value: id)],
                                                    payloadHash: S3Signer.emptyPayloadHash, extraHeaders: [])
        var components = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        components.percentEncodedQuery = S3Signer.canonicalQuery([(name: "part-number-marker", value: "1"), (name: "uploadId", value: id)])
        request.url = components.url
        let (body, response) = try await bucket.session.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 403)
        #expect(MultipartXML.error(in: body)?.code == "SignatureDoesNotMatch")
        #expect(bucket.state.withLock { $0.received.last?.signatureMatches } == false)
    }

    /// Bytes sent reach `onBytesSent` as deltas; the fraction callback is unchanged.
    @Test func progressDelegateReportsBytesSent() {
        let sent = Mutex<[Int64]>([])
        let fractions = Mutex<[Double]>([])
        let delegate = UploadProgressDelegate(onProgress: { fraction in fractions.withLock { $0.append(fraction) } },
                                              onBytesSent: { bytes in sent.withLock { $0.append(bytes) } })
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        // Never resumed, so nothing is sent.
        let task = session.dataTask(with: URL(string: "https://example.invalid/")!)
        delegate.urlSession(session, task: task, didSendBodyData: 4, totalBytesSent: 4, totalBytesExpectedToSend: 10)
        delegate.urlSession(session, task: task, didSendBodyData: 6, totalBytesSent: 10, totalBytesExpectedToSend: 10)

        #expect(sent.withLock { $0 } == [4, 6])
        #expect(fractions.withLock { $0 } == [0.4, 1])
    }
}
