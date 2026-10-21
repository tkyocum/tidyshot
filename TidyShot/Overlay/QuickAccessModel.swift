import AppKit
import Observation

/// State behind the Quick Access panel: the capture it shows and the actions its buttons run.
@Observable
final class QuickAccessModel {
    var record: CaptureRecord
    var thumbnail: NSImage?
    var isHovered = false

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onRetry: () -> Void = {}
    @ObservationIgnored var onReveal: () -> Void = {}
    @ObservationIgnored var onDelete: () -> Void = {}
    @ObservationIgnored var onAnnotate: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}
    /// Task 5 wires these to `AppCoordinator.saveAs(recordID:)` and `copyImage(recordID:)`.
    @ObservationIgnored var onSaveAs: () -> Void = {}
    @ObservationIgnored var onCopyImage: () -> Void = {}

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
