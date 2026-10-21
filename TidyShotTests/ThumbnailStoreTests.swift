import Foundation
import Testing
@testable import TidyShot

struct ThumbnailStoreTests {
    let dir: URL

    init() {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    @Test func storeSitsNextToHistoryFile() {
        let store = ThumbnailStore(nextTo: dir.appending(path: "TidyShot/history.json"))
        #expect(store.directory.path(percentEncoded: false) == dir.appending(path: "TidyShot/thumbnails").path(percentEncoded: false) + "/")
    }

    @Test func writeCreatesFolderAndReturnsFileName() throws {
        let store = ThumbnailStore(directory: dir.appending(path: "thumbnails"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let name = try store.write(Data([1, 2, 3]), id: id)
        #expect(name == "\(id.uuidString).png")
        #expect(try Data(contentsOf: store.url(forFileName: name)) == Data([1, 2, 3]))

        store.remove(fileName: name)
        #expect(!FileManager.default.fileExists(atPath: store.url(forFileName: name).path(percentEncoded: false)))
        store.remove(fileName: name)
    }

    /// An edit gets a new name per save, so rows keyed on the name reload, and the capture-time
    /// writer (`<UUID>.png` only) can never overwrite it.
    @Test func editedFileNameDiffersAndIsDeterministic() throws {
        let store = ThumbnailStore(directory: dir.appending(path: "thumbnails"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!
        let edited = Date(timeIntervalSince1970: 1_792_411_200.123)

        #expect(store.fileName(for: id, editedAt: nil) == "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B.png")
        #expect(store.fileName(for: id, editedAt: edited) == "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B-1792411200123.png")
        #expect(store.fileName(for: id, editedAt: edited) == store.fileName(for: id, editedAt: edited))
        #expect(store.fileName(for: id, editedAt: edited.addingTimeInterval(1)) != store.fileName(for: id, editedAt: edited))

        let name = try store.write(Data([7, 8]), fileName: store.fileName(for: id, editedAt: edited))
        #expect(name == "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B-1792411200123.png")
        #expect(try Data(contentsOf: store.url(forFileName: name)) == Data([7, 8]))
        #expect(!FileManager.default.fileExists(atPath: store.url(forFileName: store.fileName(for: id)).path(percentEncoded: false)))
    }
}
