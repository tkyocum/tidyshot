import Foundation
import Testing
@testable import TidyShot

struct DragFileStoreTests {
    let root: URL
    let store: DragFileStore

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "DragFileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = DragFileStore(temporaryDirectory: root)
    }

    /// A file outside the drag folder, standing in for a save-folder or `pending` file.
    func source(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let folder = root.appending(path: "pending", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(bytes).write(to: url)
        return url
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The names in `id`'s folder, sorted.
    func names(_ id: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.folder(for: id).path(percentEncoded: false))) ?? []).sorted()
    }

    /// `<tmp>/Drag/<id>/<name>`, a copy with the source's bytes; the source stays.
    @Test func stageCopiesTheSourceIntoTheRecordsFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let original = try source("\(id.uuidString).png", [1, 2, 3])
        let staged = try store.stage(id: id, name: "aSIS7.png", from: original, scope: nil)
        #expect(store.directory.lastPathComponent == DragFileStore.directoryName)
        #expect(staged.lastPathComponent == "aSIS7.png")
        #expect(staged.deletingLastPathComponent().lastPathComponent == id.uuidString)
        #expect(staged.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Drag")
        #expect(try Data(contentsOf: staged) == Data([1, 2, 3]))
        #expect(exists(original))
        #expect(store.stagedFile(id: id)?.lastPathComponent == "aSIS7.png")
    }

    /// A later stage replaces the earlier file, under a new name or the same one.
    @Test func aSecondStageReplacesTheFirst() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try store.stage(id: id, name: "Screenshot 2026-10-21 at 09.15.02.png", from: try source("a.png", [1]), scope: nil)
        let second = try store.stage(id: id, name: "aSIS7.png", from: try source("b.png", [2]), scope: nil)
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: second) == Data([2]))
        let third = try store.stage(id: id, name: "aSIS7.png", from: try source("c.png", [3]), scope: nil)
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: third) == Data([3]))
    }

    /// Staging the staged file as itself keeps it.
    @Test func stagingTheStagedFileItselfKeepsIt() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let staged = try store.stage(id: id, name: "aSIS7.png", from: try source("a.png", [1]), scope: nil)
        let again = try store.stage(id: id, name: "aSIS7.png", from: staged, scope: nil)
        #expect(again.lastPathComponent == "aSIS7.png")
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: again) == Data([1]))
    }

    /// A source that is gone throws and leaves the earlier file in place.
    @Test func stagingAMissingSourceThrowsAndKeepsTheStagedFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try store.stage(id: id, name: "aSIS7.png", from: try source("a.png", [1]), scope: nil)
        let gone = root.appending(path: "pending/gone.png")
        #expect(throws: (any Error).self) { try store.stage(id: id, name: "other.png", from: gone, scope: nil) }
        #expect(names(id) == ["aSIS7.png"])
    }

    /// The pending file moves (it is gone afterwards) and replaces the earlier clone.
    @Test func adoptMovesThePendingFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try store.stage(id: id, name: "Screenshot 2026-10-21 at 09.15.02.png", from: try source("clone.png", [1]), scope: nil)
        let pending = try source("\(id.uuidString).png", [9, 9])
        let adopted = try store.adopt(id: id, name: "aSIS7.png", moving: pending)
        #expect(!exists(pending))
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: adopted) == Data([9, 9]))
        #expect(throws: (any Error).self) { try store.adopt(id: id, name: "x.png", moving: pending) }
        #expect(names(id) == ["aSIS7.png"])
    }

    /// A restored card's download lands in its folder like a stage.
    @Test func writePutsDownloadedBytesInTheFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let url = try store.write(Data([4, 5]), id: id, name: "aSIS7.png")
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: url) == Data([4, 5]))
        #expect(store.stagedFile(id: id)?.lastPathComponent == "aSIS7.png")
    }

    /// A restored card's download under its old name is handed out under the name worked out now,
    /// as the only file in the folder.
    @Test func restageRenamesTheFoldersFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try store.write(Data([4, 5]), id: id, name: "Screenshot 2026-10-21 at 09.15.02.png")
        let restaged = try #require(store.restage(id: id, name: "aSIS7.png"))
        #expect(restaged.lastPathComponent == "aSIS7.png")
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: restaged) == Data([4, 5]))
        #expect(store.restage(id: id, name: "aSIS7.png") == restaged)
        #expect(names(id) == ["aSIS7.png"])
    }

    /// With two files left by overlapping operations, the one already under the name wins, though
    /// another sorts first; an empty or missing folder gives nil.
    @Test func restagePrefersTheFileAlreadyUnderTheName() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        #expect(store.restage(id: id, name: "aSIS7.png") == nil)
        try store.write(Data([1]), id: id, name: "aSIS7.png")
        try Data([2]).write(to: store.folder(for: id).appending(path: "Screenshot 2026-10-21 at 09.15.02.png"))
        #expect(store.stagedFile(id: id)?.lastPathComponent == "Screenshot 2026-10-21 at 09.15.02.png")
        let restaged = try #require(store.restage(id: id, name: "aSIS7.png"))
        #expect(restaged.lastPathComponent == "aSIS7.png")
        #expect(try Data(contentsOf: restaged) == Data([1]))
    }

    /// Finder's `.DS_Store` in a folder is never the drag file (it sorts before every name).
    @Test func hiddenFilesAreNeverTheStagedFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try FileManager.default.createDirectory(at: store.folder(for: id), withIntermediateDirectories: true)
        try Data([0]).write(to: store.folder(for: id).appending(path: ".DS_Store"))
        #expect(store.stagedFile(id: id) == nil)
        #expect(store.restage(id: id, name: "aSIS7.png") == nil)
        try store.write(Data([7]), id: id, name: "aSIS7.png")
        #expect(store.stagedFile(id: id)?.lastPathComponent == "aSIS7.png")
    }

    /// One record's folder goes; another's stays; removing it again is no error.
    @Test func removeDeletesOneRecordsFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = UUID()
        let removed = UUID()
        try store.write(Data([1]), id: kept, name: "a.png")
        try store.write(Data([2]), id: removed, name: "b.png")
        store.remove(id: removed)
        #expect(!exists(store.folder(for: removed)))
        #expect(store.stagedFile(id: removed) == nil)
        #expect(names(kept) == ["a.png"])
        store.remove(id: removed)
    }

    /// The launch sweep removes `Drag` and everything in it; a second sweep is no error.
    @Test func sweepRemovesTheWholeDragFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try store.write(Data([1]), id: UUID(), name: "a.png")
        try store.write(Data([2]), id: UUID(), name: "b.png")
        store.sweep()
        #expect(!exists(store.directory))
        store.sweep()
    }
}
