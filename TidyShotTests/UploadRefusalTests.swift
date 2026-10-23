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

    @Test func retryFailedUploadsLeavesOutMarkedAndDeletingRecords() {
        let (first, marked, deleting, last) = (record(.image), record(unmuted: [MuteInterval(start: 0, end: 4)]),
                                               record(), record(.gif))
        let retried = AppCoordinator.failedRecordsToRetry([first, marked, deleting, last], deletingIDs: [deleting.id])
        #expect(retried.map(\.id) == [first.id, last.id])
        #expect(AppCoordinator.failedRecordsToRetry([], deletingIDs: []).isEmpty)
    }
}
