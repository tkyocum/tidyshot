import Foundation
import Testing
@testable import TidyShot

struct PendingFileStoreTests {
    let dir: URL

    init() {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    @Test func writePutsTheFileInsideTheFolderAndRemoveIgnoresAMissingFile() throws {
        let store = PendingFileStore(nextTo: dir.appending(path: "history.json"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let url = try store.write(Data("png".utf8), id: id, ext: "png")
        #expect(url.lastPathComponent == "\(id.uuidString).png")
        #expect(url.deletingLastPathComponent().lastPathComponent == PendingFileStore.directoryName)
        #expect(try Data(contentsOf: url) == Data("png".utf8))

        try store.remove(url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        try store.remove(url)
    }

    /// Anything but "already gone" is reported, so Delete keeps the record and says why.
    @Test func removeThrowsWhenTheFileCannotBeDeleted() throws {
        let store = PendingFileStore(directory: dir.appending(path: "pending"))
        let url = try store.write(Data([1]), id: UUID(), ext: "png")
        let folder = store.directory.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
            try? FileManager.default.removeItem(at: dir)
        }

        #expect(throws: (any Error).self) { try store.remove(url) }
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }
}
