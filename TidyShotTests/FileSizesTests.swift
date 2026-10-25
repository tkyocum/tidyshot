import Foundation
import Testing
@testable import TidyShot

/// The launch backfill of `CaptureRecord.byteCount` (spec 2.13, Old records), over a temporary
/// folder that stands in for `pending/` and the save folder.
struct FileSizesTests {
    let dir: URL
    let pending: URL
    let saveFolder: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        pending = dir.appending(path: "pending", directoryHint: .isDirectory)
        saveFolder = dir.appending(path: "Screenshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
    }

    /// Writes `count` bytes at `url` and returns it.
    @discardableResult
    func file(_ url: URL, bytes count: Int) throws -> URL {
        try Data(repeating: 7, count: count).write(to: url)
        return url
    }

    func record(_ fileURL: URL?, temporary: Bool = false, byteCount: Int? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: nil,
                      byteCount: byteCount)
    }

    @Test func byteCountIsTheFilesSizeAndNilWhenItIsGone() throws {
        let png = try file(saveFolder.appending(path: "Shot.png"), bytes: 5_120)
        #expect(FileSizes.byteCount(of: png) == 5_120)
        #expect(FileSizes.byteCount(of: png, scope: saveFolder) == 5_120)
        #expect(FileSizes.byteCount(of: saveFolder.appending(path: "Gone.png")) == nil)

        // Rewritten in place: the size is read again, not taken from an earlier read.
        try file(png, bytes: 2_048)
        #expect(FileSizes.byteCount(of: png) == 2_048)
    }

    /// Only records with no size and a file TidyShot can reach: in `pending/` directly, or in the
    /// save folder under its scope. A file anywhere else (an earlier save folder) is left out.
    @Test func backfillItemsAreRecordsWithNoSizeAndAReachableFile() {
        let inPending = record(pending.appending(path: "\(UUID().uuidString).png"), temporary: true)
        let inSaveFolder = record(saveFolder.appending(path: "Shot.png"))
        let nested = record(saveFolder.appending(path: "2026/Recording.mp4"))
        let sized = record(saveFolder.appending(path: "Sized.png"), byteCount: 42)
        let noFile = record(nil)
        let elsewhere = record(dir.appending(path: "Old Folder/Shot.png"))

        let items = FileSizes.backfillItems(for: [inPending, inSaveFolder, nested, sized, noFile, elsewhere],
                                            pendingFolder: pending, saveFolder: saveFolder)
        #expect(items == [
            FileSizes.BackfillItem(id: inPending.id, fileURL: inPending.fileURL!, scope: nil),
            FileSizes.BackfillItem(id: inSaveFolder.id, fileURL: inSaveFolder.fileURL!, scope: saveFolder),
            FileSizes.BackfillItem(id: nested.id, fileURL: nested.fileURL!, scope: saveFolder),
        ])

        // With no save folder set, only `pending/` can be reached.
        #expect(FileSizes.backfillItems(for: [inPending, inSaveFolder], pendingFolder: pending, saveFolder: nil)
                == [FileSizes.BackfillItem(id: inPending.id, fileURL: inPending.fileURL!, scope: nil)])
    }

    /// Sizes come from the files' attributes; a missing file is skipped.
    @Test func measureReadsSizesAndSkipsMissingFiles() throws {
        let a = FileSizes.BackfillItem(id: UUID(), fileURL: try file(pending.appending(path: "a.png"), bytes: 999), scope: nil)
        let b = FileSizes.BackfillItem(id: UUID(), fileURL: try file(saveFolder.appending(path: "b.mp4"), bytes: 123_456),
                                       scope: saveFolder)
        let gone = FileSizes.BackfillItem(id: UUID(), fileURL: saveFolder.appending(path: "gone.png"), scope: saveFolder)

        let measured = FileSizes.measure([a, b, gone])
        #expect(measured == [a.id: FileSizes.Measured(fileURL: a.fileURL, byteCount: 999),
                             b.id: FileSizes.Measured(fileURL: b.fileURL, byteCount: 123_456)])
        #expect(FileSizes.measure([]).isEmpty)
    }

    /// The pass runs off the main actor, so a record may have changed meanwhile: a size set since
    /// (a save, an edit or an upload) wins, and a record that now points at another file keeps none.
    @Test func fillSetsTheSizeOnlyWhereItIsStillMissing() {
        let shot = saveFolder.appending(path: "Shot.png")
        var waiting = record(shot)
        var sizedMeanwhile = record(shot, byteCount: 77)
        var moved = record(pending.appending(path: "moved.png"), temporary: true)
        var unmeasured = record(shot)
        let measured = [waiting.id: FileSizes.Measured(fileURL: shot, byteCount: 5_120),
                        sizedMeanwhile.id: FileSizes.Measured(fileURL: shot, byteCount: 5_120),
                        moved.id: FileSizes.Measured(fileURL: shot, byteCount: 5_120)]

        FileSizes.fill(&waiting, from: measured)
        FileSizes.fill(&sizedMeanwhile, from: measured)
        FileSizes.fill(&moved, from: measured)
        FileSizes.fill(&unmeasured, from: measured)
        #expect(waiting.byteCount == 5_120)
        #expect(sizedMeanwhile.byteCount == 77)
        #expect(moved.byteCount == nil)
        #expect(unmeasured.byteCount == nil)
    }

    /// The backfill writes `history.json` once, and only when a record changed.
    @Test func updateAllChangesEveryRecordAndPersists() throws {
        let historyURL = dir.appending(path: "history.json")
        let store = HistoryStore(fileURL: historyURL, retentionDays: { 3650 })
        let first = record(saveFolder.appending(path: "a.png"))
        let second = record(saveFolder.appending(path: "b.png"))
        store.add(first)
        store.add(second)

        store.updateAll { $0.byteCount = $0.id == first.id ? 10 : 20 }
        let reloaded = HistoryStore(fileURL: historyURL, retentionDays: { 3650 })
        reloaded.load()
        #expect(reloaded.record(id: first.id)?.byteCount == 10)
        #expect(reloaded.record(id: second.id)?.byteCount == 20)

        // Nothing changes: the file is not written again.
        let written = try FileManager.default.attributesOfItem(atPath: historyURL.path(percentEncoded: false))[.modificationDate] as? Date
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)],
                                              ofItemAtPath: historyURL.path(percentEncoded: false))
        store.updateAll { _ in }
        let after = try FileManager.default.attributesOfItem(atPath: historyURL.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(written != nil)
        #expect(after == Date(timeIntervalSince1970: 0))
    }
}
