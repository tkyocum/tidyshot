import Foundation

/// Where `saveRecording` first tries to put the file.
nonisolated enum RecordingFileTarget: Equatable, Sendable {
    case saveFolder
    case pending
}

/// Where the file ended up.
nonisolated enum RecordingFileResult: Equatable, Sendable {
    /// Moved into the save folder.
    case saveFolder
    /// Moved to `pending/<id>.mp4`, the target for `.uploadOnly`.
    case pending
    /// Meant for the save folder, but in `pending/` instead: no folder was chosen, or the move failed.
    case fallback(reason: String)
    /// Even the rename into `pending/` failed; the file is still at `path` in `tmp/Recording`.
    case leftInTmp(reason: String, path: String)
}

/// What posts once the record is made, besides the upload's own notifications.
nonisolated enum RecordingSaveNotification: Equatable, Sendable {
    case none
    /// `Recording saved`, when Show notification is on.
    case saved
    /// Always posts.
    case notice(RecordingNotice)
}

/// What a save that refused the upload for its size does to the record (Size in the design,
/// Gap 4). The state is always `.none`, never `.failed`, so nothing offers Retry.
nonisolated struct RecordingOversizePlan: Equatable, Sendable {
    var fileIsTemporary: Bool
    var uploadState: CaptureRecord.UploadState
    var notices: [RecordingNotice]
}

