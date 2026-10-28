import Foundation

/// A multipart upload that may still exist on the server: enough to abort it, signed with the
/// credentials stored at the time.
nonisolated struct MultipartRef: Codable, Hashable, Sendable {
    var uploadID: String
    var key: String
    var location: ObjectLocation
}

/// A record's multipart upload, written once when Create succeeds and kept until the upload
/// finishes, so a Retry can resume it (also after a relaunch) and Delete knows what to abort.
nonisolated struct MultipartUploadState: Codable, Equatable, Sendable {
    var uploadID: String
    var key: String
    var location: ObjectLocation
    /// Fixed at Create and never recomputed.
    var partSize: Int64
    /// The size of the file the upload sends.
    var byteCount: Int64
    /// The modification date of the file the upload sends, checked before a resume. Coded as a
    /// `Double`, not a `Date` (see `encode(to:)`).
    var sourceModified: Date
    /// The file the upload sends: the kept Clop copy, or the record's own file.
    var sourcePath: String
    var startedAt: Date

    /// The upload to abort.
    var ref: MultipartRef { MultipartRef(uploadID: uploadID, key: key, location: location) }
}

nonisolated extension MultipartUploadState {
    private enum CodingKeys: String, CodingKey {
        case uploadID, key, location, partSize, byteCount, sourceModified, sourcePath, startedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uploadID = try container.decode(String.self, forKey: .uploadID)
        key = try container.decode(String.self, forKey: .key)
        location = try container.decode(ObjectLocation.self, forKey: .location)
        partSize = try container.decode(Int64.self, forKey: .partSize)
        byteCount = try container.decode(Int64.self, forKey: .byteCount)
        sourceModified = Date(timeIntervalSinceReferenceDate: try container.decode(Double.self, forKey: .sourceModified))
        sourcePath = try container.decode(String.self, forKey: .sourcePath)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
    }

    /// `sourceModified` goes out as its `timeIntervalSinceReferenceDate`: `HistoryStore` writes
    /// dates as ISO 8601 with milliseconds, which would cut an APFS modification date and fail
    /// every resume's source check after a relaunch. JSON round-trips a `Double` exactly.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uploadID, forKey: .uploadID)
        try container.encode(key, forKey: .key)
        try container.encode(location, forKey: .location)
        try container.encode(partSize, forKey: .partSize)
        try container.encode(byteCount, forKey: .byteCount)
        try container.encode(sourceModified.timeIntervalSinceReferenceDate, forKey: .sourceModified)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encode(startedAt, forKey: .startedAt)
    }
}

/// The parts sent so far for one upload id, rewritten after each part (`multipart/<recordID>.json`).
/// `completeSent` is set before the first Complete for that id goes out.
nonisolated struct MultipartSidecar: Codable, Equatable, Sendable {
    var uploadID: String
    var completeSent: Bool
    var parts: [MultipartPart]
}

/// What a `.file` job sends, as the coordinator read it: where to, which file, its size and its
/// modification date. The queue builds `MultipartUploadState` from it.
nonisolated struct MultipartSource: Equatable, Sendable {
    var location: ObjectLocation
    var path: String
    var byteCount: Int64
    var modified: Date
}
