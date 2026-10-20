import Foundation

/// The pure parts of deleting a capture, shared by the overlay and Recent Captures: which objects
/// to remove from the bucket, which of them another capture still needs, and what the two alerts
/// say. `AppCoordinator.deleteCapture` does the I/O.
nonisolated enum CaptureDeletion {
    /// The first alert's message. Its buttons are Delete and Cancel.
    static let confirmationMessage = "Delete this capture?"
    /// The second alert's informative text, shown only after the storage DELETE failed. Its buttons
    /// are Remove and Cancel.
    static let storageFailureText = "Remove it from history anyway? The object stays in the bucket."

    /// Object keys that may hold the capture, in order and without duplicates: the key it was
    /// uploaded under, and the key a cancelled upload had reserved (its PUT may have completed
    /// on the server as it was cancelled). Both live at `record.objectLocation`.
    static func objectKeys(for record: CaptureRecord) -> [String] {
        var keys: [String] = []
        for key in [record.uploadedKey, record.pendingObjectKey].compactMap({ $0 }) where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    /// The keys among `keys` that a record in `others` also points at, at the same location.
    /// A template without `{random}` or `{counter}` can give two captures the same key when HEAD
    /// cannot see the first object, and deleting it would break the other capture's URL.
    static func sharedKeys(_ keys: [String], at location: ObjectLocation, with others: [CaptureRecord]) -> [String] {
        keys.filter { key in
            others.contains { other in
                other.objectLocation == location && (other.uploadedKey == key || other.pendingObjectKey == key)
            }
        }
    }

    /// The first alert's one line: where the capture disappears from. Delete also removes the
    /// thumbnail, and the local file when the object is in storage too. A record uploaded before
    /// Phase 3 has no `objectLocation`, so its object cannot be deleted, and the line says it stays.
    static func confirmationText(for record: CaptureRecord) -> String {
        if record.isUploading || (record.objectLocation != nil && !objectKeys(for: record).isEmpty) {
            return "Removes it from object storage and from history."
        }
        let inSaveFolder = record.fileURL != nil && !record.fileIsTemporary
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
}
