// R4 probe D1: a signed GET through URLSessionDownloadTask with progress, a cancel with resume
// data at 50 %, a resume 2 s later, and a second resume from the same data 16 minutes after
// signing. Tim's to run, on an uploaded recording of at least 100 MB; it only reads the bucket.
//
// Build from the repository root (a build of more than one file, so this is an @main type with no
// top-level code):
//   xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/r4-download \
//     docs/superpowers/research/recording-probes/r4-download.swift TidyShot/Upload/S3Signer.swift \
//     TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/MultipartRequests.swift TidyShot/Upload/MultipartXML.swift
// Run:
//   AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… [AWS_SESSION_TOKEN=…] \
//     /tmp/r4-download <bucket> <region> <endpoint> <key>

import Foundation

@main
enum R4Download {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 5 else {
            print("usage: r4-download <bucket> <region> <endpoint> <key>")
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
        let landing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("r4-download-\(getpid()).bin")
        defer { try? FileManager.default.removeItem(at: landing) }

        // As S3Destination.uncachedSession is configured.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)

        let signedAt = Date()
        let request = signedGET(bucket: args[1], key: args[4], region: args[2], endpoint: endpoint,
                                credentials: credentials, date: signedAt)
        print("signed at \(signedAt)")

        print("\n1. Download, cancelling at 50 %")
        let first = Watcher(label: "first", landing: landing, cancelAtHalf: true)
        let firstTask = session.downloadTask(with: request)
        firstTask.delegate = first
        firstTask.resume()
        let ended = await first.ended()
        guard case .resumeData(let resumeData) = ended else {
            print("   the download ended before 50 %: \(ended)")
            try? FileManager.default.removeItem(at: landing)
            exit(1)
        }
        print("2. resume data: \(resumeData.map { "\($0.count) bytes" } ?? "none")")
        let fullLength = first.contentLength
        guard let resumeData else { exit(1) }

        // The resume data names URLSession's partial file, and step 3's finished download moves that
        // file away. A copy of it, put back before step 4, lets the late resume reach the bucket.
        let partial = partialFile(in: resumeData)
        let aside = landing.appendingPathExtension("partial")
        defer { try? FileManager.default.removeItem(at: aside) }
        if let partial, (try? FileManager.default.copyItem(at: partial, to: aside)) != nil {
            print("   partial file \(partial.lastPathComponent) copied aside for step 4")
        } else {
            print("   the partial file the resume data names was not found or not copied; "
                  + "a step 4 failure with no status is then inconclusive")
        }

        print("\n3. Resume after 2 s")
        try? await Task.sleep(for: .seconds(2))
        let second = Watcher(label: "resume", landing: landing, cancelAtHalf: false)
        let secondTask = session.downloadTask(withResumeData: resumeData)
        secondTask.delegate = second
        secondTask.resume()
        print("   \(await second.ended())")
        let size = (try? FileManager.default.attributesOfItem(atPath: landing.path)[.size] as? Int64) ?? nil
        print("   file size \(size.map(String.init) ?? "none"), first response Content-Length \(fullLength.map(String.init) ?? "none"), "
              + "match \(size != nil && size == fullLength)")
        try? FileManager.default.removeItem(at: landing)

        let lateAt = signedAt.addingTimeInterval(16 * 60)
        let wait = lateAt.timeIntervalSinceNow
        print("\n4. Resume again from the same data at 16 minutes after signing, in \(Int(max(0, wait))) s (403 expected)")
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        if let partial, FileManager.default.fileExists(atPath: aside.path) {
            try? FileManager.default.removeItem(at: partial)
            do {
                try FileManager.default.copyItem(at: aside, to: partial)
                print("   partial file put back")
            } catch {
                print("   the partial file was not put back (\(error)); a failure with no status is inconclusive")
            }
        }
        let late = Watcher(label: "late resume", landing: landing, cancelAtHalf: false)
        let lateTask = session.downloadTask(withResumeData: resumeData)
        lateTask.delegate = late
        lateTask.resume()
        print("   \(await late.ended())")
        if let partial { try? FileManager.default.removeItem(at: partial) }
        print("done")
    }

    /// The partial file a resume data plist names: `NSURLSessionResumeInfoTempFileName` (a name in
    /// the temporary directory) or `NSURLSessionResumeInfoLocalPath`, in a plain dictionary or among a
    /// keyed archive's `$objects`. Nil when no named file exists.
    static func partialFile(in resumeData: Data) -> URL? {
        guard let plist = try? PropertyListSerialization.propertyList(from: resumeData, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        var names: [String] = []
        for key in ["NSURLSessionResumeInfoTempFileName", "NSURLSessionResumeInfoLocalPath"] {
            if let name = dictionary[key] as? String { names.append(name) }
        }
        if let objects = dictionary["$objects"] as? [Any] {
            names += objects.compactMap { $0 as? String }
                .filter { $0.hasPrefix("CFNetworkDownload_") || $0.hasPrefix("/") }
        }
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        for name in names {
            let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : temporary.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return url
            }
        }
        return nil
    }

