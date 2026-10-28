// R4 probe M1: multipart upload against a real bucket, with the app's own requests
// (MultipartRequests, MultipartXML, S3Signer). Tim's to run; it uploads under
// <prefix>/r4-probe-<random> and deletes what it made.
//
// Build from the repository root (a build of more than one file, so this is an @main type with no
// top-level code):
//   xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/r4-multipart \
//     docs/superpowers/research/recording-probes/r4-multipart.swift TidyShot/Upload/S3Signer.swift \
//     TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/MultipartRequests.swift TidyShot/Upload/MultipartXML.swift
// Run:
//   AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… [AWS_SESSION_TOKEN=…] \
//     /tmp/r4-multipart <bucket> <region> <endpoint> <prefix> [acl]

import Foundation

@main
enum R4Multipart {
    static let mib = 1024 * 1024

    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 5 || (args.count == 6 && args[5] == "acl") else {
            print("usage: r4-multipart <bucket> <region> <endpoint> <prefix> [acl]")
            exit(2)
        }
        let env = ProcessInfo.processInfo.environment
        guard let accessKey = env["AWS_ACCESS_KEY_ID"], !accessKey.isEmpty,
              let secret = env["AWS_SECRET_ACCESS_KEY"], !secret.isEmpty else {
            print("AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set")
            exit(2)
        }
        let credentials = AWSCredentials(accessKeyID: accessKey, secretAccessKey: secret,
                                         sessionToken: env["AWS_SESSION_TOKEN"].flatMap { $0.isEmpty ? nil : $0 })
        guard let endpoint = URLComponents(string: args[3]), let host = endpoint.host, !host.isEmpty else {
            print("bad endpoint: \(args[3])")
            exit(2)
        }
        let prefix = args[4].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let name = "r4-probe-\(randomSuffix())"
        let key = prefix.isEmpty ? name : "\(prefix)/\(name)"
        let client = Client(bucket: args[1], region: args[2], endpoint: endpoint, key: key, credentials: credentials)
        let publicRead = args.count == 6

