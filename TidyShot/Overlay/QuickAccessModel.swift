import AppKit
import Observation

/// State behind the Quick Access panel: the capture it shows and the actions its buttons run.
@Observable
final class QuickAccessModel {
    var record: CaptureRecord
    var thumbnail: NSImage?
    var isHovered = false
    /// The card's staged drag file (`DragFileStore`), or nil while none is ready; set by
    /// `QuickAccessController.setDragFile(_:for:)`. Read by the drag view, not drawn.
    @ObservationIgnored var dragFileURL: URL?
    /// True while a drag-out session from this card runs; the auto-close countdown waits meanwhile.
    @ObservationIgnored var isDraggingOut = false

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
    /// A press on the card's drag surface: stage the drag file now.
    @ObservationIgnored var onPrepareDrag: () -> Void = {}
    /// A drag-out session ended; true when a receiver took the file.
    @ObservationIgnored var onDragEnded: (Bool) -> Void = { _ in }

    init(record: CaptureRecord, thumbnail: NSImage?) {
        self.record = record
        self.thumbnail = thumbnail
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
}
