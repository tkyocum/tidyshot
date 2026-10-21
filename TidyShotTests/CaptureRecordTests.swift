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

    /// A record as Phase 3 wrote it: temporary flag, thumbnail and location, but no edit fields.
    let phase3JSON = """
    [
      {
        "fileIsTemporary" : true,
        "fileURL" : "file:///Users/tim/Library/Containers/io.tky.tidyshot/Data/Library/Application%20Support/TidyShot/pending/5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D.png",
        "id" : "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D",
        "objectLocation" : {
          "bucket" : "snap.tky.io",
          "endpoint" : "https://s3.us-west-2.amazonaws.com",
          "region" : "us-west-2",
          "usePathStyle" : true
        },
        "pixelHeight" : 100,
        "pixelWidth" : 200,
        "thumbnailFileName" : "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D.png",
        "timestamp" : "2026-10-19T16:56:03.000Z",
        "uploadState" : {
          "failed" : {
            "message" : "offline"
          }
        }
      }
    ]
    """

    @Test func editedAtAndStaleFlagDecodeFromPhaseThreeJSON() throws {
        try Data(phase3JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!))
        #expect(record.fileIsTemporary)
        #expect(record.thumbnailFileName == "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D.png")
        #expect(record.editedAt == nil)
        #expect(record.uploadIsStale == false)
        #expect(!record.keepsUnuploadedEdit)
    }

    /// Timestamps are stored with millisecond precision, so the fixture uses whole seconds.
    @Test func editedAtAndStaleFlagRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_792_411_200)
        let edited = CaptureRecord(timestamp: now, fileURL: dir.appending(path: "pending/x.png"), fileIsTemporary: true,
                                   pixelWidth: 40, pixelHeight: 30, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/x.png")!, key: "x.png"),
                                   editedAt: now.addingTimeInterval(90), uploadIsStale: true)
        store().add(edited)

        let reloaded = store()
        reloaded.load()
        let record = try #require(reloaded.record(id: edited.id))
        #expect(record == edited)
        #expect(record.editedAt == now.addingTimeInterval(90))
        #expect(record.uploadIsStale)
        #expect(record.keepsUnuploadedEdit)
    }

    /// A Phase 3.1 record: uploaded with a location and no local file, and no Phase 4 fields.
    @Test func supersededObjectsDefaultEmptyFromOldJSON() throws {
        let json = """
        [
          {
            "fileIsTemporary" : false,
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "objectLocation" : {
              "bucket" : "snap.tky.io",
              "endpoint" : "https://s3.us-west-2.amazonaws.com",
              "region" : "us-west-2",
              "usePathStyle" : true
            },
            "pixelHeight" : 10,
            "pixelWidth" : 20,
            "thumbnailFileName" : "6F9619FF-8B86-D011-B42D-00C04FC964FF.png",
            "timestamp" : "2026-10-19T16:56:03.000Z",
            "uploadState" : {
              "uploaded" : {
                "key" : "aB3dE9.png",
                "url" : "https://snap.tky.io/aB3dE9.png"
              }
            }
          }
        ]
        """
        try Data(json.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!))
        #expect(record.supersededObjects == [])
        #expect(record.uploadedKey == "aB3dE9.png")
        #expect(record.objectLocation?.bucket == "snap.tky.io")
    }

    @Test func supersededObjectsRoundTrip() throws {
        let here = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)
        let there = ObjectLocation(endpoint: "https://abc.r2.cloudflarestorage.com", region: "auto",
                                   bucket: "shots", usePathStyle: false)
        let record = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: nil, pixelWidth: 20, pixelHeight: 10,
                                   appName: nil, uploadState: .uploaded(url: URL(string: "https://snap.tky.io/new.png")!, key: "new.png"),
                                   objectLocation: here,
                                   supersededObjects: [ObjectRef(key: "old.png", location: here),
                                                       ObjectRef(key: "older.png", location: there)])
        store().add(record)

        let reloaded = store()
        reloaded.load()
        #expect(reloaded.record(id: record.id) == record)
        #expect(reloaded.record(id: record.id)?.supersededObjects.map { $0.location } == [here, there])
    }

    @Test func priorUploadDefaultsNilFromOldJSON() throws {
        try Data(phase2JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!))
        #expect(record.priorUpload == nil)
        #expect(record.supersededObjects == [])
        #expect(record.linkURL?.absoluteString == "https://snap.tky.io/aSIS7x.png")
    }

    @Test func priorUploadRoundTrips() throws {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let now = Date(timeIntervalSince1970: 1_792_411_200)
        let replace = PriorUpload(url: URL(string: "https://snap.tky.io/aB3dE9.png")!, key: "aB3dE9.png",
                                  location: location, isReplace: true)
        let asNew = PriorUpload(url: URL(string: "https://snap.tky.io/Qx12Zz.png")!, key: "Qx12Zz.png",
                                location: location, isReplace: false)
        let interrupted = CaptureRecord(timestamp: now, fileURL: dir.appending(path: "pending/x.png"), fileIsTemporary: true,
                                        pixelWidth: 20, pixelHeight: 10, appName: nil,
                                        uploadState: .failed(message: "Upload was interrupted."),
                                        objectLocation: location, priorUpload: replace)
        let failed = CaptureRecord(timestamp: now.addingTimeInterval(-1), fileURL: nil, pixelWidth: 20, pixelHeight: 10, appName: nil,
                                   uploadState: .failed(message: "offline"), objectLocation: location, priorUpload: asNew)
        let first = store()
        first.add(interrupted)
        first.add(failed)

        let second = store()
        second.load()
        #expect(second.record(id: interrupted.id) == interrupted)
        #expect(second.record(id: interrupted.id)?.priorUpload == replace)
        #expect(second.record(id: failed.id)?.priorUpload == asNew)
    }

    /// `uploadedURL` stays computed from `uploadState` alone. The link falls back to the prior
    /// upload while an editor upload runs and after one was interrupted.
    @Test func linkURLFallsBackToPriorUpload() {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let old = URL(string: "https://snap.tky.io/aB3dE9.png")!
        var record = CaptureRecord(fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, uploadState: .uploading(fraction: 0.3),
                                   priorUpload: PriorUpload(url: old, key: "aB3dE9.png", location: location, isReplace: true))
        #expect(record.uploadedURL == nil)
        #expect(record.uploadedKey == nil)
        #expect(record.linkURL == old)

        record.uploadState = .failed(message: "Upload was interrupted.")
        #expect(record.linkURL == old)

        let new = URL(string: "https://snap.tky.io/Qx12Zz.png")!
        record.uploadState = .uploaded(url: new, key: "Qx12Zz.png")
        #expect(record.linkURL == new)

        record.priorUpload = nil
        record.uploadState = .failed(message: "offline")
        #expect(record.linkURL == nil)
    }

    /// The staleness rule follows the link, not `uploadedURL`: a replace interrupted by a quit leaves
    /// `.failed` with the link in `priorUpload`, and the next local edit must still mark the link stale.
    @Test func localEditMarksStaleWhenThereIsALink() {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let edited = Date(timeIntervalSince1970: 1_792_411_200)
        let prior = PriorUpload(url: URL(string: "https://snap.tky.io/aB3dE9.png")!, key: "aB3dE9.png",
                                location: location, isReplace: true)

        var interrupted = CaptureRecord(fileURL: nil, fileIsTemporary: true, pixelWidth: 20, pixelHeight: 10, appName: nil,
                                        uploadState: .failed(message: "Upload was interrupted."),
                                        objectLocation: location, priorUpload: prior)
        interrupted.recordLocalEdit(pixelWidth: 40, pixelHeight: 30, at: edited)
        #expect(interrupted.uploadedURL == nil)
        #expect(interrupted.uploadIsStale)
        #expect(interrupted.editedAt == edited)
        #expect(interrupted.pixelWidth == 40 && interrupted.pixelHeight == 30)

        var uploaded = CaptureRecord(fileURL: nil, pixelWidth: 20, pixelHeight: 10, appName: nil,
                                     uploadState: .uploaded(url: prior.url, key: "aB3dE9.png"), objectLocation: location)
        uploaded.recordLocalEdit(pixelWidth: 20, pixelHeight: 10, at: edited)
        #expect(uploaded.uploadIsStale)

        // No link at all: nothing shows the original, so there is nothing to call stale.
        var never = CaptureRecord(fileURL: nil, pixelWidth: 20, pixelHeight: 10, appName: nil)
        never.recordLocalEdit(pixelWidth: 40, pixelHeight: 30, at: edited)
        #expect(!never.uploadIsStale)
        #expect(never.editedAt == edited)
    }
}
