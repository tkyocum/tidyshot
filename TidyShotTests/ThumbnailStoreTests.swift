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
}
