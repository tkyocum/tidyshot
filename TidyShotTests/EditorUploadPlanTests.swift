import Foundation
import Testing
@testable import TidyShot

struct EditorUploadPlanTests {
    let here = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                              bucket: "snap.tky.io", usePathStyle: true)
    let elsewhere = ObjectLocation(endpoint: "https://s3.eu-west-1.amazonaws.com", region: "eu-west-1",
                                   bucket: "shots-eu", usePathStyle: false)
    let link = URL(string: "https://snap.tky.io/aB3dE9.png")!
    let key = "aB3dE9.png"
    let savedFile = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png")
    let pendingFile = URL(fileURLWithPath: "/Users/tim/Library/Containers/io.tky.tidyshot/Data/pending/Shot.png")

    let destinationChanged = "The destination changed, so this uploads as a new link."
    let sharedLink = "Another capture shares this link, so this uploads as a new link."
    let earlierStays = "The earlier upload stays in the bucket."

    /// A capture in the save folder in `state`, whose objects live at `location`.
    func record(_ state: CaptureRecord.UploadState, at location: ObjectLocation?) -> CaptureRecord {
        CaptureRecord(fileURL: savedFile, pixelWidth: 10, pixelHeight: 10, appName: nil,
                      uploadState: state, objectLocation: location)
    }

    /// Uploaded as `key` to `location`; nil is a capture uploaded before Phase 3.
    func uploaded(at location: ObjectLocation?) -> CaptureRecord {
        record(.uploaded(url: link, key: key), at: location)
    }

    /// An editor upload of `uploaded(at: location)` cut short by a quit or crash: `HistoryStore.load`
    /// turned `.uploading` into `.failed` and kept `priorUpload` (and, for Upload as New, the
    /// superseded old key).
    func interrupted(at location: ObjectLocation, isReplace: Bool) -> CaptureRecord {
        var capture = record(.failed(message: "Upload was interrupted."), at: location)
        capture.priorUpload = PriorUpload(url: link, key: key, location: location, isReplace: isReplace)
        if !isReplace {
            capture.supersededObjects = [ObjectRef(key: key, location: location)]
        }
        // What the local write that preceded the upload left: `applyLocalEdit` marks a record with a
        // link stale, and `linkURL` covers a link kept only in `priorUpload` (Task 14).
        capture.uploadIsStale = true
        return capture
    }

    func planned(_ capture: CaptureRecord, to location: ObjectLocation, others: [CaptureRecord] = [],
                 asNew: Bool = false) -> EditorUploadPlan.Plan {
        EditorUploadPlan.plan(record: capture, currentLocation: location, others: others, asNew: asNew)
    }

    @Test func refuseWhileUploading() {
        let uploading = record(.uploading(fraction: 0.4), at: here)
        #expect(planned(uploading, to: here) == .refuse("This capture is already uploading."))
        #expect(planned(uploading, to: here, asNew: true) == .refuse("This capture is already uploading."))
        // A refusal changes nothing.
        #expect(EditorUploadPlan.startingUpload(uploading, plan: .refuse("x")) == uploading)
    }

    @Test func neverUploadedIsNewObjectWithoutSupersede() {
        #expect(planned(record(.none, at: nil), to: here) == .newObject(supersede: nil, notice: nil))
        #expect(planned(record(.failed(message: "offline"), at: nil), to: here) == .newObject(supersede: nil, notice: nil))
        // A cancelled first upload reserved a key, but no link points at it.
        var cancelled = record(.failed(message: "Upload cancelled."), at: here)
        cancelled.pendingObjectKey = "Qx12Zz.png"
        #expect(planned(cancelled, to: here, asNew: true) == .newObject(supersede: nil, notice: nil))
    }

    @Test func sameLocationUnsharedIsReplace() {
        let other = record(.uploaded(url: URL(string: "https://snap.tky.io/other.png")!, key: "other.png"), at: here)
        #expect(planned(uploaded(at: here), to: here, others: [other]) == .replace(key: key))
        // The same key in another bucket is another object.
        #expect(planned(uploaded(at: here), to: here, others: [uploaded(at: elsewhere)]) == .replace(key: key))
    }

    @Test func asNewSupersedesOldKey() {
        #expect(planned(uploaded(at: here), to: here, asNew: true)
                == .newObject(supersede: ObjectRef(key: key, location: here), notice: nil))
    }

    @Test func destinationChangedSupersedesAtOldLocationWithNotice() {
        let expected = EditorUploadPlan.Plan.newObject(supersede: ObjectRef(key: key, location: here),
                                                       notice: destinationChanged)
        #expect(planned(uploaded(at: here), to: elsewhere) == expected)
        #expect(planned(uploaded(at: here), to: elsewhere, asNew: true) == expected)
    }

    @Test func sharedKeyIsNewObjectWithoutSupersede() {
        // Another capture got the same key from a template without {random} or {counter}.
        let twin = uploaded(at: here)
        let expected = EditorUploadPlan.Plan.newObject(supersede: nil, notice: sharedLink)
        #expect(planned(uploaded(at: here), to: here, others: [twin]) == expected)
        // Upload as New never deletes an object another capture links to.
        #expect(planned(uploaded(at: here), to: here, others: [twin], asNew: true) == expected)
    }

    @Test func prePhaseThreeIsNewObjectWithNotice() {
        let expected = EditorUploadPlan.Plan.newObject(supersede: nil, notice: earlierStays)
        #expect(planned(uploaded(at: nil), to: here) == expected)
        #expect(planned(uploaded(at: nil), to: here, asNew: true) == expected)
    }

    @Test func interruptedReplaceUploadFromEditorStillReplaces() {
        let replace = interrupted(at: here, isReplace: true)
        #expect(planned(replace, to: here) == .replace(key: key))
        #expect(planned(replace, to: elsewhere)
                == .newObject(supersede: ObjectRef(key: key, location: here), notice: destinationChanged))
        // An interrupted Upload as New, then Upload: the old key is the link again, so it is no
        // longer deleted as superseded.
        let asNew = interrupted(at: here, isReplace: false)
        #expect(planned(asNew, to: here) == .replace(key: key))
        let restarted = EditorUploadPlan.startingUpload(asNew, plan: .replace(key: key))
        #expect(restarted.supersededObjects.isEmpty)
        #expect(restarted.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: true))
    }

    @Test func retryOfInterruptedReplaceReusesKey() {
        let replace = interrupted(at: here, isReplace: true)
        let policy = EditorUploadPlan.retryPolicy(record: replace, currentLocation: here, others: [])
        #expect(policy == .fixed(key))
        #expect(EditorUploadPlan.startingRetry(replace, policy: policy) == replace)
        // A key another capture shares is never re-PUT.
        #expect(EditorUploadPlan.retryPolicy(record: replace, currentLocation: here, others: [uploaded(at: here)])
                == .template(supersede: nil))
    }

    @Test func retryOfInterruptedReplaceAfterDestinationChangeSupersedes() {
        let replace = interrupted(at: here, isReplace: true)
        let old = ObjectRef(key: key, location: here)
        let policy = EditorUploadPlan.retryPolicy(record: replace, currentLocation: elsewhere, others: [])
        #expect(policy == .template(supersede: old))
        let started = EditorUploadPlan.startingRetry(replace, policy: policy)
        #expect(started.supersededObjects == [old])
        // A new link now: success posts no cache note, and a later retry stays a template upload.
        #expect(started.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: false))
        #expect(EditorUploadPlan.retryPolicy(record: started, currentLocation: here, others: []) == .template(supersede: nil))
    }

    @Test func retryWithoutPriorUploadUsesTemplate() {
        let failed = record(.failed(message: "offline"), at: nil)
        #expect(EditorUploadPlan.retryPolicy(record: failed, currentLocation: here, others: []) == .template(supersede: nil))
        #expect(EditorUploadPlan.startingRetry(failed, policy: .template(supersede: nil)) == failed)
        // An interrupted Upload as New already lists its old key as superseded.
        let asNew = interrupted(at: here, isReplace: false)
        let policy = EditorUploadPlan.retryPolicy(record: asNew, currentLocation: here, others: [])
        #expect(policy == .template(supersede: nil))
        #expect(EditorUploadPlan.startingRetry(asNew, policy: policy) == asNew)
    }

    @Test func failureRestoresPriorUploadAndDropsSupersededRef() {
        var original = uploaded(at: here)
        original.uploadIsStale = true                                // set by the local write
        let older = ObjectRef(key: "older.png", location: elsewhere) // a superseded delete that failed earlier
        original.supersededObjects = [older]
        let started = EditorUploadPlan.startingUpload(original, plan: planned(original, to: here, asNew: true))
        #expect(started.supersededObjects == [older, ObjectRef(key: key, location: here)])
        // The old object is live again, so the record is exactly what it was.
        #expect(EditorUploadPlan.applyingFailure(to: started, message: "403 Forbidden") == original)
        #expect(EditorUploadPlan.failedReplaceMessage == "Upload failed. The link still shows the earlier image.")

        // A cancelled attempt at a new destination reserved a key there, then a retry failed. The
        // reserved key stays listed at its own location, so Delete still removes it.
        var cancelled = EditorUploadPlan.startingUpload(original, plan: planned(original, to: elsewhere))
        cancelled.pendingObjectKey = "Qx12Zz.png"
        cancelled.objectLocation = elsewhere
        let restored = EditorUploadPlan.applyingFailure(to: cancelled, message: "offline")
        #expect(restored.uploadState == .uploaded(url: link, key: key))
        #expect(restored.objectLocation == here)
        #expect(restored.pendingObjectKey == nil)
        #expect(restored.supersededObjects == [older, ObjectRef(key: "Qx12Zz.png", location: elsewhere)])
        #expect(restored.priorUpload == nil)
    }

    @Test func failureWithoutPriorUploadMarksFailed() {
        let first = EditorUploadPlan.startingUpload(record(.none, at: nil), plan: .newObject(supersede: nil, notice: nil))
        #expect(first.priorUpload == nil)
        #expect(EditorUploadPlan.applyingFailure(to: first, message: "offline").uploadState == .failed(message: "offline"))
        // A pre-Phase-3 link has no location to return to, so it fails as today.
        let legacy = EditorUploadPlan.startingUpload(uploaded(at: nil), plan: .newObject(supersede: nil, notice: earlierStays))
        #expect(legacy.priorUpload == nil)
        #expect(EditorUploadPlan.applyingFailure(to: legacy, message: "offline").uploadState == .failed(message: "offline"))
    }

    @Test func successClearsPriorUploadAndStaleFlag() {
        let old = ObjectRef(key: key, location: here)
        var done = EditorUploadPlan.startingUpload(interrupted(at: here, isReplace: false),
                                                   plan: .newObject(supersede: old, notice: nil))
        // As handle(.uploaded) sets it before applyingSuccess.
        done.uploadState = .uploaded(url: URL(string: "https://snap.tky.io/Qx12Zz.png")!, key: "Qx12Zz.png")
        let settled = EditorUploadPlan.applyingSuccess(to: done)
        #expect(settled.priorUpload == nil)
        #expect(!settled.uploadIsStale)
        #expect(settled.uploadState == done.uploadState)
        // deleteSupersededObjects deletes the old object afterwards and drops the ref.
        #expect(settled.supersededObjects == [old])
    }

    @Test func failedUploadOnlyReplaceKeepsEditedPendingFileAndMarksStale() {
        // An uploaded upload-only capture has no file. Upload wrote the edit to pending/<id>.png
        // first, and that local write marked the upload stale.
        var uploadOnly = CaptureRecord(fileURL: nil, pixelWidth: 10, pixelHeight: 10, appName: nil,
                                       uploadState: .uploaded(url: link, key: key), objectLocation: here)
        uploadOnly.fileURL = pendingFile
        uploadOnly.fileIsTemporary = true
        uploadOnly.uploadIsStale = true
        let replace = planned(uploadOnly, to: here)
        #expect(replace == .replace(key: key))
        let failed = EditorUploadPlan.applyingFailure(to: EditorUploadPlan.startingUpload(uploadOnly, plan: replace),
                                                      message: "403 Forbidden")
        #expect(failed.uploadState == .uploaded(url: link, key: key))
        #expect(failed.fileURL == pendingFile)
        #expect(failed.fileIsTemporary)
        #expect(failed.uploadIsStale)
        #expect(failed.keepsUnuploadedEdit) // retention never prunes it
        #expect(EditorSaveTarget.uploadedCopyNotice(for: failed)
                == "The uploaded copy still shows the original. Upload to replace it.")
        // The next Upload from the editor replaces the object.
        #expect(planned(failed, to: here) == .replace(key: key))
    }

    @Test func interruptedReplaceThatFailsAgainStaysStaleAndRetained() {
        // Upload-only capture: killed mid-replace, so it is `.failed` with the link only in
        // `priorUpload` (`uploadedURL` is nil), and its pending file holds the edit.
        var interruptedReplace = interrupted(at: here, isReplace: true)
        interruptedReplace.fileURL = pendingFile
        interruptedReplace.fileIsTemporary = true
        #expect(interruptedReplace.uploadedURL == nil)
        #expect(interruptedReplace.linkURL == link)
        // The user presses Save or Upload again and the replace fails again.
        let plan = planned(interruptedReplace, to: here)
        #expect(plan == .replace(key: key))
        let failed = EditorUploadPlan.applyingFailure(
            to: EditorUploadPlan.startingUpload(interruptedReplace, plan: plan), message: "403 Forbidden")
        #expect(failed.uploadState == .uploaded(url: link, key: key))
        #expect(failed.uploadIsStale)
        #expect(failed.keepsUnuploadedEdit) // retention never prunes the only copy of the edit
        #expect(EditorSaveTarget.uploadedCopyNotice(for: failed)
                == "The uploaded copy still shows the original. Upload to replace it.")
    }

    @Test func startingUploadSetsUploadingStateAndPriorUpload() {
        let original = uploaded(at: here)
        let replace = EditorUploadPlan.startingUpload(original, plan: .replace(key: key))
        #expect(replace.uploadState == .uploading(fraction: 0))
        #expect(replace.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: true))
        #expect(replace.supersededObjects.isEmpty)
        #expect(replace.linkURL == link) // Copy Link keeps working while it runs

        let old = ObjectRef(key: key, location: here)
        let asNew = EditorUploadPlan.startingUpload(original, plan: .newObject(supersede: old, notice: nil))
        #expect(asNew.uploadState == .uploading(fraction: 0))
        #expect(asNew.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: false))
        #expect(asNew.supersededObjects == [old])
        // Starting again never lists the old object twice.
        #expect(EditorUploadPlan.startingUpload(asNew, plan: .newObject(supersede: old, notice: nil)).supersededObjects == [old])

        let first = EditorUploadPlan.startingUpload(record(.none, at: nil), plan: .newObject(supersede: nil, notice: nil))
        #expect(first.uploadState == .uploading(fraction: 0))
        #expect(first.priorUpload == nil)
        #expect(first.supersededObjects.isEmpty)
    }

    @Test func cacheNoteOnlyOnFirstSameKeyReplace() {
        let replace = PriorUpload(url: link, key: key, location: here, isReplace: true)
        #expect(EditorUploadPlan.cacheNote == "Replaced. Copies opened before now may stay cached for a while.")
        #expect(EditorUploadPlan.shouldPostCacheNote(prior: replace, uploadedKey: key, at: here, alreadyPosted: false))
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: replace, uploadedKey: key, at: here, alreadyPosted: true))
        // A new link has nothing cached under it: a first upload, Upload as New, or a fallback.
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: nil, uploadedKey: key, at: here, alreadyPosted: false))
        let asNew = PriorUpload(url: link, key: key, location: here, isReplace: false)
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: asNew, uploadedKey: "Qx12Zz.png", at: here, alreadyPosted: false))
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: replace, uploadedKey: "Qx12Zz.png", at: elsewhere, alreadyPosted: false))
    }
}
