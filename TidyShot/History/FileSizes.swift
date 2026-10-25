import Foundation

/// File sizes for Recent Captures (spec 2.13), from each file's `fileSizeKey` resource value. A
/// file is never read. Also the launch backfill: records saved before 2.13 have no `byteCount`, and
/// those with a local file TidyShot can reach get it in one pass off the main actor.
nonisolated enum FileSizes {
    /// A record to measure: its file, and the folder whose security scope reaching it needs (the
    /// save folder; nil for a file in `pending/`).
    struct BackfillItem: Equatable, Sendable {
        let id: UUID
        let fileURL: URL
        let scope: URL?
    }

    /// The size found for a record, with the file it was read from.
    struct Measured: Equatable, Sendable {
        let fileURL: URL
        let byteCount: Int
    }

    /// The size of the file at `fileURL`, holding `scope`'s security scope when one is given. Nil
    /// when the file is gone or its size cannot be read. Any size cached on the URL is dropped
    /// first, so a file rewritten in place is measured again.
    static func byteCount(of fileURL: URL, scope: URL? = nil) -> Int? {
        let accessing = scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scope?.stopAccessingSecurityScopedResource() } }
        var url = fileURL
        url.removeAllCachedResourceValues()
        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    /// The records with no `byteCount` and a local file TidyShot can reach, in order: a file in
    /// `pendingFolder` directly, and one in `saveFolder` under that folder's scope. A file anywhere
    /// else, such as an earlier save folder, is left out: the sandbox would refuse it.
    static func backfillItems(for records: [CaptureRecord], pendingFolder: URL, saveFolder: URL?) -> [BackfillItem] {
        records.compactMap { record in
            guard record.byteCount == nil, let fileURL = record.fileURL else { return nil }
            if SaveLocation.contains(fileURL, inFolder: pendingFolder) {
                return BackfillItem(id: record.id, fileURL: fileURL, scope: nil)
            }
            if let saveFolder, SaveLocation.contains(fileURL, inFolder: saveFolder) {
                return BackfillItem(id: record.id, fileURL: fileURL, scope: saveFolder)
            }
            return nil
        }
    }

    /// Each item's size, by record id, in one pass that holds each scope once for all of its files.
    /// A file that is gone, or whose size cannot be read, is left out. Runs in a detached task.
    static func measure(_ items: [BackfillItem]) -> [UUID: Measured] {
        let scopes = Set(items.compactMap(\.scope)).filter { $0.startAccessingSecurityScopedResource() }
        defer {
            for scope in scopes {
                scope.stopAccessingSecurityScopedResource()
            }
        }
        var sizes: [UUID: Measured] = [:]
        for item in items {
            if let byteCount = byteCount(of: item.fileURL) {
                sizes[item.id] = Measured(fileURL: item.fileURL, byteCount: byteCount)
            }
        }
        return sizes
    }

    /// Sets the record's size from `measured` while it still has none and still points at the file
    /// that was measured: a save, an edit or an upload during the pass set the size it should keep.
    static func fill(_ record: inout CaptureRecord, from measured: [UUID: Measured]) {
        guard record.byteCount == nil, let size = measured[record.id], size.fileURL == record.fileURL else { return }
        record.byteCount = size.byteCount
    }
}
