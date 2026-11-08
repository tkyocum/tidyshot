import Foundation
import Synchronization
@testable import TidyShot

/// An in-memory multipart S3 for one test, behind `StubSession.make(headerHandler:)`. It reads the
/// method, the path-style key and the decoded query, and answers Create, UploadPart, Complete,
/// Abort, ListParts and HEAD as AWS documents them. Like S3 it checks each request's
/// `x-amz-content-sha256` against its body and its signature against what it received, so a URL
/// query that differs from the signed one is refused.
nonisolated final class StubMultipartBucket: Sendable {
    struct Part: Equatable, Sendable {
        var etag: String
        var data: Data
    }

    struct Upload: Sendable {
        var key: String
        /// The object headers Create carried: `content-type`, `cache-control`, `x-amz-acl`.
        var headers: [String: String]
        var parts: [Int: Part] = [:]
    }

    struct Object: Sendable {
        var data: Data
        var headers: [String: String]
    }

    /// One request as the bucket received it.
    struct Received: Sendable {
        var method: String
        var query: [String: String]
        var body: Data
        var contentType: String?
        var contentSHA256: String?
        var signedHeaders: String?
        var signatureMatches: Bool
    }

    struct State: Sendable {
        /// Every part but the last must be at least this large at Complete. S3's is 5 MiB.
        var minimumPartSize = 0
        var listPageSize = 1000
        /// When set, every Complete that reaches the part checks answers this instead.
        var completeAnswer: (status: Int, body: Data)?
        /// Upload ids that answer `NoSuchUpload`, as an id the lifecycle rule aborted would.
        var missingUploads: Set<String> = []
        var uploads: [String: Upload] = [:]
        var objects: [String: Object] = [:]
        var received: [Received] = []
        var lastUpload = 0
        var lastETag = 0
    }

    let state: Mutex<State>
    let bucket: String
    let credentials: AWSCredentials
    let region: String
    let date: Date
    /// The session routed to this bucket. Set once in `init`, after the handler can hold the bucket.
    nonisolated(unsafe) private(set) var session: URLSession!

    init(bucket: String, credentials: AWSCredentials, region: String, date: Date, state: State = State()) {
        self.state = Mutex(state)
        self.bucket = bucket
        self.credentials = credentials
        self.region = region
        self.date = date
        session = StubSession.make(headerHandler: { request in self.answer(request) }).0
    }

    private func answer(_ request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return error(400, "InvalidURI")
        }
        let method = request.httpMethod ?? "GET"
        let body = StubURLProtocol.bodyBytes(of: request)
        let pairs = (components.queryItems ?? []).map { (name: $0.name, value: $0.value ?? "") }
        let query = Dictionary(pairs.map { ($0.name, $0.value) }, uniquingKeysWith: { first, _ in first })
        let contentSHA256 = request.value(forHTTPHeaderField: "x-amz-content-sha256")
        let authorization = request.value(forHTTPHeaderField: "authorization")
        let signedHeaders = authorization.flatMap(Self.signedHeaders(in:))
        let signatureMatches = authorization != nil && authorization == expectedAuthorization(
            request, method: method, path: url.path(percentEncoded: false), query: pairs,
            signedHeaders: signedHeaders ?? "", payloadHash: contentSHA256 ?? "")
        state.withLock {
            $0.received.append(Received(method: method, query: query, body: body,
                                        contentType: request.value(forHTTPHeaderField: "content-type"),
                                        contentSHA256: contentSHA256, signedHeaders: signedHeaders,
                                        signatureMatches: signatureMatches))
        }
        guard contentSHA256 == S3Signer.sha256Hex(body) else { return error(400, "XAmzContentSHA256Mismatch") }
        guard signatureMatches else { return error(403, "SignatureDoesNotMatch") }
        let prefix = "/\(bucket)/"
        let path = url.path(percentEncoded: false)
        guard path.hasPrefix(prefix) else { return error(404, "NoSuchBucket") }
        let key = String(path.dropFirst(prefix.count))

        switch (method, query["uploads"], query["uploadId"], query["partNumber"]) {
        case ("POST", _?, nil, nil): return create(key: key, request: request)
        case ("PUT", nil, let id?, let number?): return uploadPart(id: id, number: number, body: body)
        case ("POST", nil, let id?, nil): return complete(id: id, key: key, request: request, body: body)
        case ("DELETE", nil, let id?, nil): return abort(id: id)
        case ("GET", nil, let id?, nil): return listParts(id: id, key: key, marker: query["part-number-marker"])
        case ("HEAD", nil, nil, nil):
            guard let object = state.withLock({ $0.objects[key] }) else { return (404, [:], Data()) }
            return (200, ["Content-Length": String(object.data.count)], Data())
        default: return error(400, "InvalidRequest")
        }
    }

    private func create(key: String, request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        var headers: [String: String] = [:]
        for name in ["content-type", "cache-control", "x-amz-acl"] {
            headers[name] = request.value(forHTTPHeaderField: name)
        }
        let id = state.withLock { state in
            state.lastUpload += 1
            // Characters that need encoding in a query, as real ids can carry.
            let id = "VXBs/\(state.lastUpload)+x="
            state.uploads[id] = Upload(key: key, headers: headers)
            return id
        }
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<InitiateMultipartUploadResult><Bucket>\(bucket)</Bucket><Key>\(key)</Key><UploadId>\(id)</UploadId></InitiateMultipartUploadResult>"
        return (200, [:], Data(xml.utf8))
    }

    private func uploadPart(id: String, number: String, body: Data) -> (status: Int, headers: [String: String], body: Data) {
        guard let number = Int(number), (1...10_000).contains(number) else { return error(400, "InvalidArgument") }
        let etag: String? = state.withLock { state in
            guard !state.missingUploads.contains(id), state.uploads[id] != nil else { return nil }
            state.lastETag += 1
            let etag = "\"etag-\(state.lastETag)\""
            state.uploads[id]?.parts[number] = Part(etag: etag, data: body)
            return etag
        }
        guard let etag else { return error(404, "NoSuchUpload") }
        return (200, ["ETag": etag], Data())
    }

    private func complete(id: String, key: String, request: URLRequest,
                          body: Data) -> (status: Int, headers: [String: String], body: Data) {
        guard let upload = state.withLock({ $0.missingUploads.contains(id) ? nil : $0.uploads[id] }) else {
            return error(404, "NoSuchUpload")
        }
        // AWS refuses Complete with no type and with the type URLSession adds to a bare POST.
        let type = request.value(forHTTPHeaderField: "content-type")
        guard let type, type != "application/x-www-form-urlencoded" else { return error(400, "MalformedXML") }
        if let scripted = state.withLock({ $0.completeAnswer }) { return (scripted.status, [:], scripted.body) }
        let listed = Self.completeParts(in: body)
        guard !listed.isEmpty else { return error(400, "MalformedXML") }
        guard zip(listed, listed.dropFirst()).allSatisfy({ $0.number < $1.number }) else {
            return error(400, "InvalidPartOrder")
        }
        var data = Data()
        for (index, part) in listed.enumerated() {
            guard let stored = upload.parts[part.number], stored.etag == part.etag else { return error(400, "InvalidPart") }
            if index < listed.count - 1, stored.data.count < state.withLock({ $0.minimumPartSize }) {
                return error(400, "EntityTooSmall")
            }
            data.append(stored.data)
        }
        state.withLock {
            $0.uploads[id] = nil
            $0.objects[key] = Object(data: data, headers: upload.headers)
        }
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<CompleteMultipartUploadResult><Bucket>\(bucket)</Bucket><Key>\(key)</Key><ETag>&quot;done-\(listed.count)&quot;</ETag></CompleteMultipartUploadResult>"
        return (200, [:], Data(xml.utf8))
    }

    private func abort(id: String) -> (status: Int, headers: [String: String], body: Data) {
        let found = state.withLock { state in
            guard !state.missingUploads.contains(id) else { return false }
            return state.uploads.removeValue(forKey: id) != nil
        }
        return found ? (204, [:], Data()) : error(404, "NoSuchUpload")
    }

    private func listParts(id: String, key: String, marker: String?) -> (status: Int, headers: [String: String], body: Data) {
        guard let upload = state.withLock({ $0.missingUploads.contains(id) ? nil : $0.uploads[id] }) else {
            return error(404, "NoSuchUpload")
        }
        let after = marker.flatMap { Int($0) } ?? 0
        let remaining = upload.parts.keys.sorted().filter { $0 > after }
        let page = remaining.prefix(state.withLock { $0.listPageSize })
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<ListPartsResult><Bucket>\(bucket)</Bucket><Key>\(key)</Key><UploadId>\(id)</UploadId><PartNumberMarker>\(after)</PartNumberMarker>"
        // AWS sends the marker on a last page too.
        if let last = page.last { xml += "<NextPartNumberMarker>\(last)</NextPartNumberMarker>" }
        xml += "<IsTruncated>\(page.count < remaining.count)</IsTruncated>"
        for number in page {
            let part = upload.parts[number]!
            let etag = part.etag.replacingOccurrences(of: "\"", with: "&quot;")
            xml += "<Part><PartNumber>\(number)</PartNumber><ETag>\(etag)</ETag><Size>\(part.data.count)</Size></Part>"
        }
        xml += "</ListPartsResult>"
        return (200, [:], Data(xml.utf8))
    }

    private func error(_ status: Int, _ code: String) -> (status: Int, headers: [String: String], body: Data) {
        (status, [:], Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<Error><Code>\(code)</Code><Message>The stub bucket refused it.</Message></Error>".utf8))
    }

    /// The parts of a Complete body, in the order written.
    private static func completeParts(in body: Data) -> [(number: Int, etag: String)] {
        String(decoding: body, as: UTF8.self).components(separatedBy: "<Part>").dropFirst().compactMap { block in
            guard let number = block.between("<PartNumber>", "</PartNumber>").flatMap({ Int($0) }),
                  let etag = block.between("<ETag>", "</ETag>") else { return nil }
            return (number, etag)
        }
    }

    private static func signedHeaders(in authorization: String) -> String? {
        authorization.between("SignedHeaders=", ",")
    }

    /// The authorization S3 would compute for what it received: the decoded path and query from
    /// the URL, and each signed header's received value (`host` from the URL).
    private func expectedAuthorization(_ request: URLRequest, method: String, path: String,
                                       query: [(name: String, value: String)], signedHeaders: String,
                                       payloadHash: String) -> String? {
        var headers: [(name: String, value: String)] = []
        for name in signedHeaders.split(separator: ";").map(String.init) where name != "x-amz-date" && name != "x-amz-security-token" {
            if name == "host" {
                headers.append((name: name, value: request.url?.host() ?? ""))
            } else {
                headers.append((name: name, value: request.value(forHTTPHeaderField: name) ?? ""))
            }
        }
        let signed = S3Signer.sign(S3Signer.Request(method: method, path: path, query: query, headers: headers,
                                                    payloadHash: payloadHash),
                                   credentials: credentials, region: region, date: date)
        return signed.headers.last?.value
    }
}

nonisolated private extension String {
    /// The text between the first `open` and the next `close`.
    func between(_ open: String, _ close: String) -> String? {
        guard let start = range(of: open), let end = self[start.upperBound...].range(of: close) else { return nil }
        return String(self[start.upperBound..<end.lowerBound])
    }
}
