import Foundation

/// The `Drag` folder in the container's temporary directory: one folder per record, holding the
/// one file a Quick Access card hands out when it is dragged (spec 2.9). Never the user's save
/// folder: a save-folder file is copied in here, an upload-only capture's pending file is moved
/// in here after its upload, and a restored card's download is written here. Under the App
/// Sandbox the folder is `~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag`. Every method
/// touches only the file system, so stages run in detached tasks.
nonisolated struct DragFileStore: Sendable {
    static let directoryName = "Drag"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `Drag` in `temporaryDirectory` (`FileManager.default.temporaryDirectory`, the container's `tmp`).
    init(temporaryDirectory: URL) {
        self.init(directory: temporaryDirectory.appending(path: Self.directoryName, directoryHint: .isDirectory))
    }

    /// `Drag/<id>`.
    func folder(for id: UUID) -> URL {
        directory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// The file in `id`'s folder, or nil. A folder holds one file, except for a moment while two
    /// operations on it overlap; then the first by name.
    func stagedFile(id: UUID) -> URL? {
        Self.entries(in: folder(for: id)).min { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies `source` to `Drag/<id>/<name>` and returns it, replacing what the folder held.
    /// `FileManager.copyItem` clones on APFS when source and folder share a volume (`pending`
    /// always does; a save folder on the startup disk does), and copies the bytes otherwise.
    /// `scope` (the save folder) is held for the copy; nil for a file in the container. Staging
    /// the staged file as itself returns it. Throws, leaving the folder as it was, when `source`
    /// does not exist or cannot be read.
    @discardableResult
    func stage(id: UUID, name: String, from source: URL, scope: URL?) throws -> URL {
        let fileManager = FileManager.default
        let destination = folder(for: id).appending(path: name)
        let accessing = scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scope?.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if source.standardizedFileURL.path(percentEncoded: false) == destination.standardizedFileURL.path(percentEncoded: false) {
            return destination
        }
        return try place(destination) { try fileManager.copyItem(at: source, to: $0) }
    }

    /// Moves an upload-only capture's pending file to `Drag/<id>/<name>` (a rename: `pending` and
    /// `tmp` are both in the container) and returns it, replacing what the folder held. Throws,
    /// leaving the folder as it was, when `source` is gone.
    @discardableResult
    func adopt(id: UUID, name: String, moving source: URL) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try place(folder(for: id).appending(path: name)) { try fileManager.moveItem(at: source, to: $0) }
    }

    /// Writes downloaded bytes (a restored card's prefetch) as `Drag/<id>/<name>`, replacing what
    /// the folder held.
    @discardableResult
    func write(_ data: Data, id: UUID, name: String) throws -> URL {
        try place(folder(for: id).appending(path: name)) { try data.write(to: $0, options: .atomic) }
    }

    /// Removes `id`'s folder. One that is already gone is not an error; another failure is logged,
    /// and the launch sweep gets the folder later.
    func remove(id: UUID) {
        Self.removeLogged(folder(for: id))
    }

    /// Removes `Drag` and everything in it. Run at launch, before any card exists.
    func sweep() {
        Self.removeLogged(directory)
    }

    /// Puts a file at `destination` with `put`, then removes what the folder held before. The
    /// folder is listed before `put` runs, so two operations that overlap (a stage from a
    /// mouse-down and an adopt from a finished upload) never remove each other's new file.
    private func place(_ destination: URL, _ put: (URL) throws -> Void) throws -> URL {
        let fileManager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let earlier = Self.entries(in: folder).filter { $0.lastPathComponent != destination.lastPathComponent }
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try put(destination)
        for entry in earlier {
            try? fileManager.removeItem(at: entry)
        }
        return destination
    }

    private static func entries(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    private static func removeLogged(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            NSLog("Could not remove \(url.lastPathComponent) from the drag folder: \(error.localizedDescription)")
        }
    }
}
