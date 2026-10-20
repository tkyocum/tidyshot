import Foundation

/// The pure parts of deleting a capture, shared by the overlay and the gallery: which objects to
/// remove from the bucket, which of them another capture still needs, and what the confirmation
/// says. `AppCoordinator.deleteCapture` does the I/O.
nonisolated enum CaptureDeletion {
    /// The second paragraph of every confirmation, explaining the middle button.
    static let historyOnlyNote = "Remove from History Only removes just the entry and keeps the uploaded object and any file in your save folder."

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

    /// The informative text of the one confirmation, naming exactly what Delete removes. A record
    /// without an `objectLocation` (uploaded before Phase 3) keeps its object, and the text says so.
    static func confirmationText(for record: CaptureRecord) -> String {
        let knowsLocation = record.objectLocation != nil
        var parts: [String] = []
        if let url = record.uploadedURL, knowsLocation {
            parts.append("the uploaded object \(url.absoluteString)")
        } else if record.isUploading {
            parts.append("the upload in progress")
        } else if record.pendingObjectKey != nil, knowsLocation {
            parts.append("any object the cancelled upload left in the bucket")
        }
        if let fileURL = record.fileURL {
            parts.append(record.fileIsTemporary ? "the temporary file" : "the file \(fileURL.lastPathComponent)")
        }
        parts.append("its entry in Recent Captures")
        let list: String
        switch parts.count {
        case 1: list = parts[0]
        case 2: list = "\(parts[0]) and \(parts[1])"
        default: list = parts.dropLast().joined(separator: ", ") + ", and " + parts[parts.count - 1]
        }
        var text = "Delete removes \(list). It cannot be undone."
        if let url = record.uploadedURL, !knowsLocation {
            text += " The uploaded object \(url.absoluteString) stays in the bucket: it was uploaded before TidyShot recorded where objects go."
        }
        return text + " " + historyOnlyNote
    }
}
