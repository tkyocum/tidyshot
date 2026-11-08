import Foundation

/// The six multipart calls. Each request comes from `MultipartRequests`, is signed with its
/// payload's SHA-256 and is sent with an `UploadProgressDelegate`, so redirects are refused. Every
/// error body goes through `excerpt`.
extension S3Destination {
    func createMultipartUpload(key: String, contentType: String, cacheControl: String?) async throws -> String {
        let call = MultipartRequests.create(contentType: contentType, cacheControl: cacheControl,
                                            publicRead: config.sendPublicReadACL)
        let (body, http) = try await send(call, key: key)
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(http, bodyText: Self.excerpt(body))
        }
        guard let uploadID = MultipartXML.uploadID(in: body) else {
            throw UploadError.httpStatus(http.statusCode, body: "no UploadId")
        }
        return uploadID
    }

    /// The part is hashed off the caller's actor (`partCall`) and sent from memory with
    /// `upload(for:from:)`, so the bytes hashed are the bytes sent.
    func uploadPart(key: String, uploadID: String, number: Int, data: Data,
                    progress: @escaping @Sendable (Int64) -> Void) async throws -> String {
        let call = await Self.partCall(uploadID: uploadID, number: number, data: data)
        let (body, http) = try await send(call, key: key, delegate: UploadProgressDelegate(onBytesSent: progress))
        guard (200..<300).contains(http.statusCode) else { throw Self.multipartFailure(body, http) }
        guard let etag = http.value(forHTTPHeaderField: "ETag"), !etag.isEmpty else {
            throw UploadError.httpStatus(http.statusCode, body: "no ETag")
        }
        return etag
    }

    /// A 200 can carry an `<Error>`, which is not a success. `EntityTooSmall`, `EntityTooLarge`
    /// and every other failure not named here is an ordinary `failure`.
    func completeMultipartUpload(key: String, uploadID: String, parts: [MultipartPart]) async throws {
        let (body, http) = try await send(MultipartRequests.complete(uploadID: uploadID, parts: parts), key: key)
        if (200..<300).contains(http.statusCode) {
            if let error = MultipartXML.error(in: body) {
                throw UploadError.completeError(code: error.code, body: Self.excerpt(body, error: error))
            }
            return
        }
        throw Self.multipartFailure(body, http)
    }

    func abortMultipartUpload(key: String, uploadID: String) async throws -> MultipartAbortResult {
        let (body, http) = try await send(MultipartRequests.abort(uploadID: uploadID), key: key)
        if (200..<300).contains(http.statusCode) { return .aborted }
        if http.statusCode == 404 { return .notFound }
        throw Self.failure(http, bodyText: Self.excerpt(body))
    }

    /// Pages until `IsTruncated` is false. S3 sends `NextPartNumberMarker` on a last page too, so
    /// the marker alone does not end the loop; a truncated page whose marker does not move ends
    /// it as well, so a server that keeps answering the same page cannot loop. A part left out
    /// that way is sent again by a resume.
    func listParts(key: String, uploadID: String) async throws -> [MultipartPart] {
        var parts: [MultipartPart] = []
        var marker: Int?
        while true {
            let (body, http) = try await send(MultipartRequests.listParts(uploadID: uploadID, marker: marker), key: key)
            guard (200..<300).contains(http.statusCode) else { throw Self.multipartFailure(body, http) }
            guard let page = MultipartXML.partsPage(in: body) else {
                throw UploadError.httpStatus(http.statusCode, body: "unreadable part list")
            }
            parts += page.parts
            guard page.isTruncated, let next = page.nextMarker, next > (marker ?? 0) else { return parts }
            marker = next
        }
    }

    /// Signs `call` for `key` and sends it: a body with `upload(for:from:)`, none with `data(for:)`.
    private func send(_ call: MultipartRequests.Call, key: String,
                      delegate: UploadProgressDelegate = UploadProgressDelegate()) async throws -> (Data, HTTPURLResponse) {
        let request = try signedRequest(method: call.method, key: key, query: call.query, payloadHash: call.payloadHash,
                                        extraHeaders: call.headers)
        let (body, response): (Data, URLResponse)
        if call.body.isEmpty {
            (body, response) = try await session.data(for: request, delegate: delegate)
        } else {
            (body, response) = try await session.upload(for: request, from: call.body, delegate: delegate)
        }
        return (body, try Self.httpResponse(response))
    }

    /// Builds the part's call, whose hash of up to 64 MiB must not run on the caller's actor.
    @concurrent
    private static func partCall(uploadID: String, number: Int, data: Data) async -> MultipartRequests.Call {
        MultipartRequests.uploadPart(uploadID: uploadID, number: number, data: data)
    }

    /// The error for a failed multipart answer: a gone upload id and a rejected part list by their
    /// codes (only `<Code>` and `<Message>` are read), else the usual `failure`.
    private static func multipartFailure(_ body: Data, _ http: HTTPURLResponse) -> UploadError {
        let error = MultipartXML.error(in: body)
        switch (http.statusCode, error?.code) {
        case (404, "NoSuchUpload"?): return .noSuchUpload
        case (400, "InvalidPart"?), (400, "InvalidPartOrder"?): return .partsRejected(body: excerpt(body, error: error))
        default: return failure(http, bodyText: excerpt(body, error: error))
        }
    }
}
