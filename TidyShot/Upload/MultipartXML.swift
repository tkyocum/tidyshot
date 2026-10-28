import Foundation

/// One uploaded part of a multipart upload: its number, the `ETag` S3 gave it and its size.
/// `etag` is kept as S3 sends it, quotes included (`"abc"`), and is written back that way in
/// Complete's body.
nonisolated struct MultipartPart: Codable, Equatable, Hashable, Sendable {
    var number: Int
    var etag: String
    var size: Int64
}

/// Small element scans over S3's multipart answers (Create's `UploadId`, an `Error`, and a
/// ListParts page). Pure, so the app and the R4 probes share them.
///
/// Elements are found as `S3Destination`'s `elementText` finds them: `<name>…</name>` with no
/// nested markup, and each `<Part>…</Part>` block scanned on its own. The scans read only the
/// elements named here; an error body's other elements (`<CanonicalRequest>`, `<StringToSign>`)
/// are never read.
nonisolated enum MultipartXML {
    struct ErrorBody: Equatable, Sendable {
        var code: String
        var message: String?
    }

    struct PartsPage: Equatable, Sendable {
        var parts: [MultipartPart]
        var isTruncated: Bool
        var nextMarker: Int?
    }

    /// The text of `<UploadId>` in Create's answer.
    static func uploadID(in body: Data) -> String? {
        elementText("UploadId", in: text(body))
    }

    /// The `<Error>` in `body`, when it has a non-empty `<Code>`. Complete can answer 200 with one.
    static func error(in body: Data) -> ErrorBody? {
        guard let error = blocks("Error", in: text(body)).first,
              let code = elementText("Code", in: error) else { return nil }
        return ErrorBody(code: code, message: elementText("Message", in: error))
    }

    /// One page of ListParts: every `<Part>` with a `<PartNumber>`, `<ETag>` and `<Size>` (a part
    /// missing one is left out), `<IsTruncated>` and `<NextPartNumberMarker>`. Nil when the body is
    /// not a `ListPartsResult`.
    static func partsPage(in body: Data) -> PartsPage? {
        let text = text(body)
        guard text.contains("<ListPartsResult>") || text.contains("<ListPartsResult ") else { return nil }
        let parts = blocks("Part", in: text).compactMap { block -> MultipartPart? in
            guard let number = elementText("PartNumber", in: block).flatMap({ Int($0) }),
                  let etag = elementText("ETag", in: block),
                  let size = elementText("Size", in: block).flatMap({ Int64($0) }) else { return nil }
            return MultipartPart(number: number, etag: etag, size: size)
        }
        return PartsPage(parts: parts,
                         isTruncated: elementText("IsTruncated", in: text) == "true",
                         nextMarker: elementText("NextPartNumberMarker", in: text).flatMap { Int($0) })
    }

    /// The five XML entities replaced, `&amp;` last so `&amp;lt;` reads `&lt;`. S3 writes a listed
    /// ETag as `&quot;abc&quot;`.
    static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func text(_ body: Data) -> String {
        String(decoding: body, as: UTF8.self)
    }

    /// The unescaped text of the first `<name>…</name>` in `text`, or nil when it is missing,
    /// empty, or contains markup.
    private static func elementText(_ name: String, in text: Substring) -> String? {
        guard let open = text.firstRange(of: "<\(name)>"),
              let close = text[open.upperBound...].firstRange(of: "</\(name)>") else { return nil }
        let value = text[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("<") else { return nil }
        return unescaped(value)
    }

    private static func elementText(_ name: String, in text: String) -> String? {
        elementText(name, in: text[...])
    }

    /// The contents of every `<name>…</name>` in `text`, in order, markup included.
    private static func blocks(_ name: String, in text: String) -> [Substring] {
        var result: [Substring] = []
        var rest = text[...]
        while let open = rest.firstRange(of: "<\(name)>"),
              let close = rest[open.upperBound...].firstRange(of: "</\(name)>") {
            result.append(rest[open.upperBound..<close.lowerBound])
            rest = rest[close.upperBound...]
        }
        return result
    }
}
