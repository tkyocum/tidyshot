import Foundation
import Testing
@testable import TidyShot

/// `SaveLocation.moveInScoped`, which moves a finished recording into the save folder.
struct SaveLocationMoveTests {
    let dir: URL
    let folder: URL
    let source: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        folder = dir.appending(path: "Shots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let recordings = dir.appending(path: "Recording", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        source = recordings.appending(path: "\(UUID().uuidString).mp4")
    }

    func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// From a detached task, as `saveRecording` runs it.
    @Test func theFileMovesInUnderItsNameAndTheSourceIsGone() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([1, 2, 3]).write(to: source)
        let (source, folder) = (source, folder)

        let moved = try await Task.detached {
            try SaveLocation.moveInScoped(source, baseName: "Recording 2026-10-22 at 10.00.00", ext: "mp4", folder: folder)
        }.value

        #expect(moved == folder.appending(path: "Recording 2026-10-22 at 10.00.00.mp4"))
        #expect(try Data(contentsOf: moved) == Data([1, 2, 3]))
        #expect(!exists(source))
        #expect(try contents(of: folder) == ["Recording 2026-10-22 at 10.00.00.mp4"])
    }

    @Test func aClashGetsTheNextNumber() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([9]).write(to: folder.appending(path: "Recording.mp4"))
        try Data([1, 2, 3]).write(to: source)

        let moved = try SaveLocation.moveInScoped(source, baseName: "Recording", ext: "mp4", folder: folder)

        #expect(moved.lastPathComponent == "Recording 2.mp4")
        #expect(try Data(contentsOf: moved) == Data([1, 2, 3]))
        // The file already there is untouched.
        #expect(try Data(contentsOf: folder.appending(path: "Recording.mp4")) == Data([9]))
        #expect(!exists(source))
    }

    @Test func aMissingSourceThrowsAndLeavesTheFolderEmpty() throws {
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(throws: (any Error).self) {
            try SaveLocation.moveInScoped(source, baseName: "Recording", ext: "mp4", folder: folder)
        }
        #expect(try contents(of: folder).isEmpty)
    }

    /// A folder that is gone since it was chosen fails the move, and the recording stays where it was.
    @Test func aMissingFolderThrowsAndKeepsTheSource() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([1, 2, 3]).write(to: source)
        let gone = dir.appending(path: "Gone", directoryHint: .isDirectory)

        #expect(throws: (any Error).self) {
            try SaveLocation.moveInScoped(source, baseName: "Recording", ext: "mp4", folder: gone)
        }
        #expect(try Data(contentsOf: source) == Data([1, 2, 3]))
    }
}
