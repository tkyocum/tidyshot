import AppKit
import Foundation
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

    func record(thumbnail: String? = nil, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png")) -> CaptureRecord {
        CaptureRecord(fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 640, pixelHeight: 400, appName: "Safari")
    }

    @Test func storedThumbnailIsUsedWithoutReadingTheFile() async throws {
        let item = record()
        let name = try store.write(try png(width: 320, height: 200), id: item.id)
        var stored = item
        stored.thumbnailFileName = name
        history.add(stored)
        var reads = 0
        let provider = ThumbnailProvider(store: store, history: history) { _ in reads += 1; throw CocoaError(.fileNoSuchFile) }

        let image = await provider.thumbnail(for: stored)
        #expect(image?.size == CGSize(width: 320, height: 200))
        #expect(reads == 0)
        #expect(await provider.thumbnail(for: stored) === image)
    }

    @Test func legacyRecordGetsAThumbnailGeneratedOnceAndStored() async throws {
        let item = record()
        history.add(item)
        let data = try png(width: 640, height: 400)
        var reads = 0
        let provider = ThumbnailProvider(store: store, history: history) { _ in reads += 1; return data }

        let image = await provider.thumbnail(for: item)
        #expect(image?.size == CGSize(width: 320, height: 200))
        let name = history.record(id: item.id)?.thumbnailFileName
        #expect(name == "\(item.id.uuidString).png")
        #expect(FileManager.default.fileExists(atPath: store.url(forFileName: name ?? "").path(percentEncoded: false)))
        #expect(await provider.thumbnail(for: item) === image)
        #expect(reads == 1)
    }

    /// The negative cache: a record whose thumbnail cannot be made is tried once, not on every
    /// appearance of its cell.
    @Test func recordWithoutAReadableFileGetsAPlaceholderAndIsTriedOnce() async {
        let item = record(file: nil)
        history.add(item)
        var reads = 0
        let provider = ThumbnailProvider(store: store, history: history) { _ in reads += 1; throw CocoaError(.fileNoSuchFile) }
        #expect(await provider.thumbnail(for: item) == nil)
        #expect(await provider.thumbnail(for: item) == nil)
        #expect(reads == 1)
        #expect(history.record(id: item.id)?.thumbnailFileName == nil)
    }

    @Test func previewComesFromTheFileOrFallsBackToTheThumbnail() async throws {
        let withFile = record()
        let data = try png(width: 2000, height: 1000)
        let provider = ThumbnailProvider(store: store, history: history) { record in
            guard record.fileURL != nil else { throw CocoaError(.fileNoSuchFile) }
            return data
        }
        let preview = await provider.preview(for: withFile)
        #expect(preview?.size == CGSize(width: 1200, height: 600))
        #expect(await provider.preview(for: withFile) === preview)

        let uploadOnly = record(thumbnail: try store.write(try png(width: 300, height: 150), id: UUID()), file: nil)
        let fallback = await provider.preview(for: uploadOnly)
        #expect(fallback?.size == CGSize(width: 300, height: 150))

        provider.forget(withFile.id)
        #expect(await provider.preview(for: withFile) !== preview)
    }

    /// Runs code in the middle of a load: `readFile` is called after the load has started and
    /// before its decode finishes.
    final class ReadHook {
        var onRead: (() -> Void)?
    }

    @Test func forgetDuringALoadDiscardsIt() async throws {
        let item = record()
        let data = try png(width: 2000, height: 1000)
        let hook = ReadHook()
        let provider = ThumbnailProvider(store: store, history: history) { _ in
            hook.onRead?()
            return data
        }
        hook.onRead = { provider.forget(item.id) }
        #expect(await provider.preview(for: item) == nil)

        hook.onRead = nil
        #expect(await provider.preview(for: item)?.size == CGSize(width: 1200, height: 600))
    }
}
