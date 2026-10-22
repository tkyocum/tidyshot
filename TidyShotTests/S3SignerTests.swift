import Foundation
import Testing
@testable import TidyShot

/// Worked examples from the AWS S3 API Reference, "Signature Calculations for the Authorization
/// Header: Transferring Payload in a Single Chunk" (sig-v4-header-based-auth). Credentials and
/// expected values are copied from that page.
struct S3SignerTests {
    let credentials = AWSCredentials(accessKeyID: "AKIAIOSFODNN7EXAMPLE",
                                     secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    /// 2013-05-24T00:00:00Z
    let date = Date(timeIntervalSince1970: 1_369_353_600)
    let host = "examplebucket.s3.amazonaws.com"

    @Test func amzDateIsUTC() {
        #expect(S3Signer.amzDateString(date) == "20130524T000000Z")
    }

    @Test func getObjectExample() {
        let request = S3Signer.Request(
            method: "GET", path: "/test.txt",
            headers: [("host", host), ("range", "bytes=0-9"), ("x-amz-content-sha256", S3Signer.emptyPayloadHash)],
            payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)

        #expect(signed.canonicalRequest == """
        GET
        /test.txt

        host:examplebucket.s3.amazonaws.com
        range:bytes=0-9
        x-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        x-amz-date:20130524T000000Z

        host;range;x-amz-content-sha256;x-amz-date
        e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        """)
        #expect(signed.stringToSign == """
        AWS4-HMAC-SHA256
        20130524T000000Z
        20130524/us-east-1/s3/aws4_request
        7344ae5b7ee6c3e7e6b0fe0640412a37625d1fbfff95c48bbb2dc43964946972
        """)
        #expect(signed.signature == "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
        #expect(signed.headers.map(\.name) == ["x-amz-date", "authorization"])
        #expect(signed.headers.last?.value == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request, SignedHeaders=host;range;x-amz-content-sha256;x-amz-date, Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    @Test func putObjectExampleEncodesDollarAndSignsBody() {
        let body = Data("Welcome to Amazon S3.".utf8)
        let bodyHash = S3Signer.sha256Hex(body)
        #expect(bodyHash == "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072")

        let request = S3Signer.Request(
            method: "PUT", path: "/test$file.text",
            headers: [("date", "Fri, 24 May 2013 00:00:00 GMT"), ("host", host),
                      ("x-amz-content-sha256", bodyHash), ("x-amz-storage-class", "REDUCED_REDUNDANCY")],
            payloadHash: bodyHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)

        #expect(signed.canonicalRequest.hasPrefix("PUT\n/test%24file.text\n\ndate:Fri, 24 May 2013 00:00:00 GMT\n"))
        #expect(signed.stringToSign.hasSuffix("9e0e90d9c76de8fa5b200d8c849cd5b8dc7a3be3951ddb7f6a76b4158342019d"))
        #expect(signed.signature == "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
    }

    @Test func getBucketLifecycleExampleHasEmptyQueryValue() {
        let request = S3Signer.Request(
            method: "GET", path: "/", query: [("lifecycle", "")],
            headers: [("host", host), ("x-amz-content-sha256", S3Signer.emptyPayloadHash)],
            payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)
        #expect(signed.canonicalRequest.contains("\nlifecycle=\n"))
        #expect(signed.signature == "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543")
    }

    @Test func listObjectsExampleSortsQuery() {
        let request = S3Signer.Request(
            method: "GET", path: "/", query: [("prefix", "J"), ("max-keys", "2")],
            headers: [("host", host), ("x-amz-content-sha256", S3Signer.emptyPayloadHash)],
            payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: credentials, region: "us-east-1", date: date)
        #expect(signed.canonicalRequest.contains("\nmax-keys=2&prefix=J\n"))
        #expect(signed.signature == "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7")
    }

    @Test func sessionTokenIsSignedAndReturned() {
        let temporary = AWSCredentials(accessKeyID: "AKID", secretAccessKey: "secret", sessionToken: "TOKEN")
        let request = S3Signer.Request(method: "GET", path: "/", headers: [("host", host)], payloadHash: S3Signer.emptyPayloadHash)
        let signed = S3Signer.sign(request, credentials: temporary, region: "us-east-1", date: date)
        #expect(signed.canonicalRequest.contains("x-amz-security-token:TOKEN\n"))
        #expect(signed.canonicalRequest.contains("host;x-amz-date;x-amz-security-token"))
        #expect(signed.headers.map(\.name) == ["x-amz-date", "x-amz-security-token", "authorization"])
    }

    @Test func uriEncodeKeepsUnreservedAndOptionallySlash() {
        #expect(S3Signer.uriEncode("a-b_c.d~e", keepSlash: false) == "a-b_c.d~e")
        #expect(S3Signer.uriEncode("x/y z", keepSlash: true) == "x/y%20z")
        #expect(S3Signer.uriEncode("x/y z", keepSlash: false) == "x%2Fy%20z")
        #expect(S3Signer.uriEncode("ሴ", keepSlash: false) == "%E1%88%B4")
        #expect(S3Signer.uriEncode("$+,:=@", keepSlash: false) == "%24%2B%2C%3A%3D%40")
    }

    @Test func removingDotSegments() {
        #expect(S3Signer.removingDotSegments("/example/..") == "/")
        #expect(S3Signer.removingDotSegments("//example//") == "/example/")
        #expect(S3Signer.removingDotSegments("/./example") == "/example")
        #expect(S3Signer.removingDotSegments("/a/b/../c/") == "/a/c/")
    }

    @Test func canonicalHeadersTrimsCollapsesAndJoinsDuplicates() {
        let result = S3Signer.canonicalHeaders([
            ("My-Header1", " value2 "), ("Host", "h"), ("my-header1", "value1"), ("X", "\"a   b   c\""),
        ])
        #expect(result.canonical == "host:h\nmy-header1:value2,value1\nx:\"a b c\"\n")
        #expect(result.signed == "host;my-header1;x")
    }

    // MARK: File hash

    /// Writes `data` to a file in a fresh folder of its own; the caller removes the folder.
    func makeFile(_ data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "S3SignerTests-\(UUID().uuidString)",
                                                                      directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "file.mp4")
        try data.write(to: url)
        return url
    }

    /// Bytes that differ along the file, so a chunk read twice, skipped or padded changes the hash.
    func patterned(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        for index in bytes.indices {
            bytes[index] = UInt8(truncatingIfNeeded: index &* 31 &+ index >> 12)
        }
        return Data(bytes)
    }

    /// Empty, one byte, exactly one 4 MiB read, and one byte into the second read.
    @Test(arguments: [0, 1, S3Signer.fileHashChunkSize, S3Signer.fileHashChunkSize + 1])
    func fileHashEqualsTheOneShotHash(byteCount: Int) async throws {
        let data = patterned(byteCount)
        let url = try makeFile(data)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(try await S3Signer.sha256Hex(fileAt: url) == S3Signer.sha256Hex(data))
    }

    @Test func fileHashChunkIsFourMebibytes() {
        #expect(S3Signer.fileHashChunkSize == 4_194_304)
    }

    /// The hash checks for cancellation before every read, so a Delete during the hash stops it
    /// instead of reading the rest of the file.
    @Test func cancelledFileHashStopsBeforeReading() async throws {
        let url = try makeFile(patterned(S3Signer.fileHashChunkSize * 2 + 1))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await S3Signer.sha256Hex(fileAt: url)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func missingFileHashThrows() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "S3SignerTests-\(UUID().uuidString).mp4")
        await #expect(throws: (any Error).self) { try await S3Signer.sha256Hex(fileAt: missing) }
    }

    /// A file's PUT is signed with the file's hash, just as the same bytes in memory are, and
    /// `Content-Length` is neither set nor signed: URLSession sets it for a file body.
    @Test func fileRequestCarriesTheFileHash() async throws {
        let data = Data("hello".utf8)
        let url = try makeFile(data)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1",
                                         bucket: "snap", publicURLTemplate: "https://snap.tky.io/{key}")
        let destination = S3Destination(config: config, credentials: credentials, now: { date })
        let headers = [(name: "content-type", value: "video/mp4")]

        let hash = try await S3Signer.sha256Hex(fileAt: url)
        let fromFile = try destination.signedRequest(method: "PUT", key: "a.mp4", payloadHash: hash, extraHeaders: headers)
        let fromData = try destination.signedRequest(method: "PUT", key: "a.mp4", body: data, extraHeaders: headers)

        #expect(fromFile.value(forHTTPHeaderField: "x-amz-content-sha256") == hash)
        #expect(hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        #expect(fromFile.value(forHTTPHeaderField: "authorization") == fromData.value(forHTTPHeaderField: "authorization"))
        #expect(fromFile.value(forHTTPHeaderField: "content-length") == nil)
        #expect(fromFile.value(forHTTPHeaderField: "authorization")?.contains("content-length") == false)
    }
}
