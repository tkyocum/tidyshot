import Foundation
import UniformTypeIdentifiers

/// What a capture's file holds: a PNG screenshot, an MP4 recording or a GIF recording.
nonisolated enum MediaKind: String, Codable, Sendable {
    case image
    case video
    case gif

    var fileExtension: String {
        switch self {
        case .image: "png"
        case .video: "mp4"
        case .gif: "gif"
        }
    }

    var contentType: String {
        switch self {
        case .image: "image/png"
        case .video: "video/mp4"
        case .gif: "image/gif"
        }
    }

    var utType: UTType {
        switch self {
        case .image: .png
        case .video: .mpeg4Movie
        case .gif: .gif
        }
    }

    /// A GIF uploads as made, with Clop on or off; screenshots and MP4s go through Clop when it
    /// is on and running.
    var isSentToClop: Bool { self != .gif }

    /// An unknown raw value, from a newer TidyShot, reads as `.video`, so `HistoryStore.load`
    /// never sets the whole history aside for it.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaKind(rawValue: raw) ?? .video
    }
}

/// One capture: where its PNG is (if it still exists), its thumbnail, how big it is, and how
/// its upload went.
nonisolated struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
    enum UploadState: Codable, Equatable, Sendable {
        case none
        case uploading(fraction: Double)
        case uploaded(url: URL, key: String)
        case failed(message: String)
    }

    let id: UUID
    let timestamp: Date
    /// The PNG on disk. Nil once an upload-only capture has been uploaded and its temporary
    /// file removed; such a record has only its thumbnail and URL.
    var fileURL: URL?
    /// True while `fileURL` points into the app container's `pending` folder (upload-only mode).
    /// Such a file is deleted after a successful upload; a file in the user's save folder is kept.
    var fileIsTemporary: Bool
    /// File name inside the `thumbnails` folder next to `history.json`. Nil for records written
    /// before thumbnails existed; `ThumbnailProvider` generates one from the local file when it can.
    var thumbnailFileName: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var appName: String?
    var uploadState: UploadState
    /// Where `uploadedKey` and `pendingObjectKey` live: the destination of the queue that
    /// uploaded the object or reserved the key. Nil for records from before Phase 3 and for
    /// captures that never reached a bucket; Delete removes nothing from storage without it.
    var objectLocation: ObjectLocation?
    /// The key a cancelled upload had reserved. Its PUT may have completed on the server as it
    /// was cancelled, so Delete removes this key too, also when a first attempt failed.
    var pendingObjectKey: String?
    /// When an edit from the editor was last written over this capture's file (Save, or the
    /// local write before an Upload). Nil for a capture never edited. A capture-time thumbnail
    /// that finishes late is not named on an edited record, because it shows the original.
    var editedAt: Date?
    /// True once an edit was written locally while the link still serves the earlier upload.
    /// The editor's subtitle then says so. Cleared when an upload of the edit succeeds.
    var uploadIsStale: Bool
    /// Objects the record's earlier uploads left behind: the old key of an Upload as New, or of an
    /// upload after the destination changed, each at its own location. Deleted after the new
    /// upload succeeds; a ref whose DELETE failed stays here, so Delete removes it later.
    var supersededObjects: [ObjectRef]
    /// The link the record had when the editor started an upload over it. Set in the same update
    /// that marks the record uploading; cleared on `.uploaded` and on a handled failure. It
    /// survives a quit or crash mid-upload (`HistoryStore.load` turns `.uploading` into
    /// `.failed`), so the link stays copyable and Delete still finds its object.
    var priorUpload: PriorUpload?
    /// `.video` for a screen recording, whose file is an MP4 and whose pixel size is the video's,
    /// and `.gif` for one saved as a GIF.
    let mediaKind: MediaKind
    /// A recording's length, read from the finished file (a GIF's from its frames). Nil for
    /// screenshots.
    var durationSeconds: Double?
    /// The size in bytes of what the record's link or file points at, for Recent Captures (spec
    /// 2.13): the bytes written at save, the new file after an editor Save, and the bytes sent once
    /// an upload succeeds (Clop's result when it was accepted). A failed upload, or the removal of
    /// the local file alone, leaves it. Nil for a record from before 2.13 until the launch backfill
    /// (`FileSizes`) finds its file, and for good when it has none.
    var byteCount: Int?
    /// The muted stretches of a recording whose muting failed, so its file still holds their sound.
    /// Non-empty is the `Sound not muted` mark (`uploadBlockedReason`). Empty for every other record.
    var unmutedIntervals: [MuteInterval]

    init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false,
         thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?,
         uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, pendingObjectKey: String? = nil,
         editedAt: Date? = nil, uploadIsStale: Bool = false,
         supersededObjects: [ObjectRef] = [], priorUpload: PriorUpload? = nil,
         mediaKind: MediaKind = .image, durationSeconds: Double? = nil, byteCount: Int? = nil,
         unmutedIntervals: [MuteInterval] = []) {
        self.id = id
        self.timestamp = timestamp
        self.fileURL = fileURL
        self.fileIsTemporary = fileIsTemporary
        self.thumbnailFileName = thumbnailFileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.appName = appName
        self.uploadState = uploadState
        self.objectLocation = objectLocation
        self.pendingObjectKey = pendingObjectKey
        self.editedAt = editedAt
        self.uploadIsStale = uploadIsStale
        self.supersededObjects = supersededObjects
        self.priorUpload = priorUpload
        self.mediaKind = mediaKind
        self.durationSeconds = durationSeconds
        self.byteCount = byteCount
        self.unmutedIntervals = unmutedIntervals
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, fileURL, fileIsTemporary, thumbnailFileName, pixelWidth, pixelHeight, appName, uploadState
        case objectLocation, pendingObjectKey, editedAt, uploadIsStale
        case supersededObjects, priorUpload
        case mediaKind, durationSeconds
        case byteCount
        case unmutedIntervals
    }

    /// Phase 2 history files have no `fileIsTemporary`, `thumbnailFileName`, `objectLocation` or
    /// `pendingObjectKey`, and always have a `fileURL`; Phase 3 files have no `editedAt` or
    /// `uploadIsStale`. They decode with the defaults. Files from before Phase 4 have no
    /// supersededObjects or priorUpload either; they decode as [] and nil. Files from before
    /// recording R1 have no `mediaKind` or `durationSeconds`; they decode as `.image` and nil. Files
    /// from before 2.13 have no `byteCount`; it decodes as nil. Files from before recording R2 have
    /// no `unmutedIntervals`; it decodes as []. Encoding is synthesised.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        fileIsTemporary = try container.decodeIfPresent(Bool.self, forKey: .fileIsTemporary) ?? false
        thumbnailFileName = try container.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        uploadState = try container.decode(UploadState.self, forKey: .uploadState)
        objectLocation = try container.decodeIfPresent(ObjectLocation.self, forKey: .objectLocation)
        pendingObjectKey = try container.decodeIfPresent(String.self, forKey: .pendingObjectKey)
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        uploadIsStale = try container.decodeIfPresent(Bool.self, forKey: .uploadIsStale) ?? false
        supersededObjects = try container.decodeIfPresent([ObjectRef].self, forKey: .supersededObjects) ?? []
        priorUpload = try container.decodeIfPresent(PriorUpload.self, forKey: .priorUpload)
        mediaKind = try container.decodeIfPresent(MediaKind.self, forKey: .mediaKind) ?? .image
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
        unmutedIntervals = try container.decodeIfPresent([MuteInterval].self, forKey: .unmutedIntervals) ?? []
    }

    var uploadedURL: URL? {
        if case .uploaded(let url, _) = uploadState { return url }
        return nil
    }

    /// The object key in the bucket, once uploaded.
    var uploadedKey: String? {
        if case .uploaded(_, let key) = uploadState { return key }
        return nil
    }

    /// The link to copy: the uploaded URL, or, while an editor upload runs over an earlier link and
    /// after a quit or crash interrupted it, that earlier link. `uploadedURL` and `uploadedKey`
    /// stay computed from `uploadState` alone.
    var linkURL: URL? { uploadedURL ?? priorUpload?.url }

    /// What an edit written to the capture's file changes on the record: its pixel size, `editedAt`,
    /// and, when the record has a link (`linkURL`, so also one that lives only in `priorUpload`
    /// after an interrupted replace), `uploadIsStale`, because that link still shows the original.
    /// `AppCoordinator.applyLocalEdit` calls this inside `history.update`.
    mutating func recordLocalEdit(pixelWidth: Int, pixelHeight: Int, at editedAt: Date) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.editedAt = editedAt
        if linkURL != nil {
            uploadIsStale = true
        }
    }

    /// What a trim written to a recording's file changes on the record (design, Trim, Save): its
    /// length and `editedAt`. The pixel size stays, and `uploadIsStale` is the Trim pass's own: it
    /// sets it before the put for a record with a link and clears it when the put fails.
    mutating func recordLocalTrim(duration: Double, at editedAt: Date) {
        durationSeconds = duration
        self.editedAt = editedAt
    }

    /// What a trim's write changes on the record (design, Trim, Save; `AppCoordinator.finishTrimWrite`),
    /// in one update: Save and Upload's `.newPendingFile` put points it at `pendingFile`; then
    /// `recordLocalTrim` with the trimmed file's `length`, or the range's when that could not be read
    /// (0); the trimmed file's size, or none when it could not be read (0), for the next launch's
    /// backfill rather than the untrimmed file's; and `unmutedIntervals` emptied, which clears `Sound
    /// not muted`, as the trimmed file was cut from the muted copy.
    mutating func recordTrimWrite(length: TimeInterval, byteCount: Int64, rangeDuration: TimeInterval,
                                  pendingFile: URL?, at editedAt: Date) {
        if let pendingFile {
            fileURL = pendingFile
            fileIsTemporary = true
        }
        recordLocalTrim(duration: length > 0 ? length : rangeDuration, at: editedAt)
        self.byteCount = byteCount > 0 ? Int(byteCount) : nil
        unmutedIntervals = []
    }

    var hasLocalFile: Bool { fileURL != nil }

    /// A recording, MP4 or GIF: no image actions, no editor, and its file is never read for a
    /// thumbnail. A kind from a newer TidyShot reads as `.video`, so it counts too.
    var isTimeBased: Bool { mediaKind != .image }

    static let soundNotMutedTitle = "Sound not muted"
    static let soundNotMutedBody = "Muting failed. The recording is kept in TidyShot and not uploaded. Trim it to fix the sound, or delete it."

    /// Why the record must not be uploaded: `soundNotMutedBody` while it is marked `Sound not
    /// muted`, otherwise nil.
    var uploadBlockedReason: String? {
        unmutedIntervals.isEmpty ? nil : Self.soundNotMutedBody
    }

    /// An upload-only capture that has not been uploaded: its PNG in `pending` is the only copy,
    /// so retention never prunes it.
    var isPendingOnly: Bool { fileIsTemporary && fileURL != nil && uploadedKey == nil }

    /// An upload-only capture whose `pending` file holds an edit its link does not show yet (a
    /// replace that failed). The file is the edit's only copy, so retention never prunes it.
    var keepsUnuploadedEdit: Bool { fileIsTemporary && fileURL != nil && uploadIsStale }

    var isFailed: Bool {
        if case .failed = uploadState { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = uploadState { return true }
        return false
    }
}

/// The link a record had when the editor started an upload over it. `isReplace` is true when that
/// upload PUTs the same key, so the URL stays. It is false when the upload makes a new object and
/// the old key goes to `supersededObjects`.
nonisolated struct PriorUpload: Codable, Equatable, Sendable {
    var url: URL
    var key: String
    var location: ObjectLocation
    var isReplace: Bool
}
