import Foundation
import Testing
@testable import TidyShot

struct CaptureRecordTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func store() -> HistoryStore {
        HistoryStore(fileURL: dir.appending(path: "history.json"), retentionDays: { 3650 },
                     now: { Date(timeIntervalSince1970: 1_792_411_200) })
    }

    /// A record exactly as Phase 2 wrote it: no thumbnail, no temporary flag, no counter.
    let phase2JSON = """
    [
      {
        "appName" : "Safari",
        "fileURL" : "file:///Users/tim/Desktop/Screenshot%202026-10-19%20at%2011.56.03.png",
        "id" : "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B",
        "pixelHeight" : 100,
        "pixelWidth" : 200,
        "timestamp" : "2026-10-19T16:56:03.000Z",
        "uploadState" : {
          "uploaded" : {
            "key" : "aSIS7x.png",
            "url" : "https://snap.tky.io/aSIS7x.png"
          }
        }
      }
    ]
    """

    @Test func phase2HistoryFileDecodesWithDefaults() throws {
        try Data(phase2JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!))
        #expect(record.fileURL?.lastPathComponent == "Screenshot 2026-10-19 at 11.56.03.png")
        #expect(record.hasLocalFile)
        #expect(record.fileIsTemporary == false)
        #expect(record.thumbnailFileName == nil)
        #expect(record.objectLocation == nil)
        #expect(record.pendingObjectKey == nil)
        #expect(!record.isPendingOnly)
        #expect(record.appName == "Safari")
        #expect(record.uploadedKey == "aSIS7x.png")
        #expect(record.uploadedURL?.absoluteString == "https://snap.tky.io/aSIS7x.png")
    }

    /// Timestamps are stored with millisecond precision, so the fixtures use whole seconds.
    @Test func recordWithoutLocalFileRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_792_411_200)
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let uploaded = CaptureRecord(timestamp: now, fileURL: nil, thumbnailFileName: "thumb.png", pixelWidth: 20, pixelHeight: 10,
                                     appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"),
                                     objectLocation: location, pendingObjectKey: "b.png")
        let pending = CaptureRecord(timestamp: now.addingTimeInterval(-1), fileURL: dir.appending(path: "pending/x.png"),
                                    fileIsTemporary: true, pixelWidth: 20, pixelHeight: 10, appName: "Notes",
                                    uploadState: .failed(message: "offline"))
        let first = store()
        first.add(uploaded)
        first.add(pending)

        let second = store()
        second.load()
        #expect(second.record(id: uploaded.id) == uploaded)
        #expect(second.record(id: pending.id) == pending)
        #expect(second.record(id: uploaded.id)?.hasLocalFile == false)
        #expect(second.record(id: uploaded.id)?.objectLocation == location)
        #expect(second.record(id: uploaded.id)?.pendingObjectKey == "b.png")
        #expect(second.record(id: pending.id)?.fileIsTemporary == true)
    }

    @Test func uploadedKeyAndPendingOnly() {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, uploadState: .failed(message: "x"))
        #expect(record.uploadedKey == nil)
        #expect(record.uploadedURL == nil)
        #expect(record.isFailed)
        #expect(!record.isPendingOnly)

        var uploadOnly = CaptureRecord(fileURL: dir.appending(path: "pending/x.png"), fileIsTemporary: true, pixelWidth: 1,
                                       pixelHeight: 1, appName: nil, uploadState: .failed(message: "offline"))
        #expect(uploadOnly.isPendingOnly)
        uploadOnly.uploadState = .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png")
        #expect(!uploadOnly.isPendingOnly)
    }
}
