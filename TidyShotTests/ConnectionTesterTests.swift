import Foundation
import Testing
@testable import TidyShot

struct ConnectionTesterTests {
    let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                     publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "p/{random:6}")

    func destination(_ session: URLSession) -> S3Destination {
        S3Destination(config: config,
                      credentials: AWSCredentials(accessKeyID: "AKID", secretAccessKey: "secret"),
                      session: session)
    }

    @Test func readableWhenPutSucceedsAndPublicGetReturnsBody() async {
        let (session, stub) = StubSession.make { request in
            switch request.httpMethod {
            case "PUT": (200, Data())
            case "GET": (200, ConnectionTester.probeBody)
            default: (204, Data())
            }
        }
        let result = await ConnectionTester.run(destination: destination(session), session: session,
                                                randomString: { String(repeating: "Z", count: $0) })

        #expect(result.probeKey == "p/tidyshot-probe-ZZZZZZZZ.txt")
        #expect(result.publicURL?.absoluteString == "https://snap.tky.io/p/tidyshot-probe-ZZZZZZZZ.txt")
        #expect(result.outcome == .readable)
        #expect(result.warning == nil)
        let requests = stub.requests
        let sent = requests.map { "\($0.httpMethod!) \($0.url!.absoluteString)" }
        #expect(sent == ["PUT https://snap.s3.us-east-1.amazonaws.com/p/tidyshot-probe-ZZZZZZZZ.txt",
                         "GET https://snap.tky.io/p/tidyshot-probe-ZZZZZZZZ.txt",
                         "DELETE https://snap.s3.us-east-1.amazonaws.com/p/tidyshot-probe-ZZZZZZZZ.txt"])
        #expect(requests[1].value(forHTTPHeaderField: "authorization") == nil)
    }

    /// The probe is deleted by the time the result shows, so its URL is not echoed.
    @Test func readableSummaryDoesNotEchoTheProbeURL() {
        let result = ConnectionTestResult(probeKey: "p/tidyshot-probe-ZZZZZZZZ.txt",
                                          publicURL: URL(string: "https://snap.tky.io/p/tidyshot-probe-ZZZZZZZZ.txt"),
                                          outcome: .readable)
        #expect(result.summary == "Upload and public read both work.")
    }

    @Test func notPublicWhenGetIsForbidden() async {
        let (session, stub) = StubSession.make { request in request.httpMethod == "GET" ? (403, Data()) : (200, Data()) }
        let result = await ConnectionTester.run(destination: destination(session), session: session)
        #expect(result.outcome == .notPublic(status: 403))
        #expect(result.summary.contains("HTTP 403"))
        #expect(stub.requests.map(\.httpMethod) == ["PUT", "GET", "DELETE"])
    }

    @Test func transportErrorOnPublicGetIsReportedDistinctly() async {
        let (session, stub) = StubSession.make { request in
            request.httpMethod == "GET" ? (StubURLProtocol.transportFailureStatus, Data()) : (200, Data())
        }
        let result = await ConnectionTester.run(destination: destination(session), session: session)
        let message = URLError(.cannotFindHost).localizedDescription
        guard case .publicCheckFailed(let reported) = result.outcome else {
            Issue.record("Expected publicCheckFailed, got \(result.outcome)")
            return
        }
        #expect(reported.contains(message))
        #expect(stub.requests.map(\.httpMethod) == ["PUT", "GET", "DELETE"])
    }

    @Test func unexpectedStatusOnPublicGetIsReportedDistinctly() async {
        let (session, _) = StubSession.make { request in request.httpMethod == "GET" ? (503, Data()) : (200, Data()) }
        let result = await ConnectionTester.run(destination: destination(session), session: session)
        #expect(result.outcome == .publicCheckFailed("HTTP 503"))
    }

    @Test func wrongBodyOn200IsNotReadable() async {
        let (session, _) = StubSession.make { request in
            request.httpMethod == "GET" ? (200, Data("<html>parked domain</html>".utf8)) : (200, Data())
        }
        let result = await ConnectionTester.run(destination: destination(session), session: session)
        guard case .publicCheckFailed = result.outcome else {
            Issue.record("Expected publicCheckFailed, got \(result.outcome)")
            return
        }
        #expect(result.outcome != .readable)
    }

    @Test func uploadFailedWhenPutIsRejected() async {
        let (session, stub) = StubSession.make { _ in (403, Data("AccessDenied".utf8)) }
        let result = await ConnectionTester.run(destination: destination(session), session: session)
        #expect(result.outcome == .uploadFailed("Server returned HTTP 403: AccessDenied"))
        #expect(stub.requests.count == 1)
    }

    @Test func warnsWhenProbeCannotBeDeleted() async {
        let (session, _) = StubSession.make { request in
            switch request.httpMethod {
            case "PUT": (200, Data())
            case "GET": (200, ConnectionTester.probeBody)
            default: (403, Data("AccessDenied".utf8))
            }
        }
        let result = await ConnectionTester.run(destination: destination(session), session: session,
                                                randomString: { String(repeating: "Z", count: $0) })
        #expect(result.outcome == .readable)
        #expect(result.warning == "Probe object p/tidyshot-probe-ZZZZZZZZ.txt could not be deleted; remove it by hand.")
    }
}
