import AppKit
import Observation

/// State behind the gallery window: the history (newest first), which cell is hovered, and the
/// larger preview for it.
@Observable
final class GalleryModel {
    /// A decoded preview and the record it belongs to.
    private struct LoadedPreview {
        let id: UUID
        let image: NSImage
    }

    let history: HistoryStore
    @ObservationIgnored let provider: ThumbnailProvider

    /// The last cell the mouse entered. Kept when the mouse leaves, so the preview pane does not
    /// flicker back to the newest capture between cells.
    private(set) var hoveredID: UUID?
    private var loadedPreview: LoadedPreview?

    init(history: HistoryStore, provider: ThumbnailProvider) {
        self.history = history
        self.provider = provider
    }

    var records: [CaptureRecord] { history.records }

    /// The hovered record, or the newest one, or nil when the history is empty.
    var previewRecord: CaptureRecord? {
        if let hoveredID, let record = history.record(id: hoveredID) { return record }
        return records.first
    }

    /// The preview image while it belongs to `previewRecord`. It is nil while a new preview loads
    /// and as soon as the record it was loaded for is deleted or leaves the history, so the pane
    /// never shows a capture that is gone.
    var preview: NSImage? {
        guard let loadedPreview, loadedPreview.id == previewRecord?.id else { return nil }
        return loadedPreview.image
    }

    func thumbnail(for record: CaptureRecord) async -> NSImage? {
        await provider.thumbnail(for: record)
    }

    func hover(_ id: UUID) {
        guard id != hoveredID else { return }
        hoveredID = id
    }

    /// Loads the preview for `previewRecord`. Called from the gallery's `.task(id:)`, which
    /// cancels it when the previewed record changes (hover, a new capture, a deletion).
    func loadPreview() async {
        guard let record = previewRecord else { return }
        let image = await provider.preview(for: record)
        guard !Task.isCancelled, let image else { return }
        loadedPreview = LoadedPreview(id: record.id, image: image)
    }
}
