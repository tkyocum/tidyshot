import AppKit
import Observation

/// What a Quick Access card's status lines say (`QuickAccessView.statusContent`).
nonisolated enum QuickAccessStatus: Equatable {
    /// `Saved`, with the file name, or what stands in for it for an upload-only capture.
    case saved(String)
    /// A temporary file with no upload: a recording that could not reach the save folder.
    case kept
    case uploading(Double)
    /// A recording's upload waits for Clop.
    case optimizing
    /// The URL replaced the clipboard.
    case urlCopied(URL)
    /// A recording's URL did not replace the clipboard, because it had changed since the save.
    case uploaded(URL)
    /// A trimmed MP4 whose link still shows the full recording (design, Stale link).
    case linkNotUpdated(URL)
    case failed(String)
    /// A recording whose muting failed: kept in TidyShot and never uploaded (design, Privacy rule).
    case soundNotMuted
    /// An uploaded recording with no local file downloads for a drag (design, Drag-out download).
    case downloading(Double)
    case downloadFailed(String)
}

/// A card's drag-out download: running with its fraction, or failed with its error.
nonisolated enum DragDownloadStatus: Equatable {
    case running(Double)
    case failed(String)
}

/// State behind the Quick Access panel: the capture it shows and the actions its buttons run.
@Observable
final class QuickAccessModel {
    var record: CaptureRecord
    var thumbnail: NSImage?
    var isHovered = false
    /// The recording's upload waits for Clop (`AppCoordinator.optimizingVideoIDs`); set by
    /// `QuickAccessController.setOptimizing(_:for:)`.
    var isOptimizing = false
    /// False when a recording's URL did not replace the clipboard (`AppCoordinator.linkNotCopiedIDs`);
    /// set by `QuickAccessController.setLinkWasCopied(_:for:)`.
    var linkWasCopied = true
    /// The card's staged drag file (`DragFileStore`), or nil while none is ready; set by
    /// `QuickAccessController.setDragFile(_:for:)`. Read by the drag view, not drawn.
    @ObservationIgnored var dragFileURL: URL?
    /// True while a drag-out session from this card runs; the auto-close countdown waits meanwhile.
    @ObservationIgnored var isDraggingOut = false
    /// The drag-out download of an uploaded recording with no local file: running, failed, or nil
    /// for neither; set by `QuickAccessController.setDownloading(_:for:)`.
    var dragDownload: DragDownloadStatus?
    /// The card's `Trim…` and `Upload Trimmed`, and whether a Trim pass writes the record's file
    /// (`AppCoordinator.trimMenuState(for:)`); set by `QuickAccessController.setTrimState(_:for:)`.
    /// All false until then, so neither item shows.
    var trimState = RecordingTrim.MenuState()

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onRetry: () -> Void = {}
    @ObservationIgnored var onReveal: () -> Void = {}
    @ObservationIgnored var onDelete: () -> Void = {}
    @ObservationIgnored var onAnnotate: () -> Void = {}
    @ObservationIgnored var onPin: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    /// The card's Save As… and Copy Image: `AppCoordinator.saveAs(recordID:)` and `copyImage(recordID:)`.
    @ObservationIgnored var onSaveAs: () -> Void = {}
    @ObservationIgnored var onCopyImage: () -> Void = {}
    /// A recording's thumbnail click and Copy File: `AppCoordinator.openCapture(recordID:)` and
    /// `copyFile(recordID:)`.
    @ObservationIgnored var onOpen: () -> Void = {}
    @ObservationIgnored var onCopyFile: () -> Void = {}
    /// A recording's `Trim…` and `Upload Trimmed`: `AppCoordinator.trimCapture(recordID:)` and
    /// `uploadTrimmed(recordID:)`.
    @ObservationIgnored var onTrim: () -> Void = {}
    @ObservationIgnored var onUploadTrimmed: () -> Void = {}
    /// A press on the card's drag surface: stage the drag file now.
    @ObservationIgnored var onPrepareDrag: () -> Void = {}
    /// A drag-out session ended; true when a receiver took the file.
    @ObservationIgnored var onDragEnded: (Bool) -> Void = { _ in }
    /// A drag past the threshold with no drag file: download an uploaded recording for it.
    @ObservationIgnored var onDownloadForDrag: () -> Void = {}

    init(record: CaptureRecord, thumbnail: NSImage?) {
        self.record = record
        self.thumbnail = thumbnail
    }

    /// True while the drag-out download runs; the auto-close countdown waits meanwhile.
    var isDownloadingForDrag: Bool {
        if case .running = dragDownload { return true }
        return false
    }

    /// True once the upload has finished (or there was none), which starts the auto-close timer.
    var isSettled: Bool {
        !record.isUploading
    }

    /// A file in the save folder to show in Finder. A pending upload-only file lives in the
    /// container and is not revealed.
    var canReveal: Bool {
        record.fileURL != nil && !record.fileIsTemporary
    }

    /// Annotate, Pin and Copy Image; left out for a recording.
    var showsImageActions: Bool {
        RecentCaptureFormatting.showsImageActions(record)
    }

    /// Copy File, for a recording with a local file that is not marked `Sound not muted`.
    var canCopyFile: Bool {
        RecentCaptureFormatting.canCopyFile(record)
    }

    /// Save As…, left out for a recording marked `Sound not muted`, whose file still holds the
    /// muted sound (design, Privacy rule).
    var canSaveAs: Bool {
        !RecentCaptureFormatting.isSoundNotMuted(record)
    }

    /// A recording's thumbnail click opens its local file, or its link when only the upload is left.
    var canOpen: Bool {
        record.isTimeBased && (record.hasLocalFile || record.linkURL != nil)
    }

    /// The poster's badge: `play.fill` for an MP4, `GIF` for a GIF; nil for an image.
    var badge: RecentCaptureFormatting.RecordingBadge? {
        RecentCaptureFormatting.badge(for: record)
    }

    /// Retry and Delete are disabled while a Trim pass writes the record's file (design, Write-time
    /// checks); `Upload Trimmed` is, through `trimState.canUploadTrimmed`.
    var canRetry: Bool {
        !trimState.isTrimming
    }

    var canDelete: Bool {
        !trimState.isTrimming
    }

    var status: QuickAccessStatus {
        if RecentCaptureFormatting.isSoundNotMuted(record) { return .soundNotMuted }
        switch dragDownload {
        case .running(let fraction): return .downloading(fraction)
        case .failed(let message): return .downloadFailed(message)
        case nil: break
        }
        return switch record.uploadState {
        case .none:
            record.fileIsTemporary && record.hasLocalFile
                ? .kept
                : .saved(record.fileURL?.lastPathComponent ?? "Upload only, no local file")
        case .uploading(let fraction):
            isOptimizing ? .optimizing : .uploading(fraction)
        case .uploaded(let url, _):
            RecentCaptureFormatting.linkIsNotUpdated(record)
                ? .linkNotUpdated(url)
                : linkWasCopied ? .urlCopied(url) : .uploaded(url)
        case .failed(let message):
            .failed(message)
        }
    }
}
