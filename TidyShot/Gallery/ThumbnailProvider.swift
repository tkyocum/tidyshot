import AppKit

/// Thumbnails and larger previews for the gallery, through async methods that the gallery calls
/// from `.task` modifiers, never from a view body. Thumbnails come from the `thumbnails` folder;
/// a record from before thumbnails existed gets one made from its local file the first time it
/// is shown (the record is updated once that finishes), or a placeholder (nil) when it has no
/// readable file, and such a record is not tried again. Previews are decoded from the local file
/// off the main thread and fall back to the thumbnail.
final class ThumbnailProvider {
    static let previewCacheLimit = 8

    private let store: ThumbnailStore
    private let history: HistoryStore
    private let readFile: (CaptureRecord) throws -> Data
    private var thumbnails: [UUID: NSImage] = [:]
    /// Records whose thumbnail could not be made from their file; tried once per launch.
    private var unavailable: Set<UUID> = []
    private var previews: [UUID: NSImage] = [:]
    /// Ids in `previews`, oldest first, each at most once.
    private var previewOrder: [UUID] = []
    /// Bumped by `forget`. A load compares the value from its start with the one at its end, so
    /// a load still running for a deleted record is discarded.
    private var generations: [UUID: Int] = [:]

    /// `readFile` returns the record's PNG, or throws when there is none (see
    /// `AppCoordinator.readLocalFile(of:)`).
    init(store: ThumbnailStore, history: HistoryStore, readFile: @escaping (CaptureRecord) throws -> Data) {
        self.store = store
        self.history = history
        self.readFile = readFile
    }

    /// The 320 px thumbnail, or nil for a placeholder.
    func thumbnail(for record: CaptureRecord) async -> NSImage? {
        let id = record.id
        if let cached = thumbnails[id] { return cached }
        let generation = generations[id, default: 0]
        if let name = record.thumbnailFileName {
            let url = store.url(forFileName: name)
            let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
            guard generations[id, default: 0] == generation else { return nil }
            if let data, let image = NSImage(data: data) {
                thumbnails[id] = image
                return image
            }
        }
        // No stored thumbnail (a record from before Phase 3, or one whose capture-time thumbnail
        // is still being written): make one from the local file, once.
        guard !unavailable.contains(id) else { return nil }
        guard let data = try? readFile(record) else {
            unavailable.insert(id)
            return nil
        }
        let store = store
        let made = await Task.detached(priority: .utility) { () -> (image: CGImage, name: String)? in
            guard let small = ThumbnailMaker.thumbnail(fromPNGData: data),
                  let png = try? ThumbnailMaker.pngData(small),
                  let name = try? store.write(png, id: id) else { return nil }
            return (small, name)
        }.value
        guard generations[id, default: 0] == generation, history.record(id: id) != nil else {
            // Deleted while the thumbnail was being made: do not leave its file behind.
            if let made { store.remove(fileName: made.name) }
            return nil
        }
        guard let made else {
            unavailable.insert(id)
            return nil
        }
        history.update(id: id) { $0.thumbnailFileName = made.name }
        let image = NSImage(cgImage: made.image, size: .zero)
        thumbnails[id] = image
        return image
    }

    /// Up to 1200 px from the local file, or the thumbnail when the record has no file left.
    func preview(for record: CaptureRecord) async -> NSImage? {
        let id = record.id
        if let cached = previews[id] { return cached }
        let generation = generations[id, default: 0]
        guard let data = try? readFile(record) else { return await thumbnail(for: record) }
        let decoded = await Task.detached(priority: .userInitiated) {
            ThumbnailMaker.thumbnail(fromPNGData: data, maxSide: ThumbnailMaker.previewMaxSide)
        }.value
        guard generations[id, default: 0] == generation else { return nil }
        guard let decoded else { return await thumbnail(for: record) }
        let image = NSImage(cgImage: decoded, size: .zero)
        previews[id] = image
        // Two overlapping loads for one id must not leave it in the order twice.
        previewOrder.removeAll { $0 == id }
        previewOrder.append(id)
        if previewOrder.count > Self.previewCacheLimit {
            previews[previewOrder.removeFirst()] = nil
        }
        return image
    }

    /// Drops everything cached for a deleted record and discards any load still running for it.
    func forget(_ id: UUID) {
        thumbnails[id] = nil
        unavailable.remove(id)
        previews[id] = nil
        previewOrder.removeAll { $0 == id }
        generations[id, default: 0] += 1
    }
}
