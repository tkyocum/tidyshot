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

    /// A recording is renamed in, never copied: the source is gone and the bytes are the same.
    @Test func moveInMakesTheIDsFileCreatingTheFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PendingFileStore(nextTo: dir.appending(path: "history.json"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appending(path: "recording.mp4")
        try Data([1, 2, 3]).write(to: source)
        #expect(!FileManager.default.fileExists(atPath: store.directory.path(percentEncoded: false)))
        let id = UUID()

        let url = try store.moveIn(source, id: id, ext: "mp4")

        #expect(url == store.directory.appending(path: "\(id.uuidString).mp4"))
        #expect(url.deletingLastPathComponent().lastPathComponent == PendingFileStore.directoryName)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    }

    @Test func moveInOfAMissingFileThrows() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PendingFileStore(directory: dir.appending(path: "pending"))

        #expect(throws: (any Error).self) {
            try store.moveIn(dir.appending(path: "gone.mp4"), id: UUID(), ext: "mp4")
        }
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

    /// The launch step's listing (harness design 4.2): a missing folder and an empty one list nothing.
    @Test func listOfAMissingOrEmptyFolderIsEmpty() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PendingFileStore(directory: dir.appending(path: "pending"))
        #expect(store.list().isEmpty)

        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        #expect(store.list().isEmpty)
    }

    /// Hidden files are skipped; every other file is listed.
    @Test func listSkipsHiddenFiles() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PendingFileStore(directory: dir.appending(path: "pending"))
        let url = try store.write(Data([1]), id: UUID(), ext: "png")
        try Data([2]).write(to: store.directory.appending(path: ".DS_Store"))

        #expect(store.list().map(\.lastPathComponent) == [url.lastPathComponent])
    }
}
