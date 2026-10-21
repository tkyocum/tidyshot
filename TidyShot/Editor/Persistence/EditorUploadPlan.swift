import Foundation

/// The decisions behind Upload and Upload as New in the editor, and behind a retry of an upload
/// the editor started: which key the PUT goes to, which old object goes after success, and what
/// the record says while the upload runs and after it ends. `AppCoordinator` does the I/O.
nonisolated enum EditorUploadPlan {
    /// What an editor upload does.
    enum Plan: Equatable, Sendable {
        /// PUT the edit over the link's own key, so the URL stays.
        case replace(key: String)
        /// Upload under a new template key. `supersede` is the old object, deleted after success;
        /// `notice` says why the link changes.
        case newObject(supersede: ObjectRef?, notice: String?)
        /// Upload nothing; the reason is posted as "Not uploaded".
        case refuse(String)
    }

    /// How a retry (the overlay's Retry, or Retry Failed Uploads) uploads.
    enum RetryPolicy: Equatable, Sendable {
        /// Re-PUT the key an interrupted or failed replace was writing, so the URL stays.
        case fixed(String)
        /// A new template key, as for any retry. `supersede` is an old object to delete after success.
        case template(supersede: ObjectRef?)
    }

    static let uploadingReason = "This capture is already uploading."
    static let destinationChangedNotice = "The destination changed, so this uploads as a new link."
    static let sharedKeyNotice = "Another capture shares this link, so this uploads as a new link."
    static let legacyNotice = "The earlier upload stays in the bucket."
    /// Posted, titled "Not uploaded", when the upload of a record that has a link fails.
    static let failedReplaceMessage = "Upload failed. The link still shows the earlier image."
    /// Posted once per launch on the first successful same-key replace, whatever Show
    /// notification says: a CDN or a browser may still serve the original.
    static let cacheNote = "Replaced. Copies opened before now may stay cached for a while."

    /// The record's link: its uploaded key where it went, or else the link that an editor upload
    /// in flight or interrupted keeps in `priorUpload`. `location` is nil for a capture uploaded
    /// before Phase 3.
    private static func link(of record: CaptureRecord) -> (url: URL, key: String, location: ObjectLocation?)? {
        if case .uploaded(let url, let key) = record.uploadState {
            return (url, key, record.objectLocation)
        }
        if let prior = record.priorUpload {
            return (prior.url, prior.key, prior.location)
        }
        return nil
    }

    /// The first rule that applies wins:
    /// 1. uploading: refuse;
    /// 2. no link: a plain first upload;
    /// 3. a link with no location (before Phase 3): a new object, and the old one stays;
    /// 4. another capture points at the key: a new object, and the old one stays;
    /// 5. the destination moved: a new object, and the old one is deleted at its own location;
    /// 6. Upload as New: a new object, and the old one is deleted;
    /// 7. otherwise, replace the key.
    /// `currentLocation` is where the upload lane writes; `others` is every other record.
    static func plan(record: CaptureRecord, currentLocation: ObjectLocation, others: [CaptureRecord], asNew: Bool) -> Plan {
        if record.isUploading {
            return .refuse(uploadingReason)
        }
        guard let link = link(of: record) else {
            return .newObject(supersede: nil, notice: nil)
        }
        guard let location = link.location else {
            return .newObject(supersede: nil, notice: legacyNotice)
        }
        if !CaptureDeletion.sharedKeys([link.key], at: location, with: others).isEmpty {
            return .newObject(supersede: nil, notice: sharedKeyNotice)
        }
        let old = ObjectRef(key: link.key, location: location)
        if location != currentLocation {
            return .newObject(supersede: old, notice: destinationChangedNotice)
        }
        if asNew {
            return .newObject(supersede: old, notice: nil)
        }
        return .replace(key: link.key)
    }

    /// A replace in `priorUpload` whose key is unshared and still at `currentLocation` is re-PUT to
    /// the same key. A replace whose destination moved supersedes its old key, unless another
    /// capture shares it. Everything else is a plain template retry.
    static func retryPolicy(record: CaptureRecord, currentLocation: ObjectLocation, others: [CaptureRecord]) -> RetryPolicy {
        guard let prior = record.priorUpload, prior.isReplace else {
            return .template(supersede: nil)
        }
        if !CaptureDeletion.sharedKeys([prior.key], at: prior.location, with: others).isEmpty {
            return .template(supersede: nil)
        }
        if prior.location == currentLocation {
            return .fixed(prior.key)
        }
        return .template(supersede: ObjectRef(key: prior.key, location: prior.location))
    }

    /// The one `history.update` before an editor upload starts: `.uploading(0)`, the link kept in
    /// `priorUpload` (when it has a location), and the superseded old object. A replace takes its
    /// key off the superseded list, because that key is the live link again (after an interrupted
    /// Upload as New, say). A refusal returns the record unchanged.
    static func startingUpload(_ record: CaptureRecord, plan: Plan) -> CaptureRecord {
        var next = record
        let prior = link(of: record).flatMap { link in
            link.location.map { PriorUpload(url: link.url, key: link.key, location: $0, isReplace: false) }
        }
        switch plan {
        case .refuse:
            return record
        case .replace(let key):
            if var prior {
                prior.isReplace = true
                next.priorUpload = prior
                next.supersededObjects.removeAll { $0 == ObjectRef(key: key, location: prior.location) }
            }
        case .newObject(let supersede, _):
            next.priorUpload = prior
            if let supersede, !next.supersededObjects.contains(supersede) {
                next.supersededObjects.append(supersede)
            }
        }
        next.uploadState = .uploading(fraction: 0)
        return next
    }

    /// The record before a retry starts. A fixed retry keeps its key off the superseded list. A
    /// template retry of a replace is a new link from now on (so its success posts no cache note
    /// and its next retry is a template one too), and lists the superseded object it was given.
    static func startingRetry(_ record: CaptureRecord, policy: RetryPolicy) -> CaptureRecord {
        var next = record
        switch policy {
        case .fixed(let key):
            if let prior = record.priorUpload {
                next.supersededObjects.removeAll { $0 == ObjectRef(key: key, location: prior.location) }
            }
        case .template(let supersede):
            next.priorUpload?.isReplace = false
            if let supersede, !next.supersededObjects.contains(supersede) {
                next.supersededObjects.append(supersede)
            }
        }
        return next
    }

    /// After `.uploaded`: the object holds the edit, so the earlier link is settled and the
    /// uploaded copy is current. The superseded list is left for `deleteSupersededObjects`.
    static func applyingSuccess(to record: CaptureRecord) -> CaptureRecord {
        var next = record
        next.priorUpload = nil
        next.uploadIsStale = false
        return next
    }

    /// After `.failed`. With a `priorUpload` the old object is untouched, so the record returns
    /// to `.uploaded` at the prior location, keeps its file and `uploadIsStale`, and drops the
    /// superseded ref the upload added. A key that a cancelled attempt reserved at another
    /// location moves to the superseded list, so it is still deleted there. Without a
    /// `priorUpload` the upload fails as any upload does.
    static func applyingFailure(to record: CaptureRecord, message: String) -> CaptureRecord {
        var next = record
        guard let prior = record.priorUpload else {
            next.uploadState = .failed(message: message)
            return next
        }
        if let reserved = next.pendingObjectKey, let reservedAt = next.objectLocation, reservedAt != prior.location {
            let orphan = ObjectRef(key: reserved, location: reservedAt)
            if !next.supersededObjects.contains(orphan) {
                next.supersededObjects.append(orphan)
            }
            next.pendingObjectKey = nil
        }
        next.uploadState = .uploaded(url: prior.url, key: prior.key)
        next.objectLocation = prior.location
        next.supersededObjects.removeAll { $0 == ObjectRef(key: prior.key, location: prior.location) }
        next.priorUpload = nil
        return next
    }

    /// What `AppCoordinator.deleteSupersededObjects` does with a superseded object.
    enum SupersededStep: Equatable, Sendable {
        /// DELETE it (unless another capture shares its key), then drop it from the list.
        case delete
        /// Drop it from the list without a DELETE: it is the live link.
        case drop
        /// Leave it listed and untouched.
        case keep
    }

    /// The step for `ref` on `record` as the record stands now. While an upload runs, nothing is
    /// deleted: its prior link sits on the list (an Upload as New lists it there) but is still the
    /// link, and that upload's own `.uploaded` runs the clean-up again. The link kept in
    /// `priorUpload` is never deleted either.
    static func supersededStep(for ref: ObjectRef, of record: CaptureRecord) -> SupersededStep {
        if record.isUploading { return .keep }
        if let prior = record.priorUpload, ref == ObjectRef(key: prior.key, location: prior.location) { return .keep }
        if let key = record.uploadedKey, let location = record.objectLocation,
           ref == ObjectRef(key: key, location: location) { return .drop }
        return .delete
    }

    /// True for the first upload in this launch that replaced its own key: `prior` was a replace
    /// of `uploadedKey` at `location`.
    static func shouldPostCacheNote(prior: PriorUpload?, uploadedKey: String, at location: ObjectLocation,
                                    alreadyPosted: Bool) -> Bool {
        guard !alreadyPosted, let prior, prior.isReplace else { return false }
        return prior.key == uploadedKey && prior.location == location
    }
}

/// What an editor Upload (⌘U, ⌥⌘U) did, as the coordinator reports it to the editor.
nonisolated struct EditorUploadOutcome: Equatable, Sendable {
    /// The edit was written to the record's file (or a new pending file) before the upload.
    var wroteLocally: Bool
    /// The upload job was handed to the queue; its link reaches the clipboard on `.uploaded`.
    var enqueued: Bool

    /// Refused before anything was written (not configured, busy, deleted, encode failed).
    static let refused = EditorUploadOutcome(wroteLocally: false, enqueued: false)

    /// A local write is what makes the document saved; an upload alone can still fail.
    var marksSaved: Bool { wroteLocally }

    /// The window closes once the upload is enqueued: the edit is saved locally and on its way to
    /// the bucket, and its link reaches the clipboard. It stays open when the upload
    /// was refused (its notification says why), or when the document was edited meanwhile, so the
    /// newer edit is not lost.
    func closesWindow(documentUnchanged: Bool) -> Bool {
        enqueued && documentUnchanged
    }
}
