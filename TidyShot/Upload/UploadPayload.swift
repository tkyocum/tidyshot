import Foundation

/// What an upload sends. A screenshot's PNG is in memory; a recording streams from its file and
/// is never loaded.
nonisolated enum UploadPayload: Sendable, Equatable {
    case data(Data)
    /// `scope` is the folder whose security scope reading the file needs (the save folder), nil
    /// for a file in the container (`pending/`, `tmp/Recording`, `tmp/Clop`).
    case file(URL, scope: URL?)

    /// The save folder for a file inside it, nil otherwise: the rule `prepareDragFile` uses. A
    /// temporary file is in the container and needs no scope.
    static func scope(for fileURL: URL, isTemporary: Bool, saveFolder: URL?) -> URL? {
        guard !isTemporary, let saveFolder, SaveLocation.contains(fileURL, inFolder: saveFolder) else { return nil }
        return saveFolder
    }

    /// A recording's file, after two checks: a save-folder file is inside the current folder
    /// (otherwise there is no scope to read it with), and `fileExists` finds it, given the scope
    /// to hold while it looks. Throws `UploadError.fileUnreadable` when either fails.
    static func video(for record: CaptureRecord, saveFolder: URL?,
                      fileExists: (URL, URL?) -> Bool) throws -> UploadPayload {
        guard let fileURL = record.fileURL else { throw UploadError.fileUnreadable("no local file") }
        let scope = scope(for: fileURL, isTemporary: record.fileIsTemporary, saveFolder: saveFolder)
        if !record.fileIsTemporary, scope == nil {
            throw UploadError.fileUnreadable(fileURL.lastPathComponent)
        }
        guard fileExists(fileURL, scope) else { throw UploadError.fileUnreadable(fileURL.lastPathComponent) }
        return .file(fileURL, scope: scope)
    }
}
