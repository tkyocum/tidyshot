import Foundation

/// Where the annotation editor gets a capture's pixels, decided before anything is read.
/// `AppCoordinator.openEditor(recordID:)` acts on it, and `RecentCaptureFormatting.canAnnotate`
/// disables a row's Annotate button when it is `.unavailable`.
nonisolated enum EditorInput {
    enum Source: Equatable, Sendable {
        /// The capture just taken, still in memory (`AppCoordinator.latestCapture`).
        case retained
        /// An upload-only capture's PNG in the container's `pending` folder.
        case pendingFile(URL)
        /// A PNG in the current save folder, read under the folder's security scope.
        case saveFolderFile(URL)
        /// The uploaded object, fetched with a signed GET from where it went.
        case download(key: String, location: ObjectLocation)
        /// Nothing the editor can load. The reason is the body of the "Could not open the capture"
        /// notification.
        case unavailable(String)
    }

    static let neverUploadedText = "This capture has no local file and was never uploaded."
    static let unknownLocationText = "This capture has no local file, and TidyShot does not know where its upload went."
    static let outsideSaveFolderText = "The file is not in the current save folder, so TidyShot cannot read it."
    static let videoText = "Videos cannot be annotated."

    /// A video first: it is `.unavailable` whatever there is to read, a safety net behind the
    /// cards and rows that leave Annotate out for it. Then the order matches what `imageData(of:)`
    /// would do, so the editor opens from the same copy Copy Image uses:
    /// 1. The retained image, when `retainedID` is this record's.
    /// 2. A pending file. It holds the newest pixels, also after a failed replace whose object still
    ///    shows the original.
    /// 3. A file in `saveFolder`. A file outside it, or with no folder, cannot be read under the
    ///    sandbox, so it falls through.
    /// 4. The uploaded object, when its location is known. `imageData(of:)`, which loads steps 2 to
    ///    4, reads the record's drag copy (`DragFileStore`) first when no local file can be read, so
    ///    a `.download` opens from that copy while it exists (an upload-only capture whose card
    ///    still shows, or a restored card's download).
    /// 5. Otherwise `.unavailable`, with the reason.
    ///
    /// Steps 2 to 5 are `fileSource(for:saveFolder:)`.
    static func source(for record: CaptureRecord, retainedID: UUID?, saveFolder: URL?) -> Source {
        if record.isTimeBased { return .unavailable(videoText) }
        if record.id == retainedID { return .retained }
        return fileSource(for: record, saveFolder: saveFolder)
    }

    /// Steps 2 to 5 of `source(for:retainedID:saveFolder:)`, with no video check: a pending file, a
    /// file in `saveFolder`, the uploaded object, otherwise `.unavailable`. Never `.retained`, and
    /// `.saveFolderFile` only with a `saveFolder`. Trim's source (`RecordingTrim.source`) is this,
    /// so the two keep one order and one set of texts.
    static func fileSource(for record: CaptureRecord, saveFolder: URL?) -> Source {
        if let fileURL = record.fileURL {
            if record.fileIsTemporary { return .pendingFile(fileURL) }
            if let saveFolder, SaveLocation.contains(fileURL, inFolder: saveFolder) { return .saveFolderFile(fileURL) }
        }
        if let key = record.uploadedKey, let location = record.objectLocation {
            return .download(key: key, location: location)
        }
        if record.fileURL != nil { return .unavailable(outsideSaveFolderText) }
        return .unavailable(record.uploadedKey == nil ? neverUploadedText : unknownLocationText)
    }
}
