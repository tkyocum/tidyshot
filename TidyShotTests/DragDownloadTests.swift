import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// The drag-out download (`S3Destination.download(key:to:expectedBytes:resumeData:progress:)`)
/// against `StubURLProtocol`, landing in a temporary `Drag/.downloads`.
struct DragDownloadTests {
    let credentials = AWSCredentials(accessKeyID: "AKIAIOSFODNN7EXAMPLE",
                                     secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    /// 2026-10-19T12:00:00Z
    let date = Date(timeIntervalSince1970: 1_792_411_200)
    let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                     publicURLTemplate: "https://snap.tky.io/{key}")
    let root: URL
    let store: DragFileStore

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "DragDownloadTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = DragFileStore(temporaryDirectory: root)
    }

    func destination(session: URLSession) -> S3Destination {
        S3Destination(config: config, credentials: credentials, session: session, now: { date })
    }

    /// Bytes no other test sends, so a leftover temporary file can be told apart by its contents.
    static func uniqueBody(_ count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: 0...255) })
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// What is in `Drag/.downloads`.
    func landed() -> [String] {
        let downloads = store.directory.appending(path: ".downloads", directoryHint: .isDirectory)
        return (try? FileManager.default.contentsOfDirectory(atPath: downloads.path(percentEncoded: false))) ?? []
    }

    /// URLSession's own download files in the temporary directory that hold `body`.
    static func sessionFiles(holding body: Data) -> [URL] {
        let temporary = FileManager.default.temporaryDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("CFNetworkDownload_") && (try? Data(contentsOf: $0)) == body }
    }

    /// The fractions a download reported, in order.
    nonisolated final class Fractions: Sendable {
        private let values = Mutex<[Double]>([])
        func append(_ value: Double) { values.withLock { $0.append(value) } }
        var all: [Double] { values.withLock { $0 } }
    }

    static func isRising(_ values: [Double]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 < $1 }
    }

    /// Eight paced chunks with `Content-Length`: the fractions rise and end at 1, and the file at
    /// `landing` is the body. `Content-Length` wins over `expectedBytes`. The GET is signed as
    /// `download(key:to:)` signs it.
    @Test func aChunkedBodyReportsRisingFractionsAndLands() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let body = Self.uniqueBody(80_000)
        let (session, stub) = StubSession.make(headerHandler: { _ in
            (200, ["Content-Length": String(body.count)], body)
        }, chunkSize: 10_000, chunkDelay: 0.12)
        let landing = try store.landingURL()
        let fractions = Fractions()
        try await destination(session: session).download(key: "aSIS7.png", to: landing, expectedBytes: 4 * Int64(body.count)) {
            fractions.append($0)
        }

        #expect(try Data(contentsOf: landing) == body)
        let reported = fractions.all
        #expect(reported.count >= 2)
        #expect(Self.isRising(reported))
        #expect(reported.last == 1)
        #expect(reported.allSatisfy { $0 > 0 && $0 <= 1 })
        let request = try #require(stub.requests.first)
        #expect(stub.requests.count == 1)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://snap.s3.us-east-1.amazonaws.com/aSIS7.png")
        #expect(request.value(forHTTPHeaderField: "Range") == nil)
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=2b2032e36f0ecee5dda47c71b2b5cb033deed81114e1626e47639929cb0f7162")
    }

    /// The delegate moves the file out of URLSession's temporary location inside its callback, so
    /// the file is at `landing` as soon as the call returns, and URLSession's temporary folder keeps
    /// no copy of it.
    @Test func theFileIsAtTheLandingPathWhenTheCallReturns() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let body = Self.uniqueBody(40_000)
        let (session, _) = StubSession.make(headerHandler: { _ in
            (200, ["Content-Length": String(body.count)], body)
        })
        let landing = try store.landingURL()
        try await destination(session: session).download(key: "a.mp4", to: landing, expectedBytes: nil) { _ in }

        #expect(exists(landing))
        #expect(try Data(contentsOf: landing) == body)
        #expect(Self.sessionFiles(holding: body).isEmpty)
    }

    /// A transport failure part way through leaves no file and throws the `URLError`.
    @Test func aTransportFailureMidBodyLeavesNoFile() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let body = Self.uniqueBody(80_000)
        let (session, _) = StubSession.make(headerHandler: { _ in
            (200, ["Content-Length": String(body.count)], body)
        }, chunkSize: 10_000, chunkDelay: 0.02, failAfterBytes: 30_000)
        let landing = try store.landingURL()
        let error = await #expect(throws: URLError.self) {
            try await destination(session: session).download(key: "a.mp4", to: landing, expectedBytes: nil) { _ in }
        }
        #expect(error?.code == .networkConnectionLost)
        #expect(!exists(landing))
        #expect(landed().isEmpty)
    }

    /// A 403 throws its excerpt and leaves no file.
    @Test func aForbiddenResponseThrowsItsExcerptAndLeavesNoFile() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let xml = "<Error><Code>AccessDenied</Code><Message>Access Denied</Message><RequestId>X</RequestId></Error>"
        let (session, _) = StubSession.make { _ in (403, Data(xml.utf8)) }
        let landing = try store.landingURL()
        await #expect(throws: UploadError.httpStatus(403, body: "AccessDenied: Access Denied")) {
            try await destination(session: session).download(key: "a.mp4", to: landing, expectedBytes: nil) { _ in }
        }
        #expect(!exists(landing))
        #expect(landed().isEmpty)
    }

    /// A redirect is refused: one request, the usual redirect error, no file.
    @Test func aRedirectIsRefused() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (session, stub) = StubSession.make(headerHandler: { _ in
            (307, ["Location": "https://snap.s3.eu-west-1.amazonaws.com/a.mp4"], Data())
        })
        let landing = try store.landingURL()
        await #expect(throws: UploadError.httpStatus(307, body: "redirected to https://snap.s3.eu-west-1.amazonaws.com/a.mp4; check the endpoint and region")) {
            try await destination(session: session).download(key: "a.mp4", to: landing, expectedBytes: nil) { _ in }
        }
        #expect(stub.requests.count == 1)
        #expect(!exists(landing))
    }

    /// Cancelling the calling task cancels the URLSession task: it throws a cancellation and
    /// leaves no file.
    @Test func cancellingTheCallerLeavesNoFile() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let body = Self.uniqueBody(80_000)
        let (session, _) = StubSession.make(headerHandler: { _ in
            (200, ["Content-Length": String(body.count)], body)
        }, chunkSize: 10_000, chunkDelay: 0.2)
        let landing = try store.landingURL()
        let fractions = Fractions()
        let destination = destination(session: session)
        let download = Task {
            try await destination.download(key: "a.mp4", to: landing, expectedBytes: nil) { fractions.append($0) }
        }
        for _ in 0..<500 where fractions.all.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!fractions.all.isEmpty)
        download.cancel()
        let result = await download.result

        #expect(throws: (any Error).self) { try result.get() }
        if case .failure(let error) = result {
            #expect(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
        #expect(!exists(landing))
        #expect(landed().isEmpty)
        #expect(fractions.all.allSatisfy { $0 < 1 })
    }

    /// With no `Content-Length`, the fractions are over `expectedBytes`.
    @Test func withNoContentLengthTheFractionsUseExpectedBytes() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let body = Self.uniqueBody(40_000)
        let (session, _) = StubSession.make(headerHandler: { _ in (200, [:], body) },
                                            chunkSize: 10_000, chunkDelay: 0.12)
        let destination = destination(session: session)

        let quarter = Fractions()
        let first = try store.landingURL()
        try await destination.download(key: "a.mp4", to: first, expectedBytes: 4 * Int64(body.count)) { quarter.append($0) }
        #expect(!quarter.all.isEmpty)
        #expect(Self.isRising(quarter.all))
        #expect(quarter.all.allSatisfy { $0 > 0 && $0 <= 0.25 })
        #expect(try Data(contentsOf: first) == body)

        let whole = Fractions()
        let second = try store.landingURL()
        try await destination.download(key: "a.mp4", to: second, expectedBytes: Int64(body.count)) { whole.append($0) }
        #expect(whole.all.last == 1)
        #expect(Self.isRising(whole.all))
    }

    /// A failure half way gives resume data; a download with it asks for the rest with
    /// `Range: bytes=500000-`, gets a 206 and lands the whole body. The chunks are paced: a body
    /// handed over in one call before the failure gives resume data that starts again at 0.
    @Test func resumeDataContinuesWithARangeRequest() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let body = Self.uniqueBody(1_000_000)
        let headers = ["Content-Length": String(body.count), "ETag": "\"5d41402abc4b2a76b9719d911017c592\"",
                       "Last-Modified": "Mon, 19 Oct 2026 12:00:00 GMT", "Accept-Ranges": "bytes"]
        let (session, stub) = StubSession.make(headerHandler: { _ in (200, headers, body) },
                                               chunkSize: 100_000, chunkDelay: 0.1, failAfterBytes: 500_000,
                                               servesRanges: true)
        let destination = destination(session: session)

        let first = try store.landingURL()
        let error = await #expect(throws: URLError.self) {
            try await destination.download(key: "a.mp4", to: first, expectedBytes: nil) { _ in }
        }
        let resumeData = try #require(error?.downloadTaskResumeData)
        #expect(!exists(first))

        let landing = try store.landingURL()
        let fractions = Fractions()
        try await destination.download(key: "a.mp4", to: landing, expectedBytes: nil, resumeData: resumeData) {
            fractions.append($0)
        }
        #expect(stub.requests.count == 2)
        #expect(stub.requests.last?.value(forHTTPHeaderField: "Range") == "bytes=500000-")
        #expect(try Data(contentsOf: landing) == body)
        #expect(fractions.all.last == 1)
        #expect(fractions.all.allSatisfy { $0 >= 0.5 })
    }

    /// A cancel that lands before the continuation is handed over (during `signedRequest`, say)
    /// cancels the URLSession task first, and URLSession completes it with no `resume()`. `start`
    /// then resumes at once with that result instead of waiting for a completion that has passed.
    @Test func aTaskCancelledBeforeStartStillResumes() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let (session, stub) = StubSession.make(headerHandler: { _ in (200, [:], Data("x".utf8)) })
        let landing = try store.landingURL()
        let delegate = DragDownloadDelegate(landing: landing, expectedBytes: nil, onProgress: { _ in })
        let task = session.downloadTask(with: URL(string: "https://snap.s3.us-east-1.amazonaws.com/a.mp4")!)
        task.delegate = delegate
        task.cancel()
        // URLSession completes a task cancelled before it was resumed a few ms later.
        try await Task.sleep(for: .milliseconds(300))
        let error = await #expect(throws: URLError.self) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                delegate.start(continuation)
                task.resume()
            }
        }
        #expect(error?.code == .cancelled)
        #expect(stub.requests.isEmpty)
        #expect(!exists(landing))
    }

    /// Whichever order `start` and the completion come in, the continuation is resumed once with
    /// the task's result.
    @Test func aCompletionBeforeStartIsKeptForStart() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: URL(string: "https://snap.s3.us-east-1.amazonaws.com/a.mp4")!)
        let landing = root.appending(path: "landing")

        let succeeded = DragDownloadDelegate(landing: landing, expectedBytes: nil, onProgress: { _ in })
        succeeded.urlSession(session, task: task, didCompleteWithError: nil)
        try await withCheckedThrowingContinuation { succeeded.start($0) }

        let failed = DragDownloadDelegate(landing: landing, expectedBytes: nil, onProgress: { _ in })
        failed.urlSession(session, task: task, didCompleteWithError: URLError(.networkConnectionLost))
        await #expect(throws: URLError(.networkConnectionLost)) {
            try await withCheckedThrowingContinuation { failed.start($0) }
        }

        let afterStart = DragDownloadDelegate(landing: landing, expectedBytes: nil, onProgress: { _ in })
        await #expect(throws: URLError(.timedOut)) {
            try await withCheckedThrowingContinuation { continuation in
                afterStart.start(continuation)
                afterStart.urlSession(session, task: task, didCompleteWithError: URLError(.timedOut))
                // A second completion does nothing.
                afterStart.urlSession(session, task: task, didCompleteWithError: nil)
            }
        }
    }
}
