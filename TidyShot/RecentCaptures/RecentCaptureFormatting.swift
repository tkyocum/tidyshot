import Foundation

/// The text and button states of a Recent Captures row, worked out before the row is built so
/// that its SwiftUI `body` only lays them out.
nonisolated enum RecentCaptureFormatting {
    /// `aSIS7x.png`: the last part of the public URL once uploaded, otherwise the local file's
    /// name. A record from before Phase 3.1 with neither shows its app name.
    static func name(for record: CaptureRecord) -> String {
        record.uploadedURL?.lastPathComponent ?? record.fileURL?.lastPathComponent ?? record.appName ?? "Capture"
    }

    /// "2 minutes ago · 5 KB": the relative time and the record's size (`sizeText`), then the upload
    /// state while it is not settled: "2 minutes ago · 5 KB · Uploading", "yesterday · 5 KB · Upload
    /// failed", or "2 minutes ago · 5 KB · Optimizing…" while a recording waits for Clop
    /// (`isOptimizing`, from `AppCoordinator.optimizingVideoIDs`). The parts are joined by a middle
    /// dot with a space either side, and an unknown or zero size leaves its part out.
    static func detail(for record: CaptureRecord, now: Date, locale: Locale = .current,
                       isOptimizing: Bool = false) -> String {
        let parts = detailParts(for: record, now: now, locale: locale, isOptimizing: isOptimizing)
        return [parts.time, parts.size, parts.state].compactMap { $0 }.joined(separator: " · ")
    }

    /// The detail with the size left out: "2 minutes ago · Upload failed". The row shows it when the
    /// whole detail would not fit, so the size gives way before the upload state is cut off. Nil
    /// when there is no size to leave out.
    static func detailWithoutSize(for record: CaptureRecord, now: Date, locale: Locale = .current,
                                  isOptimizing: Bool = false) -> String? {
        let parts = detailParts(for: record, now: now, locale: locale, isOptimizing: isOptimizing)
        guard parts.size != nil else { return nil }
        return [parts.time, parts.state].compactMap { $0 }.joined(separator: " · ")
    }

    private static func detailParts(for record: CaptureRecord, now: Date, locale: Locale,
                                    isOptimizing: Bool) -> (time: String, size: String?, state: String?) {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let state: String? = switch record.uploadState {
        case .uploading: isOptimizing ? "Optimizing…" : "Uploading"
        case .failed: "Upload failed"
        case .none, .uploaded: nil
        }
        return (formatter.localizedString(for: record.timestamp, relativeTo: now), sizeText(record.byteCount), state)
    }

    /// "999 bytes", "5 KB", "1.2 MB": `ByteCountFormatter`'s `.file` style, the decimal units Finder
    /// shows. Nil for an unknown or zero size. `ByteCountFormatter` has no locale of its own and
    /// writes in the current one; the format-style API that takes a locale writes `kB` and rounds
    /// 999 bytes up to `1 kB`, unlike Finder.
    static func sizeText(_ byteCount: Int?) -> String? {
        guard let byteCount, byteCount > 0 else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(byteCount))
    }

    /// Copy URL needs a link: an uploaded object, or the earlier link of an editor upload that is
    /// running or was interrupted (`CaptureRecord.linkURL`).
    static func canCopyLink(_ record: CaptureRecord) -> Bool {
        record.linkURL != nil
    }

    /// Annotate, Pin and Copy Image are left out for a recording, not disabled; Copy File takes
    /// Copy Image's place (design, Videos in the rest of the app).
    static func showsImageActions(_ record: CaptureRecord) -> Bool {
        !record.isTimeBased
    }

    /// Copy File needs a recording with a local file, in the save folder or `pending/`.
    static func canCopyFile(_ record: CaptureRecord) -> Bool {
        record.isTimeBased && record.hasLocalFile
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
