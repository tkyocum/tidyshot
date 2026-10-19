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
    @ObservationIgnored private var saveDisabled = false
    @ObservationIgnored private var loggedSaveDisabled = false

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

    /// Reads the file. A missing file yields an empty list. A file that cannot be read or decoded
    /// is renamed to `history.json.corrupt-<unix seconds>` (so the next save cannot overwrite it)
    /// and the list starts empty. Records still marked `uploading` were interrupted by a quit or
    /// crash and become `failed` so they can be retried; that rewrite is saved once.
    func load() {
        var loaded: [CaptureRecord] = []
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = Self.dateDecodingStrategy
            loaded = try decoder.decode([CaptureRecord].self, from: data)
        } catch where Self.isFileMissing(error) {
            records = []
            return
        } catch {
            NSLog("History file could not be read or decoded, setting it aside: \(error)")
            setAsideCorruptFile()
            loaded = []
        }
        var interrupted = false
        for index in loaded.indices where loaded[index].isUploading {
            loaded[index].uploadState = .failed(message: "Upload was interrupted.")
            interrupted = true
        }
        records = Self.sortedNewestFirst(Self.pruned(loaded, retentionDays: retentionDays(), now: now()))
        if interrupted { save() }
    }

    func add(_ record: CaptureRecord) {
        records.insert(record, at: 0)
        records = Self.sortedNewestFirst(Self.pruned(records, retentionDays: retentionDays(), now: now()))
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

    /// Newest first; equal timestamps keep their current relative order.
    private static func sortedNewestFirst(_ records: [CaptureRecord]) -> [CaptureRecord] {
        records.enumerated().sorted { lhs, rhs in
            lhs.element.timestamp != rhs.element.timestamp
                ? lhs.element.timestamp > rhs.element.timestamp
                : lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func isFileMissing(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == CocoaError.fileReadNoSuchFile.rawValue || ns.code == CocoaError.fileNoSuchFile.rawValue {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOENT) {
            return true
        }
        return false
    }

    private static let dateEncodingStrategy: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var container = encoder.singleValueContainer()
        try container.encode(formatter.string(from: date))
    }

    private static let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let text = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO 8601 date: \(text)"))
    }

    /// Moves an unusable history file out of the way, next to the original. If the move fails,
    /// saving is disabled so the corrupt file is never overwritten.
    private func setAsideCorruptFile() {
        let stamp = Int(now().timeIntervalSince1970)
        let directory = fileURL.deletingLastPathComponent()
        let name = "\(fileURL.lastPathComponent).corrupt-\(stamp)"
        var target = directory.appending(path: name)
        if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            let suffix = UUID().uuidString.prefix(8).lowercased()
            target = directory.appending(path: "\(name)-\(suffix)")
        }
        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
        } catch {
            NSLog("Could not set aside the history file: \(error.localizedDescription)")
            saveDisabled = true
        }
    }

    private func save() {
        if saveDisabled {
            if !loggedSaveDisabled {
                loggedSaveDisabled = true
                NSLog("History saving is disabled because the corrupt history file could not be set aside.")
            }
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = Self.dateEncodingStrategy
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
