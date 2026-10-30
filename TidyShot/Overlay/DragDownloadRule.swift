import Foundation

/// When a drag on a card downloads an uploaded recording that has no local file (design, Drag-out
/// download), and what the card does meanwhile.
nonisolated enum DragDownloadRule {
    /// Resume data replays the first request, whose signature S3 accepts for 15 minutes; a retry
    /// uses it only while less than this has passed since the request was signed.
    static let resumeWindow: TimeInterval = 840

    /// An MP4 or a GIF with no local file, uploaded and not marked `Sound not muted`, whose card has
    /// no drag file and whose download is not running.
    static func starts(record: CaptureRecord, hasDragFile: Bool, isRunning: Bool) -> Bool {
        record.isTimeBased && !record.hasLocalFile
            && record.uploadedKey != nil && record.objectLocation != nil
            && record.uploadBlockedReason == nil
            && !hasDragFile && !isRunning
    }

    /// The file's size plus the 1 GB a recording keeps free. A record with no size, or an
    /// unreadable free space, counts as enough.
    static func hasRoom(byteCount: Int?, freeBytes: Int64?) -> Bool {
        guard let byteCount else { return true }
        return RecordingLimits.hasRoom(for: Int64(byteCount), freeBytes: freeBytes)
    }

    static func usesResumeData(signedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(signedAt) < resumeWindow
    }

    /// The partial file URLSession keeps for `resumeData`, so a resume that is dropped unused can
    /// remove it. The data is a keyed archive on current macOS and a plain dictionary on older
    /// ones; both are read. Only a file named `CFNetworkDownload_…` is returned, so nothing else
    /// can be removed by mistake.
    static func partialFile(in resumeData: Data,
                            temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> URL? {
        guard let dictionary = (try? PropertyListSerialization.propertyList(from: resumeData, format: nil))
                as? [String: Any] else { return nil }
        var names = ["NSURLSessionResumeInfoTempFileName", "NSURLSessionResumeInfoLocalPath"]
            .compactMap { dictionary[$0] as? String }
        names += (dictionary["$objects"] as? [Any] ?? []).compactMap { $0 as? String }
        for name in names {
            let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : temporaryDirectory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            if url.lastPathComponent.hasPrefix("CFNetworkDownload_"),
               FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return url
            }
        }
        return nil
    }

    /// The auto-close countdown waits during a download as it does during a drag-out session.
    static func keepsCardOpen(isDraggingOut: Bool, isDownloading: Bool) -> Bool {
        isDraggingOut || isDownloading
    }
}
