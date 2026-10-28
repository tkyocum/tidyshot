import Foundation
import Synchronization

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

    /// The body a request carried: URLSession hands a URLProtocol a file or data body as a stream.
    nonisolated static func bodyBytes(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
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
