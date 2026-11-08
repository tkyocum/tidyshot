import Foundation

/// The five multipart calls as method, decoded query, extra headers and body. Pure, and shared
/// with the R4 probes, so M1 sends the app's own requests. It builds no path: the app takes it
/// from `S3DestinationConfig.objectPath(for:)`, the probes from their own `/<bucket>/<key>`.
nonisolated enum MultipartRequests {
    struct Call: Sendable {
        var method: String
        /// Decoded names and values; the URL's query and the canonical query are both built from them.
        var query: [(name: String, value: String)]
        /// The extra headers, all signed. `host` and `x-amz-content-sha256` are the caller's.
        var headers: [(name: String, value: String)]
        var body: Data
        /// `S3Signer.sha256Hex(body)`, never `UNSIGNED-PAYLOAD` (a bucket policy may deny it).
        var payloadHash: String

        init(method: String, query: [(name: String, value: String)],
             headers: [(name: String, value: String)] = [], body: Data = Data()) {
            self.method = method
            self.query = query
            self.headers = headers
            self.body = body
            self.payloadHash = S3Signer.sha256Hex(body)
        }
    }

    /// The object's headers, all signed so a change in transit fails the signature: the single PUT
    /// and Create send the same ones.
    static func objectHeaders(contentType: String, cacheControl: String?, publicRead: Bool) -> [(name: String, value: String)] {
        var headers = [(name: "content-type", value: contentType)]
        if let cacheControl {
            headers.append((name: "cache-control", value: cacheControl))
        }
        if publicRead {
            headers.append((name: "x-amz-acl", value: "public-read"))
        }
        return headers
    }

    /// CreateMultipartUpload, with the object's headers.
    static func create(contentType: String, cacheControl: String?, publicRead: Bool) -> Call {
        Call(method: "POST", query: [(name: "uploads", value: "")],
             headers: objectHeaders(contentType: contentType, cacheControl: cacheControl, publicRead: publicRead))
    }

    static func uploadPart(uploadID: String, number: Int, data: Data) -> Call {
        Call(method: "PUT", query: [(name: "partNumber", value: String(number)), (name: "uploadId", value: uploadID)],
             body: data)
    }

    /// The explicit type matters: URLSession gives a POST with a body and no type
    /// `application/x-www-form-urlencoded`, which AWS refuses on Complete.
    static func complete(uploadID: String, parts: [MultipartPart]) -> Call {
        Call(method: "POST", query: [(name: "uploadId", value: uploadID)],
             headers: [(name: "content-type", value: "application/xml")], body: completeBody(parts))
    }

    static func abort(uploadID: String) -> Call {
        Call(method: "DELETE", query: [(name: "uploadId", value: uploadID)])
    }

    static func listParts(uploadID: String, marker: Int?) -> Call {
        var query = [(name: "uploadId", value: uploadID)]
        if let marker {
            query.append((name: "part-number-marker", value: String(marker)))
        }
        return Call(method: "GET", query: query)
    }

    /// Complete's body: the parts in ascending order, each ETag as S3 gave it (quotes included),
    /// UTF-8 with no declaration and no whitespace.
    static func completeBody(_ parts: [MultipartPart]) -> Data {
        var xml = "<CompleteMultipartUpload>"
        for part in parts.sorted(by: { $0.number < $1.number }) {
            xml += "<Part><PartNumber>\(part.number)</PartNumber><ETag>\(part.etag)</ETag></Part>"
        }
        xml += "</CompleteMultipartUpload>"
        return Data(xml.utf8)
    }
}
