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
        /// The body is delivered in chunks of this size. Nil: in one piece.
        var chunkSize: Int? = nil
        /// A pause after each chunk, so URLSession writes it before the next arrives.
        var chunkDelay: TimeInterval? = nil
        /// After this many bytes of a longer body the load fails with
        /// `URLError(.networkConnectionLost)`.
        var failAfterBytes: Int? = nil
        /// A `Range: bytes=<n>-` request is answered 206 with `Content-Range` and the body from `n`.
        var servesRanges = false
    }

    /// Set by `stopLoading`, so a paced delivery stops calling the client once the task is cancelled.
    private let stopped = Mutex(false)

    static let entries = Mutex<[String: Entry]>([:])

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let id = request.value(forHTTPHeaderField: Self.sessionHeader) ?? ""
        let entry = Self.entries.withLock { entries -> Entry? in
            entries[id]?.requests.append(request)
            return entries[id]
        }
        guard let entry else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        var (status, headers, body) = entry.handler(request)
        if status == Self.transportFailureStatus {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if entry.servesRanges, status == 200, let start = Self.rangeStart(of: request), start < body.count {
            headers["Content-Range"] = "bytes \(start)-\(body.count - 1)/\(body.count)"
            if headers["Content-Length"] != nil {
                headers["Content-Length"] = String(body.count - start)
            }
            status = 206
            body = body.subdata(in: start..<body.count)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        if (300..<400).contains(status), let location = headers["Location"], let target = URL(string: location) {
            var redirect = request
            redirect.url = target
            client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard entry.chunkSize != nil || entry.chunkDelay != nil || entry.failAfterBytes != nil else {
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let limit = entry.failAfterBytes.flatMap { $0 < body.count ? $0 : nil }
        let delivered = limit.map { body.prefix($0) } ?? body
        let chunkSize = max(1, entry.chunkSize ?? delivered.count)
        let chunks = stride(from: 0, to: delivered.count, by: chunkSize).map {
            delivered.subdata(in: $0..<min($0 + chunkSize, delivered.count))
        }
        deliver(chunks[...], delay: entry.chunkDelay ?? 0, thenFail: limit != nil, on: ClientRunLoop())
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }

    /// Hands `chunks` to the client one at a time, pausing `delay` after each, then fails or finishes.
    /// Each call runs on the run loop `startLoading` ran on, as URLProtocol's client expects.
    private func deliver(_ chunks: ArraySlice<Data>, delay: TimeInterval, thenFail: Bool, on runLoop: ClientRunLoop) {
        guard !stopped.withLock({ $0 }) else { return }
        guard let chunk = chunks.first else {
            if thenFail {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
            } else {
                client?.urlProtocolDidFinishLoading(self)
            }
            return
        }
        client?.urlProtocol(self, didLoad: chunk)
        let rest = chunks.dropFirst()
        nonisolated(unsafe) let unsafeSelf = self
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            runLoop.perform { unsafeSelf.deliver(rest, delay: delay, thenFail: thenFail, on: runLoop) }
        }
    }

    /// `n` from a `Range: bytes=<n>-` header.
    private static func rangeStart(of request: URLRequest) -> Int? {
        guard let range = request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="), range.hasSuffix("-") else {
            return nil
        }
        return Int(range.dropFirst("bytes=".count).dropLast())
    }

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

    /// Like `make(handler:)`, for stubs that need response headers, and optionally a body delivered
    /// in paced chunks, a failure part way through it, or a 206 for a `Range` request (`Entry`).
    static func make(headerHandler handler: @escaping StubURLProtocol.HeaderHandler, chunkSize: Int? = nil,
                     chunkDelay: TimeInterval? = nil, failAfterBytes: Int? = nil,
                     servesRanges: Bool = false) -> (URLSession, StubSession) {
        let stub = StubSession(id: UUID().uuidString)
        let entry = StubURLProtocol.Entry(handler: handler, chunkSize: chunkSize, chunkDelay: chunkDelay,
                                          failAfterBytes: failAfterBytes, servesRanges: servesRanges)
        StubURLProtocol.entries.withLock { $0[stub.id] = entry }
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

/// The run loop and mode `startLoading` ran in, so a paced delivery calls the client there.
nonisolated private struct ClientRunLoop: @unchecked Sendable {
    let runLoop: CFRunLoop
    let mode: CFRunLoopMode

    init() {
        runLoop = CFRunLoopGetCurrent()
        mode = CFRunLoopCopyCurrentMode(runLoop) ?? .defaultMode
    }

    func perform(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, mode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }
}
