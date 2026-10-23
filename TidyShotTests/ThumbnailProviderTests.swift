import AppKit
import Foundation
import Synchronization
import Testing
@testable import TidyShot

struct ThumbnailProviderTests {
    let dir: URL
    let history: HistoryStore
    let store: ThumbnailStore

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        history = HistoryStore(fileURL: dir.appending(path: "history.json"))
        store = ThumbnailStore(nextTo: dir.appending(path: "history.json"))
    }

    func png(width: Int, height: Int) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try ImageEncoder.pngData(from: context.makeImage()!, scale: 1)
    }

    /// A provider whose save folder is `dir`, reading through `read`.
    func makeProvider(_ read: @escaping ThumbnailProvider.FileReader) -> ThumbnailProvider {
        ThumbnailProvider(store: store, history: history, saveFolder: { [dir] in dir }, readFile: read)
    }

    func record(thumbnail: String? = nil, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png")) -> CaptureRecord {
        CaptureRecord(fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 640, pixelHeight: 400, appName: "Safari")
    }

    @Test func storedThumbnailIsUsedWithoutReadingTheFile() async throws {
        let item = record()
        let name = try store.write(try png(width: 320, height: 200), id: item.id)
        var stored = item
        stored.thumbnailFileName = name
        history.add(stored)
        let reads = Mutex(0)
        let provider = makeProvider { _, _ in reads.withLock { $0 += 1 }; throw CocoaError(.fileNoSuchFile) }

        let image = await provider.thumbnail(for: stored)
        #expect(image?.size == CGSize(width: 320, height: 200))
        #expect(reads.withLock { $0 } == 0)
        #expect(await provider.thumbnail(for: stored) === image)
    }

    @Test func legacyRecordGetsAThumbnailGeneratedOnceAndStored() async throws {
        let item = record()
        history.add(item)
        let data = try png(width: 640, height: 400)
        let reads = Mutex<[URL?]>([])
        let provider = makeProvider { _, folder in reads.withLock { $0.append(folder) }; return data }

        let image = await provider.thumbnail(for: item)
        #expect(image?.size == CGSize(width: 320, height: 200))
        let name = history.record(id: item.id)?.thumbnailFileName
        #expect(name == "\(item.id.uuidString).png")
        #expect(FileManager.default.fileExists(atPath: store.url(forFileName: name ?? "").path(percentEncoded: false)))
        #expect(await provider.thumbnail(for: item) === image)
        // Read once, through the save folder's scope.
        #expect(reads.withLock { $0 } == [dir])
    }

    /// The negative cache: a record whose thumbnail cannot be made is tried once, not on every
    /// appearance of its cell. A record with no local file is never read at all.
    @Test func recordWithoutAReadableFileGetsAPlaceholderAndIsTriedOnce() async {
        let item = record()
        let noFile = record(file: nil)
        history.add(item)
        history.add(noFile)
        let reads = Mutex(0)
        let provider = makeProvider { _, _ in reads.withLock { $0 += 1 }; throw CocoaError(.fileNoSuchFile) }
        #expect(await provider.thumbnail(for: item) == nil)
        #expect(await provider.thumbnail(for: item) == nil)
        #expect(reads.withLock { $0 } == 1)
        #expect(history.record(id: item.id)?.thumbnailFileName == nil)

        #expect(await provider.thumbnail(for: noFile) == nil)
        #expect(reads.withLock { $0 } == 1)
    }

    @Test func previewComesFromTheFileOrFallsBackToTheThumbnail() async throws {
        let withFile = record()
        let data = try png(width: 2000, height: 1000)
        let provider = makeProvider { _, _ in data }
        let preview = await provider.preview(for: withFile)
        #expect(preview?.size == CGSize(width: 1200, height: 600))
        #expect(await provider.preview(for: withFile) === preview)

        let uploadOnly = record(thumbnail: try store.write(try png(width: 300, height: 150), id: UUID()), file: nil)
        let fallback = await provider.preview(for: uploadOnly)
        #expect(fallback?.size == CGSize(width: 300, height: 150))

        provider.forget(withFile.id)
        #expect(await provider.preview(for: withFile) !== preview)
    }

    /// A preview call that is already cancelled gets no thumbnail fallback, also for a record
    /// with no local file (an upload-only capture), which would otherwise read the thumbnail.
    @Test func cancelledPreviewSkipsTheThumbnailFallback() async throws {
        let uploadOnly = record(thumbnail: try store.write(try png(width: 300, height: 150), id: UUID()), file: nil)
        let provider = makeProvider { _, _ in throw CocoaError(.fileNoSuchFile) }
        let load = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            return await provider.preview(for: uploadOnly) == nil
        }
        #expect(await load.value)
        #expect(await provider.preview(for: uploadOnly)?.size == CGSize(width: 300, height: 150))
    }

    func video(thumbnail: String? = nil, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Recording.mp4"),
               temporary: Bool = false) -> CaptureRecord {
        CaptureRecord(fileURL: file, fileIsTemporary: temporary, thumbnailFileName: thumbnail, pixelWidth: 1600,
                      pixelHeight: 1000, appName: nil, mediaKind: .video, durationSeconds: 42)
    }

    /// A video's file is never read: its thumbnail and its hover preview are the stored 320 px
    /// poster, at its own size.
    @Test func aVideosPreviewIsItsStoredThumbnail() async throws {
        let item = video(thumbnail: try store.write(try png(width: 320, height: 200), id: UUID()))
        history.add(item)
        let data = try png(width: 2000, height: 1250)
        let reads = Mutex(0)
        let provider = makeProvider { _, _ in reads.withLock { $0 += 1 }; return data }
        #expect(await provider.thumbnail(for: item)?.size == CGSize(width: 320, height: 200))
        #expect(await provider.preview(for: item)?.size == CGSize(width: 320, height: 200))
        #expect(reads.withLock { $0 } == 0)
    }

    /// A video with no stored thumbnail gets the placeholder (nil), from a save-folder or a pending
    /// file alike, and no thumbnail is made from its file.
    @Test func aVideoWithoutAThumbnailIsNeverRead() async throws {
        let saved = video()
        let pending = video(file: URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).mp4"), temporary: true)
        history.add(saved)
        history.add(pending)
        let data = try png(width: 640, height: 400)
        let reads = Mutex(0)
        let provider = makeProvider { _, _ in reads.withLock { $0 += 1 }; return data }
        for item in [saved, pending] {
            #expect(await provider.thumbnail(for: item) == nil)
            #expect(await provider.preview(for: item) == nil)
            #expect(history.record(id: item.id)?.thumbnailFileName == nil)
        }
        #expect(reads.withLock { $0 } == 0)
    }

    /// `forget` runs while the load's read is in progress in its detached task: the reader
    /// blocks until the test has called it.
    @Test func forgetDuringALoadDiscardsIt() async throws {
        let item = record()
        let data = try png(width: 2000, height: 1000)
        let blocking = Mutex(true)
        let reading = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let provider = makeProvider { _, _ in
            if blocking.withLock({ $0 }) {
                reading.withLock { $0 = true }
                release.wait()
            }
            return data
        }
        let load = Task { await provider.preview(for: item)?.size }
        try await eventually { reading.withLock { $0 } }
        provider.forget(item.id)
        release.signal()
        #expect(await load.value == nil)

        blocking.withLock { $0 = false }
        #expect(await provider.preview(for: item)?.size == CGSize(width: 1200, height: 600))
    }
}
