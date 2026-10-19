import Foundation

/// One capture: where its PNG is, how big it is, and how its upload went.
nonisolated struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
    enum UploadState: Codable, Equatable, Sendable {
        case none
        case uploading(fraction: Double)
        case uploaded(url: URL, key: String)
        case failed(message: String)
    }

    let id: UUID
    let timestamp: Date
    var fileURL: URL
    var pixelWidth: Int
    var pixelHeight: Int
    var appName: String?
    var uploadState: UploadState

    init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL, pixelWidth: Int, pixelHeight: Int,
         appName: String?, uploadState: UploadState = .none) {
        self.id = id
        self.timestamp = timestamp
        self.fileURL = fileURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.appName = appName
        self.uploadState = uploadState
    }

    var uploadedURL: URL? {
        if case .uploaded(let url, _) = uploadState { return url }
        return nil
    }

    var isFailed: Bool {
        if case .failed = uploadState { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = uploadState { return true }
        return false
    }
}
