import Foundation

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

    init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false,
         thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?,
         uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, pendingObjectKey: String? = nil) {
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, fileURL, fileIsTemporary, thumbnailFileName, pixelWidth, pixelHeight, appName, uploadState
        case objectLocation, pendingObjectKey
    }

    /// Phase 2 history files have no `fileIsTemporary`, `thumbnailFileName`, `objectLocation` or
    /// `pendingObjectKey`, and always have a `fileURL`; they decode with the defaults. Encoding
    /// is synthesised.
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

    var hasLocalFile: Bool { fileURL != nil }

    /// An upload-only capture that has not been uploaded: its PNG in `pending` is the only copy,
    /// so retention never prunes it.
    var isPendingOnly: Bool { fileIsTemporary && fileURL != nil && uploadedKey == nil }

    var isFailed: Bool {
        if case .failed = uploadState { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = uploadState { return true }
        return false
    }
}
