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
        /// Nothing to write over, for this reason (the window subtitle). ⌘S then runs Save As….
        case unavailable(String)

        /// Whether there is a file to write over; `unavailable` says why not.
        var writesOverFile: Bool { if case .unavailable = self { false } else { true } }
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

    /// The local write before an Upload (⌘U, ⌥⌘U). An Upload always leaves the edit in a local
    /// file, so a failed upload keeps it and Retry never uploads an unedited original.
    enum UploadWrite: Equatable, Sendable {
        /// Save over the Save target first (`applyLocalEdit`), so the file equals the object.
        case saveTarget
        /// Nothing to write over (an uploaded upload-only capture with no file, a save-folder file
        /// outside the current folder, or no folder): the edit gets `pending/<id>.png` and the
        /// record switches to it, as an upload-only capture. A save-folder original stays where it is.
        case newPendingFile
    }

    static func uploadWrite(for record: CaptureRecord, saveFolder: URL?) -> UploadWrite {
        plan(for: record, saveFolder: saveFolder).writesOverFile ? .saveTarget : .newPendingFile
    }

    /// True when a Save As… to `url` lands on the record's own file and ⌘S could write over that
    /// file now; the coordinator then runs Save, so the record, its thumbnail and the stale flag
    /// follow. Paths are compared standardized.
    static func saveAsWritesOverOwnFile(_ url: URL, record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> Bool {
        guard let record, let fileURL = record.fileURL,
              url.standardizedFileURL == fileURL.standardizedFileURL,
              EditorAvailability.refusal(for: .save, record: record, saveFolder: saveFolder, isDeleting: isDeleting) == nil
        else { return false }
        return plan(for: record, saveFolder: saveFolder).writesOverFile
    }

    /// The subtitle note for an edit that was saved locally but that the link does not show yet.
    static func uploadedCopyNotice(for record: CaptureRecord) -> String? {
        record.uploadIsStale ? uploadedCopyStaleNotice : nil
    }
}

/// The editor's commands as the availability table and the shortcut gate see them.
nonisolated enum EditorAction: CaseIterable, Sendable {
    case save, saveAs, copy, upload, uploadAsNew
}

/// What ⌘S does (spec 2.6, Save), decided from the record and the save folder the editor last
/// heard of. The coordinator plans again at write time.
nonisolated enum EditorSaveCommand: Equatable, Sendable {
    /// Write over the Save target (`EditorSaveTarget.plan`) through the coordinator.
    case writeOver
    /// Nothing local to write over (no file, a file outside the current folder, no folder, or no
    /// record): run Save As….
    case saveAs

    static func forSave(record: CaptureRecord?, saveFolder: URL?) -> EditorSaveCommand {
        guard let record, EditorSaveTarget.plan(for: record, saveFolder: saveFolder).writesOverFile else { return .saveAs }
        return .writeOver
    }

    /// The unsaved-changes sheet's first button.
    enum CloseSheetButton: Equatable, Sendable {
        /// Runs ⌘S, which opens the save panel itself when there is nothing to write over.
        case save
        /// Save is unavailable (uploading, deleting or deleted): runs Save As….
        case saveAs

        var title: String {
            switch self {
            case .save: "Save"
            case .saveAs: "Save As…"
            }
        }
    }

    static func closeSheetButton(available: Set<EditorAction>) -> CloseSheetButton {
        available.contains(.save) ? .save : .saveAs
    }
}

/// What the editor may do for its record now, why not, and the window subtitle. One table feeds
/// the toolbar validation, the shortcut gate, the action methods' guard and the coordinator's
/// write-time check. A nil record was deleted or pruned.
nonisolated enum EditorAvailability {
    static let deletedStatus = "This capture was deleted. Copy and Save As still work."
    static let deletingStatus = "Deleting…"
    static let uploadingStatus = "Uploading…"
    static let deletedRefusal = "This capture was deleted."
    static let deletingRefusal = "This capture is being deleted."
    static let uploadingRefusal = "This capture is still uploading."
    static let notUploadedRefusal = "This capture has no link yet. Use Upload."
    /// While a Trim pass runs on the record (`AppCoordinator.trimmingIDs`): Retry, `Upload Trimmed`
    /// and `startUpload` refuse with it.
    static let trimmingRefusal = "This capture is being trimmed."

    static func actions(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> Set<EditorAction> {
        Set(EditorAction.allCases.filter {
            refusal(for: $0, record: record, saveFolder: saveFolder, isDeleting: isDeleting) == nil
        })
    }

    /// Nil when `action` may run; otherwise the reason, posted as the body of `Not saved` or
    /// `Not uploaded`. Copy and Save As… are never refused: they work on the editor's own image,
    /// also for a deleted, deleting or uploading record. Save is not refused for want of a file
    /// to write over: `EditorSaveCommand` sends it to Save As… then. `isTrimming` is true while a
    /// Trim pass runs on the record; the pass itself asks with false.
    static func refusal(for action: EditorAction, record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool,
                        isTrimming: Bool = false) -> String? {
        switch action {
        case .copy, .saveAs:
            return nil
        case .save, .upload, .uploadAsNew:
            guard let record else { return deletedRefusal }
            if isDeleting { return deletingRefusal }
            if isTrimming { return trimmingRefusal }
            if record.isUploading { return uploadingRefusal }
            if action == .uploadAsNew, record.linkURL == nil { return notUploadedRefusal }
            return nil
        }
    }

    /// The window subtitle, or nil for none. In order: deleted, deleting, uploading, the stale-link
    /// note, then why Save has nothing to write over.
    static func status(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String? {
        guard let record else { return deletedStatus }
        if isDeleting { return deletingStatus }
        if record.isUploading { return uploadingStatus }
        if let notice = EditorSaveTarget.uploadedCopyNotice(for: record) { return notice }
        if case .unavailable(let reason) = EditorSaveTarget.plan(for: record, saveFolder: saveFolder) { return reason }
        return nil
    }
}
