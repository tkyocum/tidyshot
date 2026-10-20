import Foundation

/// The `thumbnails` folder next to `history.json`: one PNG per capture, named by record id.
/// Thumbnails belong to the app, so the store may delete them; the user's screenshots never
/// live here.
nonisolated struct ThumbnailStore: Sendable {
    static let directoryName = "thumbnails"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `thumbnails` in the folder that holds `historyFileURL`.
    init(nextTo historyFileURL: URL) {
        self.init(directory: historyFileURL.deletingLastPathComponent().appending(path: Self.directoryName, directoryHint: .isDirectory))
    }

    func fileName(for id: UUID) -> String {
        id.uuidString + ".png"
    }

    func url(forFileName name: String) -> URL {
        directory.appending(path: name)
    }

    /// Writes `png` for `id` (creating the folder) and returns the file name to store in the record.
    func write(_ png: Data, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = fileName(for: id)
        try png.write(to: url(forFileName: name), options: .atomic)
        return name
    }

    /// Removes the thumbnail; a missing file is not an error. A thumbnail is TidyShot's own
    /// cache, so a failure is not worth stopping a delete for.
    func remove(fileName: String) {
        try? FileManager.default.removeItem(at: url(forFileName: fileName))
    }
}