/// How `saveRecording` treats a recording, from the after-capture action, the destination and
/// where the file landed: the table, No destination, Where the file lands, Clipboard after the
/// upload and quit mode in the design. Pure; the coordinator carries it out.
nonisolated struct RecordingSavePlan: Equatable, Sendable {
    /// False only when the file is still in `tmp/Recording`: the launch check recovers it.
    var makesRecord: Bool
    /// The file is in `pending/`, whatever the action.
    var fileIsTemporary: Bool
    var uploadState: CaptureRecord.UploadState
    /// Start the upload now.
    var uploads: Bool
    /// Put a reference to the file on the clipboard.
    var copiesFileReference: Bool
    /// Only a file in the save folder becomes `lastCaptureURL`.
    var setsLastCaptureURL: Bool
    var showsCard: Bool
    var notification: RecordingSaveNotification
    /// Posted through the once-per-launch `Upload not configured` gate.
    var notConfiguredWarning: String?

    static let noFolderReason = "No folder was chosen."
    static let notSavedTitle = "Not saved to a folder"
    static let oversizedNotice = RecordingNotice(
        title: "Not uploaded", body: "The recording is larger than 5 GB, too large to upload in one piece.")
    /// What quit mode writes for an upload it does not start.
    static let interruptedUploadMessage = "Upload was interrupted."
    static let uploadNotConfiguredWarning =
        "Set up a destination in Settings > Upload. The recording was saved and is on the clipboard as a file."
    static let uploadOnlyNotConfiguredWarning =
        "Set up a destination in Settings > Upload, then retry from Recent Captures. TidyShot keeps the recording until then."

    static func target(for action: AfterCaptureAction) -> RecordingFileTarget {
        action == .uploadOnly ? .pending : .saveFolder
    }

    /// `copyImage` is `Copy image to clipboard`, `alsoCopyImage` is `Also copy image…`. With no
    /// destination, `.upload` is saved exactly as `.save`, with a file reference whatever the
    /// settings say. A `.upload` file that fell back to `pending/` with a destination behaves as
    /// `.uploadOnly` from here on. Quit mode skips the upload (an uploading record is written as
    /// interrupted), the card, the notifications and the warning; the clipboard rule still applies.
    static func make(action: AfterCaptureAction, hasDestination: Bool, result: RecordingFileResult,
                     copyImage: Bool, alsoCopyImage: Bool, quitMode: Bool) -> RecordingSavePlan {
        if case .leftInTmp(let reason, let path) = result {
            let notice = RecordingNotice(title: notSavedTitle, body: "\(reason) The recording is still at \(path).")
            return RecordingSavePlan(makesRecord: false, fileIsTemporary: true, uploadState: .none, uploads: false,
                                     copiesFileReference: false, setsLastCaptureURL: false, showsCard: false,
                                     notification: quitMode ? .none : .notice(notice), notConfiguredWarning: nil)
        }

        let inSaveFolder = result == .saveFolder
        let willUpload = hasDestination && action != .save

        let uploadState: CaptureRecord.UploadState
        if willUpload {
            uploadState = quitMode ? .failed(message: interruptedUploadMessage) : .uploading(fraction: 0)
        } else if action == .uploadOnly {
            // Nowhere to upload to yet; the pending file stays until a retry succeeds.
            uploadState = .failed(message: UploadError.notConfigured.localizedDescription)
        } else {
            uploadState = .none
        }

        let copiesFileReference: Bool
        switch action {
        case .save: copiesFileReference = copyImage
        case .upload: copiesFileReference = hasDestination ? inSaveFolder && alsoCopyImage : true
        // A reference into `pending/` would dangle once the upload removes the file.
        case .uploadOnly: copiesFileReference = false
        }

        let notification: RecordingSaveNotification
        if quitMode {
            notification = .none
        } else if case .fallback(let reason) = result {
            notification = .notice(notSavedToFolder(reason: reason, uploads: willUpload))
        } else if inSaveFolder && !willUpload {
            notification = .saved
        } else {
            notification = .none
        }

        var warning: String?
        if !quitMode && !hasDestination {
            switch action {
            case .upload: warning = uploadNotConfiguredWarning
            case .uploadOnly: warning = uploadOnlyNotConfiguredWarning
            case .save: warning = nil
            }
        }

        return RecordingSavePlan(makesRecord: true, fileIsTemporary: !inSaveFolder, uploadState: uploadState,
                                 uploads: willUpload && !quitMode, copiesFileReference: copiesFileReference,
                                 setsLastCaptureURL: inSaveFolder, showsCard: !quitMode,
                                 notification: notification, notConfiguredWarning: warning)
    }

    /// After a video upload, the URL replaces the clipboard only if its change count is still the
    /// one TidyShot left after the save. No count, as after a relaunch, counts as changed.
    static func replacesClipboard(savedChangeCount: Int?, currentChangeCount: Int) -> Bool {
        savedChangeCount == currentChangeCount
    }

    static func notSavedToFolder(reason: String, uploads: Bool) -> RecordingNotice {
        RecordingNotice(title: notSavedTitle, body: reason + " " + (uploads
            ? "The recording uploads without a local copy."
            : "TidyShot keeps the recording. Use Save As… on its card."))
    }

    /// Over the single-upload limit, where the file is decides, not the action: a pending file
    /// moves into the save folder, and a save-folder file stays.
    static func oversizedMoves(fileIsTemporary: Bool) -> Bool {
        fileIsTemporary
    }

    /// `move` is nil when nothing moved, `.saveFolder` after the move, and `.fallback(reason:)`
    /// when no folder was chosen or the move failed, the file staying in `pending/`.
    static func oversized(fileIsTemporary: Bool, move: RecordingFileResult?) -> RecordingOversizePlan {
        switch move {
        case nil:
            RecordingOversizePlan(fileIsTemporary: fileIsTemporary, uploadState: .none, notices: [oversizedNotice])
        case .saveFolder:
            RecordingOversizePlan(fileIsTemporary: false, uploadState: .none, notices: [oversizedNotice])
        case .pending:
            RecordingOversizePlan(fileIsTemporary: true, uploadState: .none, notices: [oversizedNotice])
        case .fallback(let reason), .leftInTmp(let reason, _):
            RecordingOversizePlan(fileIsTemporary: true, uploadState: .none,
                                  notices: [oversizedNotice, notSavedToFolder(reason: reason, uploads: false)])
        }
    }
}
