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
    /// "yesterday · Upload failed".
    static func detail(for record: CaptureRecord, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let time = formatter.localizedString(for: record.timestamp, relativeTo: now)
        switch record.uploadState {
        case .uploading: return "\(time) · Uploading"
        case .failed: return "\(time) · Upload failed"
        case .none, .uploaded: return time
        }
    }

    /// Copy URL needs a link: an uploaded object, or the earlier link of an editor upload that is
    /// running or was interrupted (`CaptureRecord.linkURL`).
    static func canCopyLink(_ record: CaptureRecord) -> Bool {
        record.linkURL != nil
    }

    /// Copy Image needs a local file, or an uploaded object whose bucket is known (signed GET).
    static func canCopyImage(_ record: CaptureRecord) -> Bool {
        record.hasLocalFile || (record.uploadedKey != nil && record.objectLocation != nil)
    }
}