        TemporaryFile.watchSignals()
        defer { TemporaryFile.remove() }
        print("key \(key), acl \(publicRead ? "public-read" : "none")")
        do {
            try await smallUpload(client, publicRead: publicRead)
            try await abortedUpload(client, publicRead: publicRead)
            try await largeUpload(client, partSize: 16 * mib, publicRead: publicRead)
            try await largeUpload(client, partSize: 64 * mib, publicRead: publicRead)
            print("done")
        } catch {
            print("stopped: \(error)")
            TemporaryFile.remove()
            exit(1)
        }
    }

    // MARK: Steps 1 to 6

    static func smallUpload(_ client: Client, publicRead: Bool) async throws {
        print("\n1. Create")
        let uploadID = try await client.create(publicRead: publicRead)

        print("\n2. Parts 1 and 2 of 5 MiB, part 3 of 1 MiB, three at a time")
        let sizes = [1: 5 * mib, 2: 5 * mib, 3: 1 * mib]
        var parts: [MultipartPart] = []
        do {
            parts = try await withThrowingTaskGroup(of: MultipartPart.self) { group in
                for (number, size) in sizes.sorted(by: { $0.key < $1.key }) {
                    group.addTask { try await client.uploadPart(uploadID: uploadID, number: number, data: randomData(size)) }
                }
                var parts: [MultipartPart] = []
                for try await part in group {
                    print("   part \(part.number) ETag \(part.etag)")
                    parts.append(part)
                }
                return parts
            }
        } catch {
            await client.abortQuietly(uploadID)
            throw error
        }

        print("\n3. ListParts")
        if let listed = try await client.listParts(uploadID: uploadID) {
            for part in listed {
                print("   part \(part.number) ETag \(part.etag) size \(part.size)")
            }
        }

        print("\n4. Complete")
        let (status, body) = try await client.send(MultipartRequests.complete(uploadID: uploadID, parts: parts), "complete")
        guard (200..<300).contains(status) else {
            await client.abortQuietly(uploadID)
            throw ProbeError.status("complete", status)
        }
        print("   body: \(String(decoding: body, as: UTF8.self))")
        if let error = MultipartXML.error(in: body) {
            print("   the 200 carries <Error>: \(error.code) \(error.message ?? "")")
        }

        print("\n5. HEAD (Content-Length \(11 * mib) and Cache-Control no-cache expected)")
        let head = try await client.head()
        print("   Content-Length \(head?.value(forHTTPHeaderField: "Content-Length") ?? "none"), "
              + "Cache-Control \(head?.value(forHTTPHeaderField: "Cache-Control") ?? "none")")

        print("\n6. DELETE")
        try await client.deleteObject()
    }

    // MARK: Step 7

    static func abortedUpload(_ client: Client, publicRead: Bool) async throws {
        print("\n7. Create, one part, Abort, then ListParts and Complete on the aborted id (404 NoSuchUpload expected)")
        let uploadID = try await client.create(publicRead: publicRead)
        let part: MultipartPart
        do {
            part = try await client.uploadPart(uploadID: uploadID, number: 1, data: randomData(1 * mib))
        } catch {
            await client.abortQuietly(uploadID)
            throw error
        }
        let (abortStatus, _) = try await client.send(MultipartRequests.abort(uploadID: uploadID), "abort")
        if !(200..<300).contains(abortStatus) {
            print("   the upload was not aborted; the lifecycle rule removes it")
        }
        _ = try await client.send(MultipartRequests.listParts(uploadID: uploadID, marker: nil), "list parts, aborted id")
        let (completeStatus, _) = try await client.send(MultipartRequests.complete(uploadID: uploadID, parts: [part]),
                                                                  "complete, aborted id")
        if (200..<300).contains(completeStatus) {
            print("   the Complete on the aborted id succeeded; deleting the object")
            try await client.deleteObject()
        }
    }

    // MARK: Steps 8 and 9

    /// 2 GiB of a sparse file in `partSize` parts, three in flight, each part read with its own
    /// FileHandle and hashed as the app does. Pauses 20 s at half the parts for `footprint`.
    static func largeUpload(_ client: Client, partSize: Int, publicRead: Bool) async throws {
        let total: Int64 = 2 * 1024 * 1024 * 1024
        let count = Int((total + Int64(partSize) - 1) / Int64(partSize))
        print("\n\(partSize == 16 * mib ? 8 : 9). 2 GiB sparse file in \(partSize / mib) MiB parts (\(count)), three in flight")
        let file = try TemporaryFile.make(size: total)
        defer { TemporaryFile.remove() }

        let uploadID = try await client.create(publicRead: publicRead)
        var parts: [MultipartPart] = []
        do {
            parts = try await withThrowingTaskGroup(of: MultipartPart.self) { group in
                var next = 1
                func add() {
                    let number = next
                    next += 1
                    let offset = Int64(number - 1) * Int64(partSize)
                    let length = Int(min(Int64(partSize), total - offset))
                    group.addTask {
                        let data = try await readPart(of: file, offset: offset, length: length)
                        return try await client.uploadPart(uploadID: uploadID, number: number, data: data)
                    }
                }
                while next <= min(3, count) { add() }
                var parts: [MultipartPart] = []
                for try await part in group {
                    parts.append(part)
                    if parts.count == count / 2 {
                        print("halfway, pid \(getpid()): run footprint \(getpid()) now")
                        try await Task.sleep(for: .seconds(20))
                    }
                    if next <= count { add() }
                }
                return parts
            }
        } catch {
            await client.abortQuietly(uploadID)
            throw error
        }

        let (status, body) = try await client.send(MultipartRequests.complete(uploadID: uploadID, parts: parts), "complete")
        guard (200..<300).contains(status) else {
            await client.abortQuietly(uploadID)
            throw ProbeError.status("complete", status)
        }
        if let error = MultipartXML.error(in: body) {
            print("   the 200 carries <Error>: \(error.code) \(error.message ?? "")")
        }
        try await client.deleteObject()
    }

    /// One part read into memory with `seek(toOffset:)` and `read(upToCount:)`, off the caller.
    @concurrent
    static func readPart(of url: URL, offset: Int64, length: Int) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length else { throw ProbeError.shortRead(offset) }
        return data
    }

    static func randomData(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            var generator = SystemRandomNumberGenerator()
            let words = raw.bindMemory(to: UInt64.self)
            for index in words.indices { words[index] = generator.next() }
        }
        return data
    }

    static func randomSuffix() -> String {
        let letters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}

enum ProbeError: Error, CustomStringConvertible {
    case status(String, Int)
    case noUploadID
    case noETag(Int)
    case noHTTPResponse
    case shortRead(Int64)

    var description: String {
        switch self {
        case .status(let label, let status): "\(label) answered \(status)"
        case .noUploadID: "Create's answer has no <UploadId>"
        case .noETag(let number): "part \(number) answered with no ETag"
        case .noHTTPResponse: "no HTTP response"
        case .shortRead(let offset): "short read at \(offset)"
        }
    }
}

/// Sends `MultipartRequests` calls to `/<bucket>/<key>`, path-style, signed with `S3Signer`.
final class Client: Sendable {
    let bucket: String
    let region: String
    let endpoint: URLComponents
    let key: String
    let credentials: AWSCredentials
    let session: URLSession

