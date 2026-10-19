import Foundation
import Observation

/// Capture records, newest first, persisted as JSON. Records older than `retentionDays()` are
/// dropped on load and on add; their files on disk are left alone. `retentionDays` is a closure
/// so a changed setting applies at the next prune without recreating the store.
@Observable
final class HistoryStore {
    static let fileName = "history.json"

    private(set) var records: [CaptureRecord] = []

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let retentionDays: () -> Int
    @ObservationIgnored private let now: () -> Date

    init(fileURL: URL, retentionDays: @escaping () -> Int = { 30 }, now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.retentionDays = retentionDays
        self.now = now
    }

    /// `~/Library/Application Support/TidyShot/history.json` (inside the sandbox container).
    static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return support.appending(path: "TidyShot", directoryHint: .isDirectory).appending(path: fileName)
    }

    /// Reads the file. A missing file yields an empty list. A file that cannot be decoded is
    /// renamed to `history.json.corrupt-<unix seconds>` (so the next save cannot overwrite it)
    /// and the list starts empty. Records still marked `uploading` were interrupted by a quit or
    /// crash and become `failed` so they can be retried.
    func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            records = []
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loaded: [CaptureRecord]
        do {
            loaded = try decoder.decode([CaptureRecord].self, from: data)
        } catch {
            NSLog("History file could not be decoded, setting it aside: \(error)")
            setAsideCorruptFile()
            loaded = []
        }
        for index in loaded.indices where loaded[index].isUploading {
            loaded[index].uploadState = .failed(message: "Upload was interrupted.")
        }
        records = Self.pruned(loaded, retentionDays: retentionDays(), now: now())
        records.sort { $0.timestamp > $1.timestamp }
    }

    func add(_ record: CaptureRecord) {
        records.insert(record, at: 0)
        records = Self.pruned(records, retentionDays: retentionDays(), now: now())
        save()
    }

    func record(id: UUID) -> CaptureRecord? {
        records.first { $0.id == id }
    }

    /// Applies `change` to the record and writes the file.
    func update(id: UUID, _ change: (inout CaptureRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        save()
    }

    /// In-memory only; progress arrives often and is not worth a disk write each time. Ignored
    /// unless the record is still uploading, because a late progress callback can arrive after
    /// the upload has already finished.
    func setProgress(id: UUID, fraction: Double) {
        guard let index = records.firstIndex(where: { $0.id == id }), records[index].isUploading else { return }
        records[index].uploadState = .uploading(fraction: fraction)
    }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    var failedRecords: [CaptureRecord] {
        records.filter(\.isFailed)
    }

    static func pruned(_ records: [CaptureRecord], retentionDays: Int, now: Date) -> [CaptureRecord] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return records.filter { $0.timestamp >= cutoff }
    }

    /// Moves an undecodable history file out of the way, next to the original.
    private func setAsideCorruptFile() {
        let stamp = Int(now().timeIntervalSince1970)
        let target = fileURL.deletingLastPathComponent().appending(path: "\(fileURL.lastPathComponent).corrupt-\(stamp)")
        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
        } catch {
            NSLog("Could not set aside the history file: \(error.localizedDescription)")
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(records)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("History save failed: \(error.localizedDescription)")
        }
    }
}
