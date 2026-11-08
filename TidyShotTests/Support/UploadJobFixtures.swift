import Foundation
@testable import TidyShot

/// Jobs for bytes in memory. The app builds every job from a `UploadPayload`; the suites hand
/// `Data` straight in.
extension UploadJob {
    /// A template job for bytes in memory.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, naming: TemplateContext = TemplateContext()) {
        self.init(id: id, payload: .data(data), contentType: contentType, fileExtension: fileExtension, naming: naming)
    }

    /// A fixed-key job for bytes in memory.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, fixedKey: String,
         cacheControl: String? = "no-cache") {
        self.init(id: id, payload: .data(data), contentType: contentType, fileExtension: fileExtension,
                  fixedKey: fixedKey, cacheControl: cacheControl)
    }
}