    init(bucket: String, region: String, endpoint: URLComponents, key: String, credentials: AWSCredentials) {
        self.bucket = bucket
        self.region = region
        self.endpoint = endpoint
        self.key = key
        self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    var path: String { "/\(bucket)/\(key)" }

    func create(publicRead: Bool) async throws -> String {
        let call = MultipartRequests.create(contentType: "video/mp4", cacheControl: "no-cache", publicRead: publicRead)
        let (status, body) = try await send(call, "create")
        guard (200..<300).contains(status) else { throw ProbeError.status("create", status) }
        guard let uploadID = MultipartXML.uploadID(in: body) else { throw ProbeError.noUploadID }
        print("   upload id \(uploadID)")
        return uploadID
    }

    func uploadPart(uploadID: String, number: Int, data: Data) async throws -> MultipartPart {
        let call = MultipartRequests.uploadPart(uploadID: uploadID, number: number, data: data)
        let (status, _, response) = try await exchange(call, "part \(number)")
        guard (200..<300).contains(status) else { throw ProbeError.status("part \(number)", status) }
        guard let etag = response.value(forHTTPHeaderField: "ETag") else { throw ProbeError.noETag(number) }
        return MultipartPart(number: number, etag: etag, size: Int64(data.count))
    }

    /// Every page of ListParts, or nil when a page fails (its code is printed).
    func listParts(uploadID: String) async throws -> [MultipartPart]? {
        var parts: [MultipartPart] = []
        var marker: Int?
        while true {
            let (status, body) = try await send(MultipartRequests.listParts(uploadID: uploadID, marker: marker), "list parts")
            guard (200..<300).contains(status), let page = MultipartXML.partsPage(in: body) else { return nil }
            parts += page.parts
            guard page.isTruncated, let next = page.nextMarker, next != marker else { return parts }
            marker = next
        }
    }

    func head() async throws -> HTTPURLResponse? {
        let (status, _, response) = try await exchange(MultipartRequests.Call(method: "HEAD", query: []), "head")
        return (200..<300).contains(status) ? response : nil
    }

    func deleteObject() async throws {
        _ = try await send(MultipartRequests.Call(method: "DELETE", query: []), "delete")
    }

    func abortQuietly(_ uploadID: String) async {
        _ = try? await send(MultipartRequests.abort(uploadID: uploadID), "abort after failure")
    }

    func send(_ call: MultipartRequests.Call, _ label: String) async throws -> (Int, Data) {
        let (status, body, _) = try await exchange(call, label)
        return (status, body)
    }

    /// Signs and sends `call`, and prints its method, status and time. A non-2xx answer prints only
    /// the body's `<Code>` and `<Message>`: a signature error echoes the canonical request and the
    /// string to sign, which can hold the session token.
    func exchange(_ call: MultipartRequests.Call, _ label: String) async throws -> (Int, Data, HTTPURLResponse) {
        var components = endpoint
        components.percentEncodedPath = S3Signer.uriEncode(path, keepSlash: true)
        components.percentEncodedQuery = call.query.isEmpty ? nil : S3Signer.canonicalQuery(call.query)
        guard let url = components.url, let host = url.host() else { throw ProbeError.noHTTPResponse }
        var headers = call.headers
        headers.append((name: "host", value: url.port.map { "\(host):\($0)" } ?? host))
        headers.append((name: "x-amz-content-sha256", value: call.payloadHash))
        let signed = S3Signer.sign(
            S3Signer.Request(method: call.method, path: path, query: call.query, headers: headers, payloadHash: call.payloadHash),
            credentials: credentials, region: region, date: Date())

        var request = URLRequest(url: url)
        request.httpMethod = call.method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for header in headers where header.name != "host" {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        for header in signed.headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let start = Date()
        let delegate = RefuseRedirects()
        let (body, response) = call.body.isEmpty
            ? try await session.data(for: request, delegate: delegate)
            : try await session.upload(for: request, from: call.body, delegate: delegate)
        guard let http = response as? HTTPURLResponse else { throw ProbeError.noHTTPResponse }
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("\(call.method) \(label): \(http.statusCode) in \(ms) ms")
        if !(200..<300).contains(http.statusCode) {
            if let error = MultipartXML.error(in: body) {
                print("   <Code> \(error.code), <Message> \(error.message ?? "none")")
            } else if let region = http.value(forHTTPHeaderField: "x-amz-bucket-region") {
                print("   x-amz-bucket-region \(region)")
            }
        }
        return (http.statusCode, body, http)
    }
}

/// Refuses HTTP redirects, so a signed request is never replayed to another host.
final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The sparse 2 GiB file, removed at the end, on failure and on Control-C or a TERM.
enum TemporaryFile {
    static let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("r4-multipart-\(getpid()).bin")
    nonisolated(unsafe) static var sources: [DispatchSourceSignal] = []

    static func make(size: Int64) throws -> URL {
        remove()
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
        return url
    }

    static func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    static func watchSignals() {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                remove()
                print("\nstopped by signal \(signalNumber); any open upload is left to the lifecycle rule")
                exit(1)
            }
            source.resume()
            sources.append(source)
        }
    }
}
