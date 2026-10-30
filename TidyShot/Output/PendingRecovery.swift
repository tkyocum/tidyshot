import Foundation

/// The `pending/` launch step's rule (harness design 4.2): which listed files are orphans to adopt. A file
/// is one when its name is `<UUID>.<png|mp4|gif>` and that UUID is no record's id; any other name is left
/// alone. By id, not by `fileURL`, so a trim's write (the record exists, its `fileURL` not yet set) and an
/// edit kept under its own record are never taken, and a record's spelling of its path never matters.
nonisolated enum PendingRecovery {
    /// An orphan: its file, the record id its name gives, and the kind its extension gives.
    struct Found: Equatable, Sendable {
        var url: URL
        var id: UUID
        var kind: MediaKind
    }

    /// The orphans among `listed`, in name order.
    static func orphans(listed: [URL], recordIDs: Set<UUID>) -> [Found] {
        listed.compactMap { url -> Found? in
            guard !url.lastPathComponent.hasPrefix("."),
                  let kind = [MediaKind.image, .video, .gif].first(where: { $0.fileExtension == url.pathExtension }),
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !recordIDs.contains(id) else { return nil }
            return Found(url: url, id: id, kind: kind)
        }
        .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
}
