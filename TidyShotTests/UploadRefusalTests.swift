import Foundation
import Testing
@testable import TidyShot

/// The Privacy rule's upload gates (design, Sound not muted): Retry and `startUpload` refuse a record
/// marked `Sound not muted`, and Retry Failed Uploads skips it.
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

    @Test func retryFailedUploadsLeavesOutMarkedAndDeletingRecords() {
        let (first, marked, deleting, last) = (record(.image), record(unmuted: [MuteInterval(start: 0, end: 4)]),
                                               record(), record(.gif))
        let retried = AppCoordinator.failedRecordsToRetry([first, marked, deleting, last], deletingIDs: [deleting.id])
        #expect(retried.map(\.id) == [first.id, last.id])
        #expect(AppCoordinator.failedRecordsToRetry([], deletingIDs: []).isEmpty)
    }
}
