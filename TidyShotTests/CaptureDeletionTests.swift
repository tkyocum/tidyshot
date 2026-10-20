import Foundation
import Testing
@testable import TidyShot

struct CaptureDeletionTests {
    let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)

    func record(state: CaptureRecord.UploadState, fileURL: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                temporary: Bool = false, location: ObjectLocation? = nil, pendingKey: String? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: "Safari",
                      uploadState: state, objectLocation: location, pendingObjectKey: pendingKey)
    }

    @Test func objectKeysAreTheUploadedAndThePendingKey() {
        let uploaded = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location)
        #expect(CaptureDeletion.objectKeys(for: uploaded) == ["aB3dE9.png"])

        let cancelled = record(state: .failed(message: "Upload cancelled."), location: location, pendingKey: "Qx12Zz.png")
        #expect(CaptureDeletion.objectKeys(for: cancelled) == ["Qx12Zz.png"])

        let both = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location, pendingKey: "Qx12Zz.png")
        #expect(CaptureDeletion.objectKeys(for: both) == ["aB3dE9.png", "Qx12Zz.png"])

        let same = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location, pendingKey: "aB3dE9.png")
        #expect(CaptureDeletion.objectKeys(for: same) == ["aB3dE9.png"])
    }

    @Test func objectKeysForLocalOnlyCaptureAreEmpty() {
        #expect(CaptureDeletion.objectKeys(for: record(state: .none)) == [])
        #expect(CaptureDeletion.objectKeys(for: record(state: .failed(message: "offline"))) == [])
        #expect(CaptureDeletion.objectKeys(for: record(state: .uploading(fraction: 0.5))) == [])
    }

    @Test func sharedKeysAreTheOnesAnotherCaptureUsesAtTheSameLocation() {
        var otherBucket = location
        otherBucket.bucket = "elsewhere"
        let others = [
            record(state: .uploaded(url: url, key: "same.png"), location: location),
            record(state: .uploaded(url: url, key: "moved.png"), location: otherBucket),
            record(state: .failed(message: "Upload cancelled."), location: location, pendingKey: "reserved.png"),
            record(state: .uploaded(url: url, key: "legacy.png")),
        ]
        #expect(CaptureDeletion.sharedKeys(["same.png", "moved.png", "reserved.png", "legacy.png", "mine.png"], at: location, with: others)
                == ["same.png", "reserved.png"])
        #expect(CaptureDeletion.sharedKeys(["same.png"], at: location, with: []) == [])
    }

    /// One line saying where the capture disappears from. Delete also removes the thumbnail.
    /// A file in the save folder is deleted for good, so the line names it next to the object.
    @Test func confirmationTextIsOneLine() {
        let storage = "Removes it from object storage and from history."
        let storageAndSaveFolder = "Removes it from object storage, your save folder and history."
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location)) == storageAndSaveFolder)
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploading(fraction: 0.2))) == storageAndSaveFolder)
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), fileURL: nil, location: location)) == storage)
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploading(fraction: 0.2), fileURL: URL(fileURLWithPath: "/tmp/p.png"), temporary: true)) == storage)
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "Upload cancelled."), fileURL: nil, location: location, pendingKey: "Qx12Zz.png")) == storage)
        #expect(CaptureDeletion.confirmationText(for: record(state: .none)) == "Removes it from your save folder and from history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "offline"), fileURL: URL(fileURLWithPath: "/tmp/p.png"), temporary: true))
                == "Removes it from history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "x"), fileURL: nil)) == "Removes it from history.")
    }

    /// A Phase 2 record does not know which bucket its object went to, so Delete leaves it.
    @Test func confirmationTextSaysWhenTheObjectStays() {
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png")))
                == "Removes it from your save folder and from history. The uploaded object stays in the bucket.")
    }

    @Test func alertTexts() {
        #expect(CaptureDeletion.confirmationMessage == "Delete this capture?")
        #expect(CaptureDeletion.storageFailureMessage(reason: "Server returned HTTP 403: AccessDenied: Access Denied")
                == "Couldn't delete it from storage: Server returned HTTP 403: AccessDenied: Access Denied")
        #expect(CaptureDeletion.storageFailureText == "Remove it from history anyway? The object stays in the bucket.")
    }
}
