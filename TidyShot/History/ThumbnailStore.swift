import Foundation

/// The `thumbnails` folder next to `history.json`: one PNG per capture, named by record id, or by
/// id and edit time once an edit was saved. Thumbnails belong to the app, so the store may delete
/// them; the user's screenshots never live here.
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

    /// `<UUID>.png` for the capture itself, `<UUID>-<milliseconds since 1970>.png` for an edit
    /// saved at `editedAt`. Each save gets a new name, so Recent Captures rows (which reload on the
    /// name) refresh, and the capture-time writer, which only writes `<UUID>.png`, never
    /// overwrites an edited thumbnail.
    func fileName(for id: UUID, editedAt: Date?) -> String {
        guard let editedAt else { return fileName(for: id) }
        let milliseconds = Int64((editedAt.timeIntervalSince1970 * 1000).rounded())
        return "\(id.uuidString)-\(milliseconds).png"
    }

    func url(forFileName name: String) -> URL {
        directory.appending(path: name)
    }

    /// Writes `png` for `id` (creating the folder) and returns the file name to store in the record.
    func write(_ png: Data, id: UUID) throws -> String {
        try write(png, fileName: fileName(for: id))
    }

    /// Writes `png` as `fileName` (creating the folder) and returns that name.
    func write(_ png: Data, fileName: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: url(forFileName: fileName), options: .atomic)
        return fileName
    }

    /// Removes the thumbnail; a missing file is not an error. A thumbnail is TidyShot's own
    /// cache, so a failure is not worth stopping a delete for.
    func remove(fileName: String) {
        try? FileManager.default.removeItem(at: url(forFileName: fileName))
    }
}
