import Foundation

/// The pure parts of deleting a capture, shared by the overlay and Recent Captures: which objects
/// to remove from the bucket, which of them another capture still needs, and what the alerts say.
/// `AppCoordinator.deleteCapture` does the I/O.
nonisolated enum CaptureDeletion {
    /// The first alert's message. Its buttons are Delete and Cancel.
    static let confirmationMessage = "Delete this capture?"
    /// The second alert's informative text, shown only after the storage DELETE failed. Its buttons
    /// are Remove and Cancel.
    static let storageFailureText = "Remove it from history anyway? The object stays in the bucket."
    /// The second alert's informative text when the file in the save folder could not be removed
    /// (any object this capture alone owned has been deleted by then; shared keys and pre-Phase 3
    /// records keep theirs). Its buttons are Remove and Cancel.
    static let fileFailureText = "Remove it from history anyway? The file stays where it is."

    /// The keys at `record.objectLocation` that may hold the capture, in order and without
    /// duplicates: the key it was uploaded under, and the key a cancelled upload had reserved (its
    /// PUT may have completed on the server as it was cancelled). `objects(for:)` adds the objects
    /// the record names elsewhere.
    static func objectKeys(for record: CaptureRecord) -> [String] {
        var keys: [String] = []
        for key in [record.uploadedKey, record.pendingObjectKey].compactMap({ $0 }) where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    /// Every object Delete removes for `record`, in order and without duplicates, each at its own
    /// location:
    /// - `objectKeys(for:)` at `objectLocation` (none without a location: a record from before
    ///   Phase 3 does not know its bucket);
    /// - the prior upload at its location, so the link's object is found while an editor upload
    ///   runs over it and after a quit or crash interrupted that upload;
    /// - the superseded objects, old keys left by an Upload as New or by an upload after the
    ///   destination changed.
    static func objects(for record: CaptureRecord) -> [ObjectRef] {
        var candidates: [ObjectRef] = []
        if let location = record.objectLocation {
            candidates += objectKeys(for: record).map { ObjectRef(key: $0, location: location) }
        }
        if let prior = record.priorUpload {
            candidates.append(ObjectRef(key: prior.key, location: prior.location))
        }
        candidates += record.supersededObjects
        var objects: [ObjectRef] = []
        for object in candidates where !objects.contains(object) {
            objects.append(object)
        }
        return objects
    }

    /// `objects` grouped by location, in order of first appearance, with each group's keys in
    /// their original order. Delete signs one destination per group.
    static func grouped(_ objects: [ObjectRef]) -> [(location: ObjectLocation, keys: [String])] {
        var groups: [(location: ObjectLocation, keys: [String])] = []
        for object in objects {
            if let index = groups.firstIndex(where: { $0.location == object.location }) {
                groups[index].keys.append(object.key)
            } else {
                groups.append((location: object.location, keys: [object.key]))
            }
        }
        return groups
    }

    /// The keys among `keys` that a record in `others` also points at, at `location`, through any
    /// object `objects(for:)` lists for it: its uploaded or reserved key, its prior upload, or a
    /// superseded object. A template without `{random}` or `{counter}` can give two captures the
    /// same key when HEAD cannot see the first object, and deleting it would break the other
    /// capture's URL. A capture whose replace is running or was interrupted still links to its
    /// prior key.
    static func sharedKeys(_ keys: [String], at location: ObjectLocation, with others: [CaptureRecord]) -> [String] {
        let claimed = Set(others.flatMap { objects(for: $0) })
        return keys.filter { claimed.contains(ObjectRef(key: $0, location: location)) }
    }

    /// The first alert's one line: where the capture disappears from. Delete also removes the
    /// thumbnail. A file in the save folder is deleted for good (not moved to the Trash), so the
    /// line names the save folder whenever the record has a file there, also next to object
    /// storage (the default Upload mode keeps both). A record uploaded before Phase 3 has no
    /// `objectLocation`, so its own object cannot be deleted, and the line says it stays. A prior
    /// upload or a superseded object names its own location, so either one counts as storage.
    static func confirmationText(for record: CaptureRecord) -> String {
        let inSaveFolder = record.fileURL != nil && !record.fileIsTemporary
        if record.isUploading || !objects(for: record).isEmpty {
            return inSaveFolder ? "Removes it from object storage, your save folder and history."
                                : "Removes it from object storage and from history."
        }
        var text = inSaveFolder ? "Removes it from your save folder and from history." : "Removes it from history."
        if record.uploadedURL != nil {
            text += " The uploaded object stays in the bucket."
        }
        return text
    }

    /// The second alert's message, after the storage DELETE failed with `reason`.
    static func storageFailureMessage(reason: String) -> String {
        "Couldn't delete it from storage: \(reason)"
    }

    /// The second alert's message, after the file in the save folder could not be removed with
    /// `reason` (it lies outside the current save folder, or the folder's bookmark no longer resolves).
    static func fileFailureMessage(reason: String) -> String {
        "Couldn't delete the file: \(reason)"
    }
}
