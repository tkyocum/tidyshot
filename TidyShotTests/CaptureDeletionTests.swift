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

    @Test func confirmationTextNamesWhatIsRemoved() {
        let note = " " + CaptureDeletion.historyOnlyNote
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location))
                == "Delete removes the uploaded object https://snap.tky.io/aB3dE9.png, the file Shot.png, and its entry in Recent Captures. It cannot be undone." + note)
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), fileURL: nil, location: location))
                == "Delete removes the uploaded object https://snap.tky.io/aB3dE9.png and its entry in Recent Captures. It cannot be undone." + note)
        #expect(CaptureDeletion.confirmationText(for: record(state: .none))
                == "Delete removes the file Shot.png and its entry in Recent Captures. It cannot be undone." + note)
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploading(fraction: 0.2), fileURL: URL(fileURLWithPath: "/tmp/p.png"), temporary: true))
                == "Delete removes the upload in progress, the temporary file, and its entry in Recent Captures. It cannot be undone." + note)
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "Upload cancelled."), fileURL: nil, location: location, pendingKey: "Qx12Zz.png"))
                == "Delete removes any object the cancelled upload left in the bucket and its entry in Recent Captures. It cannot be undone." + note)
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "x"), fileURL: nil))
                == "Delete removes its entry in Recent Captures. It cannot be undone." + note)
    }

    /// A Phase 2 record does not know which bucket its object went to, so Delete leaves it.
    @Test func confirmationTextSaysWhenTheObjectStays() {
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png")))
                == "Delete removes the file Shot.png and its entry in Recent Captures. It cannot be undone. The uploaded object https://snap.tky.io/aB3dE9.png stays in the bucket: it was uploaded before TidyShot recorded where objects go. "
                + CaptureDeletion.historyOnlyNote)
    }
}