    /// The GET as the app signs it: path-style `/<bucket>/<key>`, `host` and the empty payload hash
    /// signed, through `MultipartRequests.Call` for the method, query and hash.
    static func signedGET(bucket: String, key: String, region: String, endpoint: URLComponents,
                          credentials: AWSCredentials, date: Date) -> URLRequest {
        let call = MultipartRequests.Call(method: "GET", query: [])
        let path = "/\(bucket)/\(key)"
        var components = endpoint
        components.percentEncodedPath = S3Signer.uriEncode(path, keepSlash: true)
        components.percentEncodedQuery = call.query.isEmpty ? nil : S3Signer.canonicalQuery(call.query)
        let url = components.url!
        let host = url.host() ?? ""
        var headers = call.headers
        headers.append((name: "host", value: url.port.map { "\(host):\($0)" } ?? host))
        headers.append((name: "x-amz-content-sha256", value: call.payloadHash))
        let signed = S3Signer.sign(
            S3Signer.Request(method: call.method, path: path, query: call.query, headers: headers, payloadHash: call.payloadHash),
            credentials: credentials, region: region, date: date)
        var request = URLRequest(url: url)
        request.httpMethod = call.method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for header in headers where header.name != "host" {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        for header in signed.headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        return request
    }
}

enum Ending: CustomStringConvertible {
    case resumeData(Data?)
    case finished(status: Int?, detail: String)
    case failed(status: Int?, error: String)

    var description: String {
        switch self {
        case .resumeData(let data): "cancelled with \(data.map { "\($0.count) bytes of" } ?? "no") resume data"
        case .finished(let status, let detail): "finished, status \(status.map(String.init) ?? "none"), \(detail)"
        case .failed(let status, let error): "failed, status \(status.map(String.init) ?? "none"): \(error)"
        }
    }
}

/// One task's delegate: prints each `didWriteData` as a fraction with the time since the task
/// started, cancels with resume data at 50 % when asked, moves a finished file to `landing`, and
/// refuses redirects. URLSession calls it on its own queue; the lock guards its state.
final class Watcher: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let label: String
    let landing: URL
    let cancelAtHalf: Bool
    private let lock = NSLock()
    private let start = Date()
    private var cancelled = false
    private var printedFirst = false
    private var detail = ""
    private var ending: Ending?
    private var continuation: CheckedContinuation<Ending, Never>?
    private(set) var contentLength: Int64?

    init(label: String, landing: URL, cancelAtHalf: Bool) {
        self.label = label
        self.landing = landing
        self.cancelAtHalf = cancelAtHalf
    }

    func ended() async -> Ending {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let ending {
                lock.unlock()
                continuation.resume(returning: ending)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    private func end(_ value: Ending) {
        lock.lock()
        guard ending == nil else { lock.unlock(); return }
        ending = value
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: value)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : -1
        let seconds = Date().timeIntervalSince(start)
        lock.lock()
        let first = !printedFirst
        printedFirst = true
        if contentLength == nil, let http = downloadTask.response as? HTTPURLResponse, http.statusCode == 200 {
            contentLength = http.expectedContentLength
        }
        let shouldCancel = cancelAtHalf && !cancelled && fraction >= 0.5
        if shouldCancel { cancelled = true }
        lock.unlock()
        print(String(format: "   %@ +%.3f s %.4f%@", label, seconds, fraction, first ? " (first)" : ""))
        if shouldCancel {
            downloadTask.cancel { [self] data in end(.resumeData(data)) }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let http = downloadTask.response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        var text = "Content-Length \(http?.value(forHTTPHeaderField: "Content-Length") ?? "none"), "
            + "Content-Range \(http?.value(forHTTPHeaderField: "Content-Range") ?? "none")"
        if (200..<300).contains(status) {
            try? FileManager.default.removeItem(at: landing)
            do {
                try FileManager.default.moveItem(at: location, to: landing)
            } catch {
                text += ", move failed: \(error)"
            }
        } else if let handle = try? FileHandle(forReadingFrom: location) {
            // Only <Code> and <Message>: a signature error echoes the canonical request.
            let body = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
            try? handle.close()
            if let error = MultipartXML.error(in: body) {
                text += ", <Code> \(error.code), <Message> \(error.message ?? "none")"
            }
        }
        lock.lock()
        detail = text
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        lock.lock()
        let detail = self.detail
        let wasCancelled = cancelled
        lock.unlock()
        if let error {
            // The cancel's resume data arrives through its own handler.
            if wasCancelled, (error as? URLError)?.code == .cancelled { return }
            end(.failed(status: status, error: "\(error)"))
        } else {
            end(.finished(status: status, detail: detail))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
