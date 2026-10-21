import Foundation

/// Where ⌘S writes an edit, decided from the record and the save folder as they are now. The
/// coordinator asks again at write time, so a folder changed in Settings or a record changed by an
/// upload never sends the bytes to the wrong file.
nonisolated enum EditorSaveTarget {
    enum Plan: Equatable, Sendable {
        /// Overwrite the file in the save folder, under that folder's security scope.
        case saveFolderFile(URL, folder: URL)
        /// Overwrite `pending/<id>.png` in place, so a later retry uploads the edit.
        case pendingFile(URL)
        /// Save is off, for this reason (the window subtitle, and the body of `Not saved`).
        case unavailable(String)
    }

    static let noFileReason = "This capture has no local file to save over."
    static let noFolderReason = "No save folder is set, so the file is not saved over."
    static let outsideFolderReason = "The file is outside the current save folder, so it is not saved over."
    static let uploadedCopyStaleNotice = "The uploaded copy still shows the original. Upload to replace it."

    static func plan(for record: CaptureRecord, saveFolder: URL?) -> Plan {
        guard let fileURL = record.fileURL else { return .unavailable(noFileReason) }
        if record.fileIsTemporary { return .pendingFile(fileURL) }
        guard let saveFolder else { return .unavailable(noFolderReason) }
        guard SaveLocation.contains(fileURL, inFolder: saveFolder) else { return .unavailable(outsideFolderReason) }
        return .saveFolderFile(fileURL, folder: saveFolder)
    }

    /// The subtitle note for an edit that was saved locally but that the link does not show yet.
    static func uploadedCopyNotice(for record: CaptureRecord) -> String? {
        record.uploadIsStale ? uploadedCopyStaleNotice : nil
    }
}

/// The editor's commands as the availability table and the shortcut gate see them.
nonisolated enum EditorAction: CaseIterable, Sendable {
    case save, saveCopy, copy, upload, uploadAsNew
}

/// What the editor may do for its record now, why not, and the window subtitle. One table feeds
/// the toolbar validation, the shortcut gate, the action methods' guard and the coordinator's
/// write-time check. A nil record was deleted or pruned.
nonisolated enum EditorAvailability {
    static let deletedStatus = "This capture was deleted. Copy and Save Copy still work."
    static let deletingStatus = "Deleting…"
    static let uploadingStatus = "Uploading…"
    static let deletedRefusal = "This capture was deleted."
    static let deletingRefusal = "This capture is being deleted."
    static let uploadingRefusal = "This capture is still uploading."
    static let notUploadedRefusal = "This capture has no link yet. Use Upload."

    static func actions(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> Set<EditorAction> {
        Set(EditorAction.allCases.filter {
            refusal(for: $0, record: record, saveFolder: saveFolder, isDeleting: isDeleting) == nil
        })
    }

    /// Nil when `action` may run; otherwise the reason, posted as the body of `Not saved` or
    /// `Not uploaded`. Copy and Save Copy are never refused: they work on the editor's own image,
    /// also for a deleted, deleting or uploading record.
    static func refusal(for action: EditorAction, record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String? {
        switch action {
        case .copy, .saveCopy:
            return nil
        case .save, .upload, .uploadAsNew:
            guard let record else { return deletedRefusal }
            if isDeleting { return deletingRefusal }
            if record.isUploading { return uploadingRefusal }
            if action == .save, case .unavailable(let reason) = EditorSaveTarget.plan(for: record, saveFolder: saveFolder) {
                return reason
            }
            if action == .uploadAsNew, record.linkURL == nil { return notUploadedRefusal }
            return nil
        }
    }

    /// The window subtitle, or nil for none. In order: deleted, deleting, uploading, the stale-link
    /// note, then why Save is off.
    static func status(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String? {
        guard let record else { return deletedStatus }
        if isDeleting { return deletingStatus }
        if record.isUploading { return uploadingStatus }
        if let notice = EditorSaveTarget.uploadedCopyNotice(for: record) { return notice }
        if case .unavailable(let reason) = EditorSaveTarget.plan(for: record, saveFolder: saveFolder) { return reason }
        return nil
    }
}
