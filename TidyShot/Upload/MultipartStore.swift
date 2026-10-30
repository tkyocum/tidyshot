import Foundation

/// The `multipart` folder next to `history.json`: one sidecar per record (`<id>.json`, the parts
/// sent so far) and, when the upload sends Clop's result, the kept copy (`<id>.<ext>`), moved out
/// of `tmp/Clop` so a Retry can resume from it after a relaunch. The record's own file is never
/// in here, so removing `<id>.*` never removes a recording.
nonisolated struct MultipartStore: Sendable {
    static let directoryName = "multipart"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `multipart` in the folder that holds `historyFileURL`.
    init(nextTo historyFileURL: URL) {
        self.init(directory: historyFileURL.deletingLastPathComponent().appending(path: Self.directoryName, directoryHint: .isDirectory))
    }

    /// `multipart/<id>.json`.
    func sidecarURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).json")
    }

    /// `multipart/<id>.<ext>`.
    func keptCopyURL(for id: UUID, ext: String) -> URL {
        directory.appending(path: "\(id.uuidString).\(ext)")
    }

    /// The sidecar for `uploadID`, or nil when it is missing, unreadable, or left by another
    /// upload id (which counts as missing).
    func readSidecar(id: UUID, uploadID: String) -> MultipartSidecar? {
        guard let data = try? Data(contentsOf: sidecarURL(for: id)),
              let sidecar = try? JSONDecoder().decode(MultipartSidecar.self, from: data),
              sidecar.uploadID == uploadID else {
            return nil
        }
        return sidecar
    }

    /// Writes the sidecar atomically (creating the folder), replacing the one there.
    func writeSidecar(_ sidecar: MultipartSidecar, id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(sidecar).write(to: sidecarURL(for: id), options: .atomic)
    }

    /// Moves Clop's result in as `<id>.<ext>` (creating the folder), replacing a file there, and
    /// returns it. Throws, leaving an earlier copy as it was, when `source` is gone.
    func keepClopCopy(_ source: URL, id: UUID, ext: String) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = keptCopyURL(for: id, ext: ext)
        if fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: source, to: url)
        return url
    }

    /// Removes the sidecar and the kept copy: every `<id>.*` file. One that is already gone is not
    /// an error; another failure is logged, and the launch sweep gets the file later.
    func remove(id: UUID) {
        for entry in entries() where Self.id(of: entry) == id {
            Self.removeLogged(entry)
        }
    }

    /// The ids whose files the launch sweep removes: those with no state (no record, or a record
    /// with no `multipart`), and those whose state started more than `MultipartPlan.stateLifetime`
    /// before `now`, which the bucket's lifecycle rule has aborted or will. `states` maps a record
    /// id to its state's `startedAt`.
    static func sweepRemovals(fileIDs: Set<UUID>, states: [UUID: Date], now: Date) -> Set<UUID> {
        fileIDs.filter { id in
            guard let startedAt = states[id] else { return true }
            return now.timeIntervalSince(startedAt) > MultipartPlan.stateLifetime
        }
    }

    /// Removes the files of `sweepRemovals`. Run at launch, after the history loads. It touches no
    /// record and no network: the record's `multipart` stays, so Delete still knows the key. A file
    /// not named by an id is left alone.
    func sweep(states: [UUID: Date], now: Date) {
        let files = entries()
        let removals = Self.sweepRemovals(fileIDs: Set(files.compactMap(Self.id(of:))), states: states, now: now)
        for file in files {
            if let id = Self.id(of: file), removals.contains(id) {
                Self.removeLogged(file)
            }
        }
    }

    /// The record id a file is named by: the name up to its first dot.
    private static func id(of file: URL) -> UUID? {
        let name = file.lastPathComponent
        return UUID(uuidString: String(name.prefix { $0 != "." }))
    }

    private func entries() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                      options: .skipsHiddenFiles)) ?? []
    }

    private static func removeLogged(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            NSLog("%@", "Could not remove \(url.lastPathComponent) from the multipart folder: \(error.localizedDescription)")
        }
    }
}
