import Foundation
import Testing
@testable import TidyShot

struct SaveLocationOverwriteTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir.appending(path: "Shots"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "Elsewhere"), withIntermediateDirectories: true)
    }

    @Test func overwriteReplacesBytesKeepsName() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "Shots", directoryHint: .isDirectory)
        let file = folder.appending(path: "Screenshot 2026-10-20 at 10.00.00.png")
        try Data([1, 2, 3]).write(to: file)

        try SaveLocation.overwriteScoped(Data([4, 5, 6, 7]), at: file, folder: folder)

        #expect(try Data(contentsOf: file) == Data([4, 5, 6, 7]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
                == ["Screenshot 2026-10-20 at 10.00.00.png"])
    }

    @Test func overwriteRefusesFileOutsideFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "Shots", directoryHint: .isDirectory)
        let outside = dir.appending(path: "Elsewhere/a.png")
        try Data([1, 2, 3]).write(to: outside)

        let error = #expect(throws: CocoaError.self) {
            try SaveLocation.overwriteScoped(Data([9]), at: outside, folder: folder)
        }
        #expect(error?.code == .fileWriteNoPermission)
        #expect(try Data(contentsOf: outside) == Data([1, 2, 3]))
    }

    /// Paths are compared component by component as written; no symlink is resolved.
    @Test func containsHandlesSymlinkFreePrefixes() {
        let folder = URL(filePath: "/Users/tim/Pictures/Shots", directoryHint: .isDirectory)
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/a.png"), inFolder: folder))
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/2026/a.png"), inFolder: folder))
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/./b/../a.png"), inFolder: folder))
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/a.png"),
                                      inFolder: URL(filePath: "/Users/tim/Pictures/Shots/")))
        // A sibling whose name starts with the folder's name is not inside it.
        #expect(!SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots 2/a.png"), inFolder: folder))
        #expect(!SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shotsa.png"), inFolder: folder))
        #expect(!SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/../a.png"), inFolder: folder))
        #expect(!SaveLocation.contains(folder, inFolder: folder))
        #expect(!SaveLocation.contains(URL(string: "https://snap.tky.io/Users/tim/Pictures/Shots/a.png")!, inFolder: folder))
    }
}
