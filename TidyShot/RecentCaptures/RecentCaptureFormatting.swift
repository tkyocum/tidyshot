import Foundation

/// The text and button states of a Recent Captures row, worked out before the row is built so
/// that its SwiftUI `body` only lays them out.
nonisolated enum RecentCaptureFormatting {
    /// `aSIS7x.png`: the last part of the public URL once uploaded, otherwise the local file's
    /// name. A record from before Phase 3.1 with neither shows its app name.
    static func name(for record: CaptureRecord) -> String {
        record.uploadedURL?.lastPathComponent ?? record.fileURL?.lastPathComponent ?? record.appName ?? "Capture"
    }

    /// "2 minutes ago", with the upload state while it is not settled: "2 minutes ago · Uploading",
    /// "yesterday · Upload failed", or "2 minutes ago · Optimizing…" while a recording waits for
    /// Clop (`isOptimizing`, from `AppCoordinator.optimizingVideoIDs`).
    static func detail(for record: CaptureRecord, now: Date, locale: Locale = .current,
                       isOptimizing: Bool = false) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let time = formatter.localizedString(for: record.timestamp, relativeTo: now)
        switch record.uploadState {
        case .uploading: return isOptimizing ? "\(time) · Optimizing…" : "\(time) · Uploading"
        case .failed: return "\(time) · Upload failed"
        case .none, .uploaded: return time
        }
    }

    /// Copy URL needs a link: an uploaded object, or the earlier link of an editor upload that is
    /// running or was interrupted (`CaptureRecord.linkURL`).
    static func canCopyLink(_ record: CaptureRecord) -> Bool {
        record.linkURL != nil
    }

    /// Annotate, Pin and Copy Image are left out for a recording, not disabled; Copy File takes
    /// Copy Image's place (design, Videos in the rest of the app).
    static func showsImageActions(_ record: CaptureRecord) -> Bool {
        !record.isVideo
    }

    /// Copy File needs a recording with a local file, in the save folder or `pending/`.
    static func canCopyFile(_ record: CaptureRecord) -> Bool {
        record.isVideo && record.hasLocalFile
    }

    /// Copy Image needs an image with a local file, or an uploaded object whose bucket is known
    /// (signed GET). Never for a recording.
    static func canCopyImage(_ record: CaptureRecord) -> Bool {
        showsImageActions(record) && (record.hasLocalFile || (record.uploadedKey != nil && record.objectLocation != nil))
    }

    /// Annotate needs an image the editor can load: the capture just taken (still in memory), a
    /// file it can read, or an uploaded object whose bucket is known. Only `.unavailable` disables
    /// the button, for example a record from before Phase 3 with no file, or a file outside the
    /// current save folder that was never uploaded. A recording is always `.unavailable`.
    static func canAnnotate(_ record: CaptureRecord, retainedID: UUID?, saveFolder: URL?) -> Bool {
        if case .unavailable = EditorInput.source(for: record, retainedID: retainedID, saveFolder: saveFolder) {
            return false
        }
        return true
    }
}
