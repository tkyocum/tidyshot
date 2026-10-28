import Foundation
import Testing
import UniformTypeIdentifiers
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

    /// A trim (design, Trim, Save) changes the length and `editedAt`. The pixel size stays, and so
    /// does `uploadIsStale`: the Trim pass sets it itself, before the put, and clears it if the put fails.
    @Test func localTrimSetsTheDurationAndEditedAtOnly() {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let edited = Date(timeIntervalSince1970: 1_792_411_200)
        for stale in [false, true] {
            var record = CaptureRecord(fileURL: URL(filePath: "/tmp/pending/x.mp4"), fileIsTemporary: true,
                                       pixelWidth: 2560, pixelHeight: 1664, appName: nil,
                                       uploadState: .uploaded(url: URL(string: "https://snap.tky.io/x.mp4")!, key: "x.mp4"),
                                       objectLocation: location, uploadIsStale: stale, mediaKind: .video,
                                       durationSeconds: 64.2)
            record.recordLocalTrim(duration: 12.4, at: edited)
            #expect(record.durationSeconds == 12.4)
            #expect(record.editedAt == edited)
            #expect(record.pixelWidth == 2560 && record.pixelHeight == 1664)
            #expect(record.uploadIsStale == stale)
        }
    }

    /// A trim's write (design, Trim, Save; `finishTrimWrite`): the trimmed file's length and size,
    /// `editedAt`, and `Sound not muted` cleared; a length that could not be read (0) is the range's,
    /// and a size that could not be read leaves none; a `.newPendingFile` put points the record at the
    /// new pending file. The pixel size, the link and `uploadIsStale` stay.
    @Test func aTrimsWriteRecordsTheTrimmedFile() {
        let edited = Date(timeIntervalSince1970: 1_792_411_200)
        let link = URL(string: "https://snap.tky.io/x.mp4")!
        let saved = URL(filePath: "/Users/tim/Movies/TidyShot/x.mp4")
        var record = CaptureRecord(fileURL: saved, fileIsTemporary: false, pixelWidth: 2560, pixelHeight: 1664,
                                   appName: nil, uploadState: .uploaded(url: link, key: "x.mp4"), uploadIsStale: true,
                                   mediaKind: .video, durationSeconds: 64.2, byteCount: 90_000_000,
                                   unmutedIntervals: [MuteInterval(start: 1.9, end: 3.3)])
        var trimmed = record
        trimmed.recordTrimWrite(length: 12.4, byteCount: 17_000_000, rangeDuration: 12.5, pendingFile: nil, at: edited)
        #expect(trimmed.durationSeconds == 12.4)
        #expect(trimmed.byteCount == 17_000_000)
        #expect(trimmed.editedAt == edited)
        #expect(trimmed.unmutedIntervals.isEmpty && trimmed.uploadBlockedReason == nil)
        #expect(trimmed.fileURL == saved && !trimmed.fileIsTemporary)
        #expect(trimmed.pixelWidth == 2560 && trimmed.pixelHeight == 1664)
        #expect(trimmed.uploadIsStale && trimmed.linkURL == link)

        // Neither the length nor the size could be read.
        trimmed = record
        trimmed.recordTrimWrite(length: 0, byteCount: 0, rangeDuration: 12.5, pendingFile: nil, at: edited)
        #expect(trimmed.durationSeconds == 12.5)
        #expect(trimmed.byteCount == nil)

        // Save and Upload with nothing to write over.
        record.fileURL = nil
        let pending = URL(filePath: "/tmp/pending/x.mp4")
        record.recordTrimWrite(length: 12.4, byteCount: 17_000_000, rangeDuration: 12.5, pendingFile: pending, at: edited)
        #expect(record.fileURL == pending && record.fileIsTemporary)
        #expect(record.durationSeconds == 12.4 && record.unmutedIntervals.isEmpty)
    }

    // MARK: Media kind (recording R1)

    @Test func historyWithoutMediaKindDecodesAsImages() throws {
        try Data(phase3JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!))
        #expect(record.mediaKind == .image)
        #expect(record.durationSeconds == nil)
        #expect(!record.isTimeBased)
    }

    /// A kind from a newer TidyShot reads as a video, so the history is never set aside for it.
    @Test func unknownMediaKindDecodesAsVideo() throws {
        let json = """
        [
          {
            "durationSeconds" : 12.5,
            "fileIsTemporary" : true,
            "fileURL" : "file:///Users/tim/Library/Containers/io.tky.tidyshot/Data/Library/Application%20Support/TidyShot/pending/7A1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D.gif",
            "id" : "7A1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D",
            "mediaKind" : "animation",
            "pixelHeight" : 100,
            "pixelWidth" : 200,
            "timestamp" : "2026-10-22T16:56:03.000Z",
            "uploadState" : {
              "none" : {
              }
            }
          }
        ]
        """
        try Data(json.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "7A1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!))
        #expect(record.mediaKind == .video)
        #expect(record.isTimeBased)
        #expect(record.durationSeconds == 12.5)
    }

    @Test func videoRecordRoundTrips() throws {
        let video = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: dir.appending(path: "pending/v.mp4"),
                                  fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                  mediaKind: .video, durationSeconds: 42.25)
        store().add(video)

        let reloaded = store()
        reloaded.load()
        let record = try #require(reloaded.record(id: video.id))
        #expect(record == video)
        #expect(record.mediaKind == .video)
        #expect(record.durationSeconds == 42.25)
        #expect(record.isTimeBased)
    }

    // MARK: GIF and muting (recording R2)

    @Test func gifRecordRoundTrips() throws {
        let gif = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: dir.appending(path: "pending/g.gif"),
                                fileIsTemporary: true, pixelWidth: 1280, pixelHeight: 832, appName: nil,
                                mediaKind: .gif, durationSeconds: 10.33, byteCount: 14_820_000)
        store().add(gif)

        let reloaded = store()
        reloaded.load()
        let record = try #require(reloaded.record(id: gif.id))
        #expect(record == gif)
        #expect(record.mediaKind == .gif)
        #expect(record.durationSeconds == 10.33)
        #expect(record.byteCount == 14_820_000)
        #expect(record.unmutedIntervals.isEmpty)
    }

    @Test func gifKindTypes() {
        #expect(MediaKind.gif.fileExtension == "gif")
        #expect(MediaKind.gif.contentType == "image/gif")
        #expect(MediaKind.gif.utType == .gif)
        #expect(MediaKind(rawValue: "gif") == .gif)
    }

    /// A GIF uploads as made, with Clop on or off (Decided 2026-10-23, 2).
    @Test func onlyAGIFIsNotSentToClop() {
        #expect(!MediaKind.gif.isSentToClop)
        #expect(MediaKind.image.isSentToClop)
        #expect(MediaKind.video.isSentToClop)
    }

    /// One predicate for every R1 gate on a recording: an MP4, a GIF, or a kind from a newer
    /// TidyShot (which reads as `.video`).
    @Test func everyKindButAnImageIsTimeBased() throws {
        func record(_ kind: MediaKind) -> CaptureRecord {
            CaptureRecord(fileURL: nil, pixelWidth: 10, pixelHeight: 10, appName: nil, mediaKind: kind)
        }
        #expect(!record(.image).isTimeBased)
        #expect(record(.video).isTimeBased)
        #expect(record(.gif).isTimeBased)

        let json = #""future""#
        let unknown = try JSONDecoder().decode(MediaKind.self, from: Data(json.utf8))
        #expect(unknown == .video)
        #expect(record(unknown).isTimeBased)
    }

    /// The `Sound not muted` mark: an open interval (a mute log's last press) keeps no end, and
    /// the size and duration round-trip beside it.
    @Test func unmutedIntervalsRoundTrip() throws {
        let intervals = [MuteInterval(start: 1.5, end: 3.25), MuteInterval(start: 7, end: nil)]
        let marked = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: dir.appending(path: "pending/m.mp4"),
                                   fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                   mediaKind: .video, durationSeconds: 9.5, byteCount: 14_000_000,
                                   unmutedIntervals: intervals)
        store().add(marked)

        let reloaded = store()
        reloaded.load()
        let record = try #require(reloaded.record(id: marked.id))
        #expect(record == marked)
        #expect(record.unmutedIntervals == intervals)
        #expect(record.unmutedIntervals.last?.end == nil)
        #expect(record.durationSeconds == 9.5)
        #expect(record.byteCount == 14_000_000)

        let open = String(decoding: try JSONEncoder().encode(MuteInterval(start: 7, end: nil)), as: UTF8.self)
        #expect(open.contains("start"))
        #expect(!open.contains("end"))
    }

    /// Files from before R2 have no `unmutedIntervals`; their records decode unmarked.
    @Test func historyWithoutUnmutedIntervalsDecodesEmpty() throws {
        for json in [phase2JSON, phase3JSON] {
            try Data(json.utf8).write(to: dir.appending(path: "history.json"))
            let history = store()
            history.load()
            let record = try #require(history.records.first)
            #expect(record.unmutedIntervals.isEmpty)
            #expect(record.uploadBlockedReason == nil)
        }
    }

    @Test func onlyAMarkedRecordIsBlockedFromUploading() {
        var record = CaptureRecord(fileURL: nil, pixelWidth: 10, pixelHeight: 10, appName: nil, mediaKind: .video,
                                   durationSeconds: 4)
        #expect(record.uploadBlockedReason == nil)
        record.unmutedIntervals = [MuteInterval(start: 0, end: 4)]
        #expect(record.uploadBlockedReason == CaptureRecord.soundNotMutedBody)
        record.unmutedIntervals = []
        #expect(record.uploadBlockedReason == nil)

        #expect(CaptureRecord.soundNotMutedTitle == "Sound not muted")
        #expect(CaptureRecord.soundNotMutedBody
                == "Muting failed. The recording is kept in TidyShot and not uploaded. Trim it to fix the sound, or delete it.")
    }

    /// Trim sets a recording's length again, so it is a `var`.
    @Test func durationSecondsChangesAndRoundTrips() throws {
        var video = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: dir.appending(path: "pending/t.mp4"),
                                  fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                  mediaKind: .video, durationSeconds: 42.25, byteCount: 3_400_000)
        video.durationSeconds = 12.5
        store().add(video)

        let reloaded = store()
        reloaded.load()
        let record = try #require(reloaded.record(id: video.id))
        #expect(record.durationSeconds == 12.5)
        #expect(record.byteCount == 3_400_000)
    }

    // MARK: Size (spec 2.13)

    @Test func byteCountRoundTrips() throws {
        let video = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: dir.appending(path: "pending/v.mp4"),
                                  fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                  mediaKind: .video, durationSeconds: 42.25, byteCount: 3_400_000_000)
        let image = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_100), fileURL: dir.appending(path: "Shot.png"),
                                  pixelWidth: 20, pixelHeight: 10, appName: nil, byteCount: 5_120)
        let first = store()
        first.add(video)
        first.add(image)

        let reloaded = store()
        reloaded.load()
        #expect(reloaded.record(id: video.id) == video)
        #expect(reloaded.record(id: video.id)?.byteCount == 3_400_000_000)
        #expect(reloaded.record(id: image.id)?.byteCount == 5_120)
    }

    /// Files from before 2.13 have no `byteCount`; their records decode with no size, and a record
    /// with no size writes no key.
    @Test func historyWithoutByteCountDecodesAsNil() throws {
        try Data(phase2JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()
        let record = try #require(history.record(id: UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!))
        #expect(record.byteCount == nil)

        try Data(phase3JSON.utf8).write(to: dir.appending(path: "history.json"))
        let phase3 = store()
        phase3.load()
        #expect(phase3.record(id: UUID(uuidString: "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!)?.byteCount == nil)

        let encoded = try JSONEncoder().encode(record)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("byteCount"))
    }

    // MARK: Multipart state (R4)

    func multipartState(modified: Date = Date(timeIntervalSinceReferenceDate: 783_456_789.1234567)) -> MultipartUploadState {
        MultipartUploadState(
            uploadID: "VXBsb2FkSWQ", key: "aB3dE9.mp4",
            location: ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                     bucket: "snap.tky.io", usePathStyle: true),
            partSize: 16_777_216, byteCount: 3_400_000_000, sourceModified: modified,
            sourcePath: "/Users/tim/Movies/rec.mp4", startedAt: Date(timeIntervalSince1970: 1_792_411_000))
    }

    @Test func multipartStateRoundTripsAndOldHistoryDecodesNil() throws {
        var video = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: dir.appending(path: "rec.mp4"),
                                  pixelWidth: 1600, pixelHeight: 1000, appName: nil, mediaKind: .video)
        video.multipart = multipartState()
        let plain = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_100), fileURL: dir.appending(path: "Shot.png"),
                                  pixelWidth: 20, pixelHeight: 10, appName: nil)
        #expect(plain.multipart == nil)
        let first = store()
        first.add(video)
        first.add(plain)

        let reloaded = store()
        reloaded.load()
        #expect(reloaded.record(id: video.id) == video)
        #expect(reloaded.record(id: video.id)?.multipart == multipartState())
        #expect(reloaded.record(id: plain.id)?.multipart == nil)

        // A record with no state writes no key; files from before R4 decode it nil.
        let encoded = try JSONEncoder().encode(plain)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("multipart"))
        try Data(phase2JSON.utf8).write(to: dir.appending(path: "history.json"))
        let old = store()
        old.load()
        #expect(old.record(id: UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!)?.multipart == nil)
    }

    /// `HistoryStore` writes dates in milliseconds. The state's modification date is coded as a
    /// `Double`, so the resume check after a relaunch still sees the file's own date.
    @Test func subMillisecondSourceDateSurvivesHistoryAndResumes() throws {
        let modified = Date(timeIntervalSinceReferenceDate: 783_456_789.1234567)
        var video = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: dir.appending(path: "rec.mp4"),
                                  pixelWidth: 1600, pixelHeight: 1000, appName: nil, mediaKind: .video)
        video.multipart = multipartState(modified: modified)
        store().add(video)

        let reloaded = store()
        reloaded.load()
        let state = try #require(reloaded.record(id: video.id)?.multipart)
        #expect(state.sourceModified == modified)
        let decision = MultipartPlan.resumeDecision(
            stored: state, location: state.location, fixedKey: nil,
            source: MultipartSourceAttributes(byteCount: 3_400_000_000, modified: modified))
        #expect(decision == .resume(state))
    }

    @Test func mediaKindTypes() {
        #expect(MediaKind.image.fileExtension == "png")
        #expect(MediaKind.video.fileExtension == "mp4")
        #expect(MediaKind.image.contentType == "image/png")
        #expect(MediaKind.video.contentType == "video/mp4")
        #expect(MediaKind.image.utType == .png)
        #expect(MediaKind.video.utType == .mpeg4Movie)
    }
}
