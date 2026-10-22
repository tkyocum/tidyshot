import CryptoKit
import Foundation

/// AWS Signature Version 4 for one HTTP request. Pure functions, no networking.
/// `nonisolated` so the upload actor can call it without hopping to the main actor.
///
/// S3 rules: the path is percent-encoded once (RFC 3986 unreserved set, `/` kept) and is not
/// normalized (no dot-segment removal, no slash collapsing). `normalizePath: true` exists only
/// so the generic AWS test suite can run; TidyShot always signs S3 requests unnormalized.
nonisolated enum S3Signer {
    /// The parts of a request that take part in signing. `path`, query names and values are
    /// the *decoded* values; the signer applies the canonical percent-encoding itself.
    struct Request: Sendable {
        var method: String
        var path: String
        var query: [(name: String, value: String)]
        var headers: [(name: String, value: String)]
        var payloadHash: String

        init(method: String,
             path: String,
             query: [(name: String, value: String)] = [],
             headers: [(name: String, value: String)],
             payloadHash: String) {
            self.method = method
            self.path = path
            self.query = query
            self.headers = headers
            self.payloadHash = payloadHash
        }
    }

    struct Signed: Sendable {
        let canonicalRequest: String
        let stringToSign: String
        let signature: String
        /// Headers to add to the outgoing request: `x-amz-date`, `x-amz-security-token` when a
        /// session token is present, and `authorization`.
        let headers: [(name: String, value: String)]
    }

    static let algorithm = "AWS4-HMAC-SHA256"
    /// SHA-256 of zero bytes; the payload hash for HEAD, GET and DELETE.
    static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// Signs `request`. The caller must already have put `host` and (for S3) `x-amz-content-sha256`
    /// in `request.headers`; every header in the list is signed.
    static func sign(_ request: Request,
                     credentials: AWSCredentials,
                     region: String,
                     service: String = "s3",
                     date: Date,
                     normalizePath: Bool = false) -> Signed {
        let amzDate = amzDateString(date)
        let dateStamp = String(amzDate.prefix(8))

        var headers = request.headers
        headers.append((name: "x-amz-date", value: amzDate))
        if let token = credentials.sessionToken, !token.isEmpty {
            headers.append((name: "x-amz-security-token", value: token))
        }

        let canonicalHeaders = canonicalHeaders(headers)
        let canonicalRequest = [
            request.method.uppercased(),
            canonicalURI(request.path, normalize: normalizePath),
            canonicalQuery(request.query),
            canonicalHeaders.canonical,
            canonicalHeaders.signed,
            request.payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            algorithm,
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let key = signingKey(secret: credentials.secretAccessKey, dateStamp: dateStamp, region: region, service: service)
        let signature = hmacHex(key: key, message: stringToSign)

        let authorization = "\(algorithm) Credential=\(credentials.accessKeyID)/\(scope), "
            + "SignedHeaders=\(canonicalHeaders.signed), Signature=\(signature)"

        var added: [(name: String, value: String)] = [(name: "x-amz-date", value: amzDate)]
        if let token = credentials.sessionToken, !token.isEmpty {
            added.append((name: "x-amz-security-token", value: token))
        }
        added.append((name: "authorization", value: authorization))

        return Signed(canonicalRequest: canonicalRequest, stringToSign: stringToSign, signature: signature, headers: added)
    }

    // MARK: Canonical pieces

    /// Percent-encodes every byte outside `A-Z a-z 0-9 - _ . ~`, using uppercase hex.
    /// With `keepSlash`, `/` is left alone (object key paths); without it, `/` becomes `%2F` (query parts).
    static func uriEncode(_ string: String, keepSlash: Bool) -> String {
        var output = ""
        output.reserveCapacity(string.utf8.count)
        for byte in string.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
                output.unicodeScalars.append(UnicodeScalar(byte))
            case UInt8(ascii: "/") where keepSlash:
                output.append("/")
            default:
                output.append("%")
                output.append(hexDigit(byte >> 4))
                output.append(hexDigit(byte & 0x0F))
            }
        }
        return output
    }

    static func canonicalURI(_ path: String, normalize: Bool) -> String {
        var path = path.isEmpty ? "/" : path
        if normalize {
            path = removingDotSegments(path)
        }
        return uriEncode(path, keepSlash: true)
    }

    /// RFC 3986 dot-segment removal plus collapsing of repeated slashes, as the generic AWS
    /// signing rules require for services other than S3.
    static func removingDotSegments(_ path: String) -> String {
        var segments: [Substring] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(segment)
            }
        }
        var result = "/" + segments.joined(separator: "/")
        if path.hasSuffix("/"), result != "/" {
            result += "/"
        }
        return result
    }

    /// Encoded `name=value` pairs sorted by name then value (byte order).
    static func canonicalQuery(_ query: [(name: String, value: String)]) -> String {
        var pairs: [(name: String, value: String)] = query.map { item in
            (name: uriEncode(item.name, keepSlash: false), value: uriEncode(item.value, keepSlash: false))
        }
        pairs.sort { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.value < rhs.value
        }
        let encoded: [String] = pairs.map { "\($0.name)=\($0.value)" }
        return encoded.joined(separator: "&")
    }

    /// Lowercased names, trimmed values with internal whitespace runs collapsed to one space,
    /// duplicate names joined with commas in their original order, sorted by name.
    /// Returns the canonical header block (each line newline-terminated) and the `;` list of names.
    static func canonicalHeaders(_ headers: [(name: String, value: String)]) -> (canonical: String, signed: String) {
        var grouped: [String: [String]] = [:]
        for header in headers {
            let name = header.name.trimmingCharacters(in: .whitespaces).lowercased()
            let value = header.value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            grouped[name, default: []].append(value)
        }
        let names = grouped.keys.sorted()
        let canonical = names.map { "\($0):\(grouped[$0]!.joined(separator: ","))\n" }.joined()
        return (canonical, names.joined(separator: ";"))
    }

    // MARK: Crypto helpers

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { byteHex($0) }.joined()
    }

    /// The size of each read when hashing a file: 4 MiB.
    static let fileHashChunkSize = 4 * 1024 * 1024

    /// SHA-256 of a file's contents, read in `fileHashChunkSize` pieces into one reusable buffer and
    /// fed to an incremental hash, so a recording is never in memory whole. `@concurrent`, so it
    /// never runs on the upload queue's actor. It checks for cancellation before every read, so a
    /// Delete during the hash stops it there.
    @concurrent
    static func sha256Hex(fileAt url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: fileHashChunkSize, alignment: 1)
        defer { buffer.deallocate() }
        while true {
            try Task.checkCancellation()
            let count = Darwin.read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[..<count]))
        }
        return hasher.finalize().map { byteHex($0) }.joined()
    }

    static func signingKey(secret: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        var key = SymmetricKey(data: Data("AWS4\(secret)".utf8))
        for component in [dateStamp, region, service, "aws4_request"] {
            let mac = HMAC<SHA256>.authenticationCode(for: Data(component.utf8), using: key)
            key = SymmetricKey(data: Data(mac))
        }
        return key
    }

    static func hmacHex(key: SymmetricKey, message: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key).map { byteHex($0) }.joined()
    }

    /// `yyyyMMdd'T'HHmmss'Z'` in UTC.
    static func amzDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func hexDigit(_ value: UInt8) -> Character {
        Character(UnicodeScalar(value < 10 ? 0x30 + value : 0x41 + value - 10))
    }

    private static func byteHex(_ byte: UInt8) -> String {
        let digits = Array("0123456789abcdef")
        return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
    }
}
