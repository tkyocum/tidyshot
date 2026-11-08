import Foundation
import Testing
@testable import TidyShot

struct FileReplacementTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "FileReplacementTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    /// A new destination gets the file directly.
    @Test func putsANewFileInPlace() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        var given: URL?
        try FileReplacement.put(at: target) { url in
            given = url
            try Data("new".utf8).write(to: url)
        }
        #expect(given == target)
        #expect(try Data(contentsOf: target) == Data("new".utf8))
        #expect(try names() == ["Recording.mp4"])
    }

    /// An existing file (the save panel already asked) is replaced from a file put first into the
    /// replacement folder for it, which is gone afterwards.
    @Test func replacesAnExistingFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        try Data("old contents that are longer".utf8).write(to: target)
        var given: URL?
        try FileReplacement.put(at: target) { url in
            given = url
            try Data("new".utf8).write(to: url)
        }
        let staged = try #require(given)
        #expect(staged != target)
        #expect(staged.lastPathComponent == "Recording.mp4")
        #expect(!exists(staged.deletingLastPathComponent()))
        #expect(try Data(contentsOf: target) == Data("new".utf8))
        #expect(try names() == ["Recording.mp4"])
    }

    /// A failed put leaves an existing file as it was, and the replacement folder goes.
    @Test func aFailedPutKeepsTheExistingFile() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        try Data("mine".utf8).write(to: target)
        var given: URL?
        #expect(throws: CocoaError.self) {
            try FileReplacement.put(at: target) { url in
                given = url
                try Data("partial".utf8).write(to: url)
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        #expect(try Data(contentsOf: target) == Data("mine".utf8))
        #expect(try names() == ["Recording.mp4"])
        let staged = try #require(given)
        #expect(!exists(staged.deletingLastPathComponent()))
    }

    /// A failed put for a new destination throws and replaces nothing.
    @Test func aFailedPutForANewFileThrows() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let target = folder.appending(path: "Recording.mp4")
        #expect(throws: CocoaError.self) {
            try FileReplacement.put(at: target) { _ in throw CocoaError(.fileNoSuchFile) }
        }
        #expect(try names().isEmpty)
    }
}
