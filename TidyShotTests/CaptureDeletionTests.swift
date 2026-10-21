import Foundation
import Testing
@testable import TidyShot

struct CaptureDeletionTests {
    let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)
    let elsewhere = ObjectLocation(endpoint: "https://abc.r2.cloudflarestorage.com", region: "auto",
                                   bucket: "shots", usePathStyle: false)

    func record(state: CaptureRecord.UploadState, fileURL: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                temporary: Bool = false, location: ObjectLocation? = nil, pendingKey: String? = nil,
                superseded: [ObjectRef] = [], prior: PriorUpload? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: "Safari",
                      uploadState: state, objectLocation: location, pendingObjectKey: pendingKey,
                      supersededObjects: superseded, priorUpload: prior)
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
        // A location but no key (a failed upload that never reserved one): nothing in storage.
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "offline"), location: location))
                == "Removes it from your save folder and from history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "offline"), fileURL: nil, location: location))
                == "Removes it from history.")
    }

    /// A Phase 2 record does not know which bucket its object went to, so Delete leaves it.
    @Test func confirmationTextSaysWhenTheObjectStays() {
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png")))
                == "Removes it from your save folder and from history. The uploaded object stays in the bucket.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), fileURL: nil))
                == "Removes it from history. The uploaded object stays in the bucket.")
    }

    @Test func alertTexts() {
        #expect(CaptureDeletion.confirmationMessage == "Delete this capture?")
        #expect(CaptureDeletion.storageFailureMessage(reason: "Server returned HTTP 403: AccessDenied: Access Denied")
                == "Couldn't delete it from storage: Server returned HTTP 403: AccessDenied: Access Denied")
        #expect(CaptureDeletion.storageFailureText == "Remove it from history anyway? The object stays in the bucket.")
        #expect(CaptureDeletion.fileFailureMessage(reason: "No save folder is set, so TidyShot cannot reach this file.")
                == "Couldn't delete the file: No save folder is set, so TidyShot cannot reach this file.")
        #expect(CaptureDeletion.fileFailureText == "Remove it from history anyway? The file stays where it is.")
    }

    /// An Upload as New, or an upload after the destination changed, leaves the old key behind at
    /// its own location. Delete removes it there, after the record's own keys, one location at a time.
    @Test func objectsIncludeSupersededAtTheirLocations() {
        let uploaded = record(state: .uploaded(url: url, key: "new.png"), location: location,
                              superseded: [ObjectRef(key: "old.png", location: elsewhere),
                                           ObjectRef(key: "older.png", location: location)])
        let objects = CaptureDeletion.objects(for: uploaded)
        #expect(objects == [ObjectRef(key: "new.png", location: location),
                            ObjectRef(key: "old.png", location: elsewhere),
                            ObjectRef(key: "older.png", location: location)])

        let groups = CaptureDeletion.grouped(objects)
        #expect(groups.map { $0.location } == [location, elsewhere])
        #expect(groups.map { $0.keys } == [["new.png", "older.png"], ["old.png"]])
        #expect(CaptureDeletion.grouped([]).isEmpty)
    }

    @Test func objectsDeduplicated() {
        let ref = ObjectRef(key: "aB3dE9.png", location: location)
        // A replace cancelled by Delete: the reserved key, the prior key and a superseded ref are one object.
        let replaced = record(state: .failed(message: "Upload cancelled."), location: location, pendingKey: "aB3dE9.png",
                              superseded: [ref, ref],
                              prior: PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: true))
        #expect(CaptureDeletion.objects(for: replaced) == [ref])

        // The same key in another bucket is another object.
        let moved = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location,
                           superseded: [ObjectRef(key: "aB3dE9.png", location: elsewhere)])
        #expect(CaptureDeletion.objects(for: moved) == [ref, ObjectRef(key: "aB3dE9.png", location: elsewhere)])
    }

    /// A superseded object whose DELETE failed is still in storage, so the alert says so even when
    /// the record has no key of its own.
    @Test func confirmationMentionsStorageForSupersededOnly() {
        let left = [ObjectRef(key: "old.png", location: elsewhere)]
        #expect(CaptureDeletion.confirmationText(for: record(state: .none, superseded: left))
                == "Removes it from object storage, your save folder and history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "offline"), fileURL: nil, superseded: left))
                == "Removes it from object storage and from history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .none)) == "Removes it from your save folder and from history.")
    }

    /// While a replace runs, and after a quit or crash interrupted it, the link's key lives only in
    /// `priorUpload`. Delete finds it at the prior upload's own location, which need not be
    /// `objectLocation`.
    @Test func objectsIncludePriorUploadAtItsLocation() {
        let replace = PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: true)
        let inFlight = record(state: .uploading(fraction: 0.3), location: location, prior: replace)
        #expect(CaptureDeletion.objects(for: inFlight) == [ObjectRef(key: "aB3dE9.png", location: location)])

        let interrupted = record(state: .failed(message: "Upload was interrupted."), fileURL: nil, location: location, prior: replace)
        #expect(CaptureDeletion.objects(for: interrupted) == [ObjectRef(key: "aB3dE9.png", location: location)])
        #expect(CaptureDeletion.confirmationText(for: interrupted) == "Removes it from object storage and from history.")

        // An Upload as New to another bucket, cancelled by Delete: the reserved key is at the new
        // location, the link's key at the old one.
        let cancelled = record(state: .failed(message: "Upload cancelled."), location: elsewhere, pendingKey: "Qx12Zz.png",
                               prior: PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: false))
        #expect(CaptureDeletion.objects(for: cancelled) == [ObjectRef(key: "Qx12Zz.png", location: elsewhere),
                                                            ObjectRef(key: "aB3dE9.png", location: location)])
    }

    /// Another capture still links to a key through its prior upload (its replace is running or was
    /// interrupted) or still owns it as a superseded object. Deleting this capture keeps that object.
    @Test func sharedKeysSeeAnotherRecordsPriorUpload() {
        let others = [
            record(state: .uploading(fraction: 0.5), location: location,
                   prior: PriorUpload(url: url, key: "linked.png", location: location, isReplace: true)),
            record(state: .uploaded(url: url, key: "fresh.png"), location: location,
                   superseded: [ObjectRef(key: "old.png", location: location)]),
            record(state: .failed(message: "Upload was interrupted."),
                   prior: PriorUpload(url: url, key: "moved.png", location: elsewhere, isReplace: false)),
        ]
        #expect(CaptureDeletion.sharedKeys(["linked.png", "old.png", "moved.png", "mine.png"], at: location, with: others)
                == ["linked.png", "old.png"])
        #expect(CaptureDeletion.sharedKeys(["moved.png", "linked.png"], at: elsewhere, with: others) == ["moved.png"])
    }
}
