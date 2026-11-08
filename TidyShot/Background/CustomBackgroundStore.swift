import CoreGraphics
import Foundation
import ImageIO
import Observation

/// The one custom background image (spec 2.11), kept as `custom.png` in the container's
/// `Application Support/TidyShot/Backgrounds`. A new image replaces the old one. Every method
/// touches only the file system, so callers run them off the main actor.
nonisolated struct CustomBackgroundStore: Sendable {
    enum StoreError: Error, Equatable {
        /// The chosen file could not be decoded as an image.
        case notAnImage
    }

    /// The stored image's long side at most, in pixels.
    static let maximumSide = 6_000
    static let fileName = "custom.png"
    static let shared = CustomBackgroundStore(directory: defaultDirectory())

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    var fileURL: URL { directory.appending(path: Self.fileName) }

    var hasImage: Bool {
        FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

    /// Decodes the file at `url`, scales it down to `maximumSide` on its long side, and writes it
    /// as PNG over the previous image. Throws `StoreError.notAnImage`, leaving the stored image as
    /// it was, when the file cannot be decoded. `url` comes from the open panel, whose
    /// user-selected access covers the read.
    func store(contentsOf url: URL) throws {
        let png = try url.withSecurityScope { () throws -> Data in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) > 0
            else { throw StoreError.notAnImage }
            // ImageIO never upscales, and applies the EXIF orientation.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.maximumSide,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { throw StoreError.notAnImage }
            return try ImageEncoder.pngData(from: image, scale: 1)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: fileURL, options: .atomic)
    }

    /// The stored image, or nil when there is none or it does not decode.
    func image() -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// A small copy of the stored image for the style editor's swatch, or nil.
    func preview(maxSide: Int) -> CGImage? {
        // `scaled`, not `thumbnail`, which cuts a tall image to its top.
        guard let image = image() else { return nil }
        return ThumbnailMaker.scaled(image, maxSide: maxSide)
    }

    /// `Application Support/TidyShot/Backgrounds` (inside the sandbox container).
    private static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appending(path: "TidyShot/Backgrounds", directoryHint: .isDirectory)
    }
}

/// Counts the custom images stored this session, so what shows the stored image (the style
/// editor's swatch, the editor's preview) reads it again after `Choose Image…` replaces it, even
/// when the style, already `.customImage`, does not change.
@Observable
final class CustomBackgroundRevision {
    static let shared = CustomBackgroundRevision()

    private(set) var count = 0

    /// Called on the main actor after a successful `CustomBackgroundStore.store(contentsOf:)`.
    func bump() {
        count += 1
    }
}
