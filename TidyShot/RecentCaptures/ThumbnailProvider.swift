import AppKit

/// Thumbnails and larger previews for Recent Captures, through async methods that its rows and
/// hover preview call from tasks, never from a view body. Thumbnails come from the `thumbnails` folder;
/// a record from before thumbnails existed gets one made from its local file the first time it
/// is shown (the record is updated once that finishes), or a placeholder (nil) when it has no
/// readable file, and such a record is not tried again. Previews are read and decoded from the
/// local file off the main thread and fall back to the thumbnail. Every file read happens in a
/// detached task: a capture can be tens of megabytes. A recording's file is never read: its
/// thumbnail and its preview are the stored poster, or the placeholder.
final class ThumbnailProvider {
    static let previewCacheLimit = 8
    static let thumbnailCacheLimit = 64

    /// Reads a capture's PNG off the main actor: the file, and the save folder whose security
    /// scope covers it (nil for a temporary file in `pending`, which needs none).
    typealias FileReader = @Sendable (_ fileURL: URL, _ folder: URL?) throws -> Data

    /// What a thumbnail load found, handed back from its detached task.
    private nonisolated enum Made: Sendable {
        case unreadable
        case failed
        case made(image: CGImage, name: String)
    }

    private let store: ThumbnailStore
    private let history: HistoryStore
    private let saveFolder: () -> URL?
    private let readFile: FileReader
    private var thumbnails = RecentCache(limit: ThumbnailProvider.thumbnailCacheLimit)
    /// Records whose thumbnail could not be made from their file; tried once per launch.
    private var unavailable: Set<UUID> = []
    private var previews = RecentCache(limit: ThumbnailProvider.previewCacheLimit)
    /// Bumped by `forget`. A load compares the value from its start with the one at its end, so
    /// a load still running for a deleted record is discarded.
    private var generations: [UUID: Int] = [:]

    /// `saveFolder` is read on the main actor before each load (`SaveLocation.currentURL`);
    /// `readFile` runs in the load's detached task (see `SaveLocation.readScoped`).
    init(store: ThumbnailStore, history: HistoryStore, saveFolder: @escaping () -> URL?, readFile: @escaping FileReader) {
        self.store = store
        self.history = history
        self.saveFolder = saveFolder
        self.readFile = readFile
    }

    /// The 320 px thumbnail, or nil for a placeholder. A recording with none stored (its poster
    /// is still being written, or could not be made) gets the placeholder, never one made from its
    /// file.
    func thumbnail(for record: CaptureRecord) async -> NSImage? {
        let id = record.id
        if let cached = thumbnails[id] { return cached }
        let generation = generations[id, default: 0]
        if let name = record.thumbnailFileName {
            let url = store.url(forFileName: name)
            let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
            guard generations[id, default: 0] == generation else { return nil }
            if let data, let image = NSImage(data: data) {
                thumbnails.insert(image, for: id)
                return image
            }
        }
        // No stored thumbnail (a record from before Phase 3, or one whose capture-time thumbnail
        // is still being written): make one from the local file, once. Not from a video.
        guard !record.isTimeBased, !unavailable.contains(id) else { return nil }
        guard let source = readSource(for: record) else {
            unavailable.insert(id)
            return nil
        }
        let store = store
        let readFile = readFile
        let made = await Task.detached(priority: .utility) { () -> Made in
            guard let data = try? readFile(source.file, source.folder) else { return .unreadable }
            guard let small = ThumbnailMaker.thumbnail(fromPNGData: data),
                  let png = try? ThumbnailMaker.pngData(small),
                  let name = try? store.write(png, id: id) else { return .failed }
            return .made(image: small, name: name)
        }.value
        guard generations[id, default: 0] == generation, history.record(id: id) != nil else {
            // Deleted while the thumbnail was being made: do not leave its file behind.
            if case .made(_, let name) = made { store.remove(fileName: name) }
            return nil
        }
        guard case .made(let small, let name) = made else {
            unavailable.insert(id)
            return nil
        }
        history.update(id: id) { $0.thumbnailFileName = name }
        let image = NSImage(cgImage: small, size: .zero)
        thumbnails.insert(image, for: id)
        return image
    }

    /// Up to 1200 px from the local file, or the thumbnail when the record has no file left. A
    /// recording's is always its stored thumbnail, at its own size: no larger poster is stored.
    /// Cancelling the calling task stops the load before a read or a decode it has not started
    /// yet and returns nil, without the thumbnail fallback and without caching anything. That holds
    /// with or without a local file: a call already cancelled when it starts returns a cached
    /// preview or nil, and never reads the thumbnail.
    func preview(for record: CaptureRecord) async -> NSImage? {
        let id = record.id
        if let cached = previews[id] { return cached }
        guard !Task.isCancelled else { return nil }
        let generation = generations[id, default: 0]
        guard !record.isTimeBased, let source = readSource(for: record) else { return await thumbnail(for: record) }
        let readFile = readFile
        let load = Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard !Task.isCancelled, let data = try? readFile(source.file, source.folder),
                  !Task.isCancelled else { return nil }
            return ThumbnailMaker.thumbnail(fromPNGData: data, maxSide: ThumbnailMaker.previewMaxSide)
        }
        // A detached task does not inherit cancellation, so the caller's is passed on.
        let decoded = await withTaskCancellationHandler { await load.value } onCancel: { load.cancel() }
        guard !Task.isCancelled, generations[id, default: 0] == generation else { return nil }
        guard let decoded else { return await thumbnail(for: record) }
        let image = NSImage(cgImage: decoded, size: .zero)
        previews.insert(image, for: id)
        return image
    }

    /// Drops everything cached for a deleted or pruned record and discards any load still
    /// running for it.
    func forget(_ id: UUID) {
        thumbnails.remove(id)
        unavailable.remove(id)
        previews.remove(id)
        generations[id, default: 0] += 1
    }

    /// What `readFile` needs for the record, resolved on the main actor: the file and, for a
    /// file in the save folder, that folder. Nil when there is nothing to read (no local file,
    /// or no save folder to reach it through).
    private func readSource(for record: CaptureRecord) -> (file: URL, folder: URL?)? {
        guard let fileURL = record.fileURL else { return nil }
        if record.fileIsTemporary { return (fileURL, nil) }
        guard let folder = saveFolder() else { return nil }
        return (fileURL, folder)
    }

    /// The newest `limit` images by record id; the oldest goes as a newer one arrives.
    private struct RecentCache {
        let limit: Int
        private var images: [UUID: NSImage] = [:]
        /// Ids in `images`, oldest first, each at most once.
        private var order: [UUID] = []

        init(limit: Int) { self.limit = limit }

        subscript(id: UUID) -> NSImage? { images[id] }

        /// Stores `image` as the newest. Two overlapping loads for one id must not leave it in the
        /// order twice.
        mutating func insert(_ image: NSImage, for id: UUID) {
            images[id] = image
            order.removeAll { $0 == id }
            order.append(id)
            if order.count > limit {
                images[order.removeFirst()] = nil
            }
        }

        mutating func remove(_ id: UUID) {
            images[id] = nil
            order.removeAll { $0 == id }
        }
    }
}
