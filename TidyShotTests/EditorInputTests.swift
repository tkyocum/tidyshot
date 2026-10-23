import Foundation
import Testing
@testable import TidyShot

struct EditorInputTests {
    let folder = URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot", isDirectory: true)
    let saved = URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Shot.png")
    /// A file in a folder that is no longer the save folder.
    let elsewhere = URL(fileURLWithPath: "/Users/tim/Desktop/Old Shots/Shot.png")
    let pending = URL(fileURLWithPath: "/Users/tim/Library/Containers/TidyShot/Data/pending/A.png")
    let link = URL(string: "https://snap.tky.io/aB3dE9.png")!
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap", usePathStyle: false)

    func record(_ state: CaptureRecord.UploadState = .none, file: URL?, temporary: Bool = false,
                location: ObjectLocation? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: file, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: nil,
                      uploadState: state, objectLocation: location)
    }

    @Test func retainedWinsForLatestCapture() {
        let uploading = record(.uploading(fraction: 0.4), file: pending, temporary: true)
        #expect(EditorInput.source(for: uploading, retainedID: uploading.id, saveFolder: folder) == .retained)
        // Upload-only, uploaded: the pending file went with the upload, the image is still in memory.
        let uploadedOnly = record(.uploaded(url: link, key: "aB3dE9.png"), file: nil, location: location)
        #expect(EditorInput.source(for: uploadedOnly, retainedID: uploadedOnly.id, saveFolder: nil) == .retained)
        // Another capture's image is not this one's.
        let savedRecord = record(file: saved)
        #expect(EditorInput.source(for: savedRecord, retainedID: UUID(), saveFolder: folder) == .saveFolderFile(saved))
    }

    @Test func pendingFileForUploadOnlyPending() {
        let uploading = record(.uploading(fraction: 0.4), file: pending, temporary: true)
        #expect(EditorInput.source(for: uploading, retainedID: nil, saveFolder: folder) == .pendingFile(pending))
        // A pending file needs no save folder.
        let failed = record(.failed(message: "Upload not configured"), file: pending, temporary: true)
        #expect(EditorInput.source(for: failed, retainedID: nil, saveFolder: nil) == .pendingFile(pending))
        // After a failed replace the pending file holds the edit and the object the original: the file wins.
        var stale = record(.uploaded(url: link, key: "aB3dE9.png"), file: pending, temporary: true, location: location)
        stale.uploadIsStale = true
        #expect(EditorInput.source(for: stale, retainedID: nil, saveFolder: nil) == .pendingFile(pending))
    }

    @Test func saveFolderFileForSavedCapture() {
        #expect(EditorInput.source(for: record(file: saved), retainedID: nil, saveFolder: folder) == .saveFolderFile(saved))
        // Upload mode: the file is read before the object, also once uploaded.
        let uploaded = record(.uploaded(url: link, key: "aB3dE9.png"), file: saved, location: location)
        #expect(EditorInput.source(for: uploaded, retainedID: nil, saveFolder: folder) == .saveFolderFile(saved))
    }

    @Test func downloadWhenFileGoneAndUploaded() {
        let uploadedOnly = record(.uploaded(url: link, key: "shots/aB3dE9.png"), file: nil, location: location)
        #expect(EditorInput.source(for: uploadedOnly, retainedID: nil, saveFolder: folder)
                == .download(key: "shots/aB3dE9.png", location: location))
    }

    @Test func unavailableForLegacyRecordWithoutFileOrLocation() {
        let legacy = record(.uploaded(url: link, key: "aB3dE9.png"), file: nil)
        #expect(EditorInput.source(for: legacy, retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.unknownLocationText))
    }

    @Test func unavailableWhenNeverUploadedAndNoFile() {
        let nothing = record(.failed(message: "Upload was interrupted."), file: nil)
        #expect(EditorInput.source(for: nothing, retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.neverUploadedText))
        #expect(EditorInput.source(for: record(file: nil), retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.neverUploadedText))
    }

    /// Uploaded before Phase 3: a file and a key, but no location to download from.
    @Test func legacyRecordWithFileReadsTheFile() {
        let legacy = record(.uploaded(url: link, key: "aB3dE9.png"), file: saved)
        #expect(EditorInput.source(for: legacy, retainedID: nil, saveFolder: folder) == .saveFolderFile(saved))
        let otherFolder = URL(fileURLWithPath: "/Users/tim/Desktop", isDirectory: true)
        #expect(EditorInput.source(for: legacy, retainedID: nil, saveFolder: otherFolder)
                == .unavailable(EditorInput.outsideSaveFolderText))
    }

    @Test func fileOutsideSaveFolderDownloadsWhenUploaded() {
        let moved = record(.uploaded(url: link, key: "aB3dE9.png"), file: elsewhere, location: location)
        #expect(EditorInput.source(for: moved, retainedID: nil, saveFolder: folder)
                == .download(key: "aB3dE9.png", location: location))
        #expect(EditorInput.source(for: moved, retainedID: nil, saveFolder: nil)
                == .download(key: "aB3dE9.png", location: location))
    }

    @Test func fileOutsideSaveFolderWithoutUploadIsUnavailable() {
        let old = record(file: elsewhere)
        #expect(EditorInput.source(for: old, retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.outsideSaveFolderText))
        #expect(EditorInput.source(for: old, retainedID: nil, saveFolder: nil)
                == .unavailable(EditorInput.outsideSaveFolderText))
    }

    /// A video is checked first: whatever the editor could otherwise load from, it cannot annotate one.
    @Test func aVideoIsUnavailable() {
        #expect(EditorInput.videoText == "Videos cannot be annotated.")
        let recording = URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Recording.mp4")
        let pendingVideo = URL(fileURLWithPath: "/Users/tim/Library/Containers/TidyShot/Data/pending/A.mp4")
        let videos = [
            CaptureRecord(fileURL: recording, pixelWidth: 10, pixelHeight: 10, appName: nil, mediaKind: .video),
            CaptureRecord(fileURL: pendingVideo, fileIsTemporary: true, pixelWidth: 10, pixelHeight: 10, appName: nil,
                          uploadState: .uploading(fraction: 0.2), mediaKind: .video),
            CaptureRecord(fileURL: nil, pixelWidth: 10, pixelHeight: 10, appName: nil,
                          uploadState: .uploaded(url: link, key: "aB3dE9.mp4"), objectLocation: location, mediaKind: .video),
        ]
        for video in videos {
            #expect(EditorInput.source(for: video, retainedID: video.id, saveFolder: folder)
                    == .unavailable(EditorInput.videoText))
        }
    }
}
