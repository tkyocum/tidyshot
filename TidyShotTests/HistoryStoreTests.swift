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

    @Test func setProgressDoesNotWriteToDisk() {
        let first = store()
        let item = record(state: .uploading(fraction: 0))
        first.add(item)
        first.setProgress(id: item.id, fraction: 0.5)
        #expect(first.record(id: item.id)?.uploadState == .uploading(fraction: 0.5))

        let second = store()
        second.load()
        #expect(second.records.first?.uploadState == .failed(message: "Upload was interrupted."))
    }

    @Test func lateProgressDoesNotReopenAFinishedUpload() {
        let first = store()
        let item = record(state: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"))
        first.add(item)
        first.setProgress(id: item.id, fraction: 0.9)
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

    @Test func removeDeletesRecord() {
        let first = store()
        let item = record()
        first.add(item)
        first.remove(id: item.id)
        #expect(first.records.isEmpty)
    }
}
