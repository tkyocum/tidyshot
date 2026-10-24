import Foundation
import Testing
@testable import TidyShot

/// The upload gates: Retry and `startUpload` refuse a record marked `Sound not muted` (design,
/// Privacy rule) or being trimmed (design, Write-time checks), and Retry Failed Uploads skips it.
struct UploadRefusalTests {
    func record(_ kind: MediaKind = .video, unmuted: [MuteInterval] = [],
                state: CaptureRecord.UploadState = .failed(message: "Upload was interrupted.")) -> CaptureRecord {
        CaptureRecord(fileURL: URL(filePath: "/tmp/pending/x.\(kind.fileExtension)"), fileIsTemporary: true,
                      pixelWidth: 1, pixelHeight: 1, appName: nil, uploadState: state, mediaKind: kind,
                      unmutedIntervals: unmuted)
    }

    @Test func aMarkedRecordIsRefusedWithTheMarksText() {
        let marked = record(unmuted: [MuteInterval(start: 1.9, end: 5.3)])
        #expect(AppCoordinator.uploadRefusal(for: marked) == CaptureRecord.soundNotMutedBody)
    }

    @Test func anUnmarkedRecordIsNotRefused() {
        for kind in [MediaKind.image, .video, .gif] {
            #expect(AppCoordinator.uploadRefusal(for: record(kind)) == nil)
        }
    }

    /// While its Trim pass runs (design, Write-time checks): Retry, `Upload Trimmed` and `startUpload`
    /// refuse with the trimming text, also for a marked record, whose pass is what fixes it.
    @Test func aRecordBeingTrimmedIsRefusedWithTheTrimmingText() {
        #expect(AppCoordinator.uploadRefusal(for: record(), isTrimming: true) == "This capture is being trimmed.")
        #expect(AppCoordinator.uploadRefusal(for: record(unmuted: [MuteInterval(start: 0, end: 1)]), isTrimming: true)
                == "This capture is being trimmed.")
        #expect(AppCoordinator.uploadRefusal(for: record(), isTrimming: false) == nil)
    }

    @Test func retryFailedUploadsLeavesOutARecordBeingTrimmed() {
        let (first, trimming, last) = (record(), record(), record(.image))
        let retried = AppCoordinator.failedRecordsToRetry([first, trimming, last], deletingIDs: [],
                                                          trimmingIDs: [trimming.id])
        #expect(retried.map(\.id) == [first.id, last.id])
    }

    /// `Upload Trimmed` (design, Stale link): refused while trimmed or marked, then as the editor's
    /// Upload is (being deleted, uploading), then with no local file, then with a link that is not
    /// stale or no link. A deleted record is refused before this, by `uploadTrimmed`'s lookup.
    @Test func uploadTrimmedIsRefusedInTheGatesOrder() {
        let folder = URL(filePath: "/Users/tim/Movies/TidyShot", directoryHint: .isDirectory)
        let link = URL(string: "https://snap.tky.io/rec.mp4")!
        var stale = record(state: .uploaded(url: link, key: "rec.mp4"))
        stale.uploadIsStale = true
        func refusal(_ record: CaptureRecord, deleting: Bool = false, trimming: Bool = false) -> String? {
            AppCoordinator.uploadTrimmedRefusal(for: record, saveFolder: folder, isDeleting: deleting, isTrimming: trimming)
        }
        #expect(refusal(stale) == nil)
        #expect(refusal(stale, deleting: true, trimming: true) == EditorAvailability.trimmingRefusal)
        var marked = stale
        marked.unmutedIntervals = [MuteInterval(start: 0, end: 1)]
        #expect(refusal(marked, deleting: true) == CaptureRecord.soundNotMutedBody)
        #expect(refusal(stale, deleting: true) == EditorAvailability.deletingRefusal)
        #expect(refusal(record(state: .uploading(fraction: 0.4))) == EditorAvailability.uploadingRefusal)
        var noFile = stale
        noFile.fileURL = nil
        noFile.fileIsTemporary = false
        #expect(refusal(noFile) == "The file could not be read: no local file")
        // Last, as the menu shows the item only for a stale link: a link that shows the file already,
        // as after an upload that ended while the menu was open. A record with no link is told so.
        #expect(refusal(record(state: .uploaded(url: link, key: "rec.mp4"))) == "The link already shows the trimmed recording.")
        #expect(refusal(record(state: .none)) == "This capture has no link to update.")
        #expect(refusal(record()) == "This capture has no link to update.")
        #expect(AppCoordinator.linkShowsTrimText == "The link already shows the trimmed recording.")
    }

    /// `Upload not configured`'s body, one constant for the editor's Upload, Save and Upload and
    /// `Upload Trimmed`.
    @Test func theUploadNotConfiguredBodyHasTheDesignsText() {
        #expect(AppCoordinator.uploadNotConfiguredBody == "Set up a destination in Settings > Upload, then upload again.")
    }

    @Test func retryFailedUploadsLeavesOutMarkedAndDeletingRecords() {
        let (first, marked, deleting, last) = (record(.image), record(unmuted: [MuteInterval(start: 0, end: 4)]),
                                               record(), record(.gif))
        let retried = AppCoordinator.failedRecordsToRetry([first, marked, deleting, last], deletingIDs: [deleting.id])
        #expect(retried.map(\.id) == [first.id, last.id])
        #expect(AppCoordinator.failedRecordsToRetry([], deletingIDs: []).isEmpty)
    }
}
