import Foundation

/// The `pending` folder next to `history.json`. Upload-only captures are written here instead of
/// the user's save folder (no folder prompt, no security scope) and deleted once uploaded; a
/// failed upload keeps its file here until the retry succeeds or the record is deleted.
nonisolated struct PendingFileStore: Sendable {
    static let directoryName = "pending"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `pending` in the folder that holds `historyFileURL`.
    init(nextTo historyFileURL: URL) {
        self.init(directory: historyFileURL.deletingLastPathComponent().appending(path: Self.directoryName, directoryHint: .isDirectory))
    }

    /// Writes `data` as `<id>.<ext>` (creating the folder) and returns the file URL.
    func write(_ data: Data, id: UUID, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(id.uuidString).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Moves `source` in as `<id>.<ext>` (creating the folder) and returns the file URL. A recording
    /// is renamed in from the container's `tmp`, never read or copied.
    func moveIn(_ source: URL, id: UUID, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(id.uuidString).\(ext)")
        try FileManager.default.moveItem(at: source, to: url)
        return url
    }

    /// Removes the file. A file that is already gone is not an error; any other failure throws,
    /// because this file may be the capture's only copy and Delete must not drop its record
    /// while the file stays behind.
    func remove(_ url: URL) throws {
        try FileManager.default.removeItemIfPresent(at: url)
    }

    /// The folder's files, hidden ones skipped; nothing when the folder is missing. The launch step lists
    /// once, before any task starts (harness design 4.2).
    func list() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles)) ?? []
    }
}
