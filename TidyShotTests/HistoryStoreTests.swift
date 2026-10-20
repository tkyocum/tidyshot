import Foundation
import Testing
@testable import TidyShot

struct HistoryStoreTests {
    let now = Date(timeIntervalSince1970: 1_792_411_200)
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func store(retentionDays: Int = 30) -> HistoryStore {
        HistoryStore(fileURL: dir.appending(path: "history.json"), retentionDays: { retentionDays }, now: { now })
    }

    func record(age: TimeInterval = 0, state: CaptureRecord.UploadState = .none) -> CaptureRecord {
        CaptureRecord(timestamp: now.addingTimeInterval(-age), fileURL: dir.appending(path: "shot.png"),
                      pixelWidth: 200, pixelHeight: 100, appName: "Safari", uploadState: state)
    }

    @Test func addPersistsAndReloadsNewestFirst() throws {
        let first = store()
        let older = record(age: 60)
        let newer = record(age: 0, state: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"))
        first.add(older)
        first.add(newer)

        let second = store()
        second.load()
        #expect(second.records == [newer, older])
        #expect(second.record(id: newer.id)?.uploadedURL?.absoluteString == "https://snap.tky.io/a.png")
    }

    @Test func updateChangesStateAndPersists() {
        let first = store()
        let item = record()
        first.add(item)
        first.update(id: item.id) { $0.uploadState = .failed(message: "boom") }

        let second = store()
        second.load()
        #expect(second.records.first?.uploadState == .failed(message: "boom"))
        #expect(second.failedRecords.map(\.id) == [item.id])
    }

    @Test func uploadingRecordsBecomeFailedOnLoadAndPersist() {
        let first = store()
        let item = record(state: .uploading(fraction: 0.4))
        first.add(item)

        let second = store()
        second.load()
        #expect(second.record(id: item.id)?.uploadState == .failed(message: "Upload was interrupted."))

        let third = store()
        third.load()
        #expect(third.record(id: item.id)?.uploadState == .failed(message: "Upload was interrupted."))
    }

    @Test func setProgressDoesNotWriteToDisk() throws {
        let first = store()
        let item = record(state: .uploading(fraction: 0))
        first.add(item)
        let file = dir.appending(path: "history.json")
        let before = try Data(contentsOf: file)
        #expect(first.setProgress(id: item.id, fraction: 0.5))
        #expect(first.record(id: item.id)?.uploadState == .uploading(fraction: 0.5))
        #expect(try Data(contentsOf: file) == before)
    }

    @Test func lateProgressDoesNotReopenAFinishedUpload() {
        let first = store()
        let item = record(state: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"))
        first.add(item)
        #expect(first.setProgress(id: item.id, fraction: 0.9) == false)
        #expect(first.record(id: item.id)?.uploadedURL != nil)
    }

    @Test func prunesRecordsOlderThanRetention() {
        let first = store(retentionDays: 30)
        first.add(record(age: 31 * 86_400))
        first.add(record(age: 29 * 86_400))
        #expect(first.records.count == 1)

        let second = store(retentionDays: 7)
        second.load()
        #expect(second.records.isEmpty)
    }

    @Test func didPruneReportsDroppedRecordsOnAddAndLoad() {
        let first = store(retentionDays: 30)
        var pruned: [[UUID]] = []
        first.didPrune = { pruned.append($0.map(\.id)) }
        let old = record(age: 31 * 86_400)
        first.add(old)
        #expect(pruned == [[old.id]])
        first.add(record(age: 29 * 86_400))
        #expect(pruned == [[old.id]])

        let second = store(retentionDays: 7)
        var prunedOnLoad: [UUID] = []
        second.didPrune = { prunedOnLoad = $0.map(\.id) }
        second.load()
        #expect(prunedOnLoad.count == 1)
        #expect(second.records.isEmpty)
    }

    /// An upload-only capture that was never uploaded has its only copy in `pending/`; retention
    /// must not drop the record (and with it the file) however old it is.
    @Test func pruningKeepsUploadOnlyCapturesThatWereNeverUploaded() {
        let history = store(retentionDays: 7)
        var pruned: [UUID] = []
        history.didPrune = { pruned += $0.map(\.id) }
        let pendingOnly = CaptureRecord(timestamp: now.addingTimeInterval(-30 * 86_400), fileURL: dir.appending(path: "pending/a.png"),
                                        fileIsTemporary: true, pixelWidth: 1, pixelHeight: 1, appName: nil,
                                        uploadState: .failed(message: "offline"))
        let old = record(age: 30 * 86_400)
        history.add(pendingOnly)
        history.add(old)

        #expect(history.records.map(\.id) == [pendingOnly.id])
        #expect(pruned == [old.id])
        let reloaded = store(retentionDays: 7)
        reloaded.load()
        #expect(reloaded.records.map(\.id) == [pendingOnly.id])
    }

    /// A record whose upload is still running must survive retention, or its `.uploaded` event
    /// would find no record and the object would be left in the bucket with nothing pointing at it.
    @Test func pruningKeepsUploadingRecords() {
        let history = store(retentionDays: 7)
        var pruned: [UUID] = []
        history.didPrune = { pruned += $0.map(\.id) }
        let uploading = record(age: 30 * 86_400, state: .uploading(fraction: 0.5))
        let old = record(age: 30 * 86_400)
        history.add(uploading)
        history.add(old)

        #expect(history.records.map(\.id) == [uploading.id])
        #expect(pruned == [old.id])
    }

    @Test func missingFileLoadsEmpty() {
        let fresh = store()
        fresh.load()
        #expect(fresh.records.isEmpty)
    }

    @Test func corruptFileIsSetAsideNotOverwritten() throws {
        let file = dir.appending(path: "history.json")
        let garbage = Data("not json".utf8)
        try garbage.write(to: file)

        let corrupt = store()
        corrupt.load()
        #expect(corrupt.records.isEmpty)

        // `now` is 1_792_411_200, so the set-aside name is deterministic.
        let setAside = dir.appending(path: "history.json.corrupt-1792411200")
        #expect(try Data(contentsOf: setAside) == garbage)

        corrupt.add(record())
        #expect(try Data(contentsOf: setAside) == garbage)
        #expect(FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func corruptFileSetAsideSurvivesNameCollision() throws {
        let existing = dir.appending(path: "history.json.corrupt-1792411200")
        let earlier = Data("earlier corrupt".utf8)
        try earlier.write(to: existing)
        let garbage = Data("not json".utf8)
        try garbage.write(to: dir.appending(path: "history.json"))

        store().load()

        #expect(try Data(contentsOf: existing) == earlier)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false))
        let others = names.filter { $0.hasPrefix("history.json.corrupt-1792411200-") }
        #expect(others.count == 1)
        if let name = others.first {
            #expect(try Data(contentsOf: dir.appending(path: name)) == garbage)
        }
    }

    @Test func removeDeletesRecord() {
        let first = store()
        let item = record()
        first.add(item)
        first.remove(id: item.id)
        #expect(first.records.isEmpty)
    }
}
