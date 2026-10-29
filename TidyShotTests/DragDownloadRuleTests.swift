import Foundation
import Testing
@testable import TidyShot

/// When a drag on a card downloads an uploaded recording with no local file (design, Drag-out
/// download), the disk check, the resume window and the auto-close rule.
struct DragDownloadRuleTests {
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap", usePathStyle: false)
    let link = URL(string: "https://snap.tky.io/aB3dE9.mp4")!

    func record(_ kind: MediaKind = .video, file: URL? = nil, uploaded: Bool = true,
                location: ObjectLocation? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: file, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                      uploadState: uploaded ? .uploaded(url: link, key: "aB3dE9.mp4") : .none,
                      objectLocation: location ?? self.location, mediaKind: kind,
                      durationSeconds: kind == .image ? nil : 42)
    }

    func starts(_ record: CaptureRecord, hasDragFile: Bool = false, isRunning: Bool = false) -> Bool {
        DragDownloadRule.starts(record: record, hasDragFile: hasDragFile, isRunning: isRunning)
    }

    /// An uploaded MP4 or GIF with no local file downloads for a drag.
    @Test func startsForAnUploadedVideoOrGIFWithNoLocalFile() {
        #expect(starts(record(.video)))
        #expect(starts(record(.gif)))
    }

    /// An image, a recording with a local file, one whose drag file is staged or whose download
    /// runs, one marked `Sound not muted`, and one that is not uploaded download nothing.
    @Test func startsForNothingElse() {
        #expect(!starts(record(.image)))
        #expect(!starts(record(.video, file: URL(fileURLWithPath: "/Users/tim/Desktop/Recording.mp4"))))
        #expect(!starts(record(.video), hasDragFile: true))
        #expect(!starts(record(.video), isRunning: true))
        var marked = record(.video)
        marked.unmutedIntervals = [MuteInterval(start: 2, end: 5)]
        #expect(!starts(marked))
        #expect(!starts(record(.video, uploaded: false)))
        var failed = record(.video)
        failed.uploadState = .failed(message: "offline")
        #expect(!starts(failed))
        var noLocation = record(.video)
        noLocation.objectLocation = nil
        #expect(!starts(noLocation))
    }

    /// The file's size plus 1 GB free, as a recording keeps; an unknown size or free space counts
    /// as enough.
    @Test func hasRoomForTheFileAndOneGB() {
        let size = 300_000_000
        let needed = Int64(size) + RecordingLimits.runningFreeBytes
        #expect(DragDownloadRule.hasRoom(byteCount: size, freeBytes: needed))
        #expect(!DragDownloadRule.hasRoom(byteCount: size, freeBytes: needed - 1))
        #expect(DragDownloadRule.hasRoom(byteCount: nil, freeBytes: 0))
        #expect(DragDownloadRule.hasRoom(byteCount: size, freeBytes: nil))
    }

    /// Resume data is used while less than 14 minutes have passed since the request was signed.
    @Test func usesResumeDataForUnderFourteenMinutes() {
        let signedAt = Date(timeIntervalSince1970: 1_792_411_200)
        #expect(DragDownloadRule.resumeWindow == 840)
        #expect(DragDownloadRule.usesResumeData(signedAt: signedAt, now: signedAt))
        #expect(DragDownloadRule.usesResumeData(signedAt: signedAt, now: signedAt.addingTimeInterval(13 * 60 + 59)))
        #expect(!DragDownloadRule.usesResumeData(signedAt: signedAt, now: signedAt.addingTimeInterval(14 * 60)))
    }

    /// The auto-close countdown waits during a download as it does during a drag.
    @Test func keepsTheCardOpenWhileDraggingOrDownloading() {
        #expect(!DragDownloadRule.keepsCardOpen(isDraggingOut: false, isDownloading: false))
        #expect(DragDownloadRule.keepsCardOpen(isDraggingOut: true, isDownloading: false))
        #expect(DragDownloadRule.keepsCardOpen(isDraggingOut: false, isDownloading: true))
        #expect(DragDownloadRule.keepsCardOpen(isDraggingOut: true, isDownloading: true))
    }

    /// The partial file URLSession names in resume data, keyed-archive or plain, found in the
    /// temporary folder, so a resume that is dropped unused can remove it.
    @Test func findsThePartialFileTheResumeDataNames() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let partial = folder.appendingPathComponent("CFNetworkDownload_aB3dE9.tmp")
        try Data([1, 2, 3]).write(to: partial)

        let archived = try NSKeyedArchiver.archivedData(
            withRootObject: ["NSURLSessionResumeInfoTempFileName": "CFNetworkDownload_aB3dE9.tmp",
                             "NSURLSessionResumeBytesReceived": 3] as NSDictionary,
            requiringSecureCoding: false)
        #expect(DragDownloadRule.partialFile(in: archived, temporaryDirectory: folder) == partial)

        let plain = try PropertyListSerialization.data(
            fromPropertyList: ["NSURLSessionResumeInfoLocalPath": partial.path], format: .xml, options: 0)
        #expect(DragDownloadRule.partialFile(in: plain, temporaryDirectory: folder) == partial)
    }

    /// No file, a folder or data that is not a property list gives nothing to remove.
    @Test func findsNoPartialFileWhenNoneIsThere() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("CFNetworkDownload_dir.tmp"),
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = try PropertyListSerialization.data(
            fromPropertyList: ["NSURLSessionResumeInfoTempFileName": "CFNetworkDownload_gone.tmp"], format: .xml, options: 0)
        let directory = try PropertyListSerialization.data(
            fromPropertyList: ["NSURLSessionResumeInfoTempFileName": "CFNetworkDownload_dir.tmp"], format: .xml, options: 0)
        #expect(DragDownloadRule.partialFile(in: missing, temporaryDirectory: folder) == nil)
        #expect(DragDownloadRule.partialFile(in: directory, temporaryDirectory: folder) == nil)
        #expect(DragDownloadRule.partialFile(in: Data("not a plist".utf8), temporaryDirectory: folder) == nil)
    }
}
