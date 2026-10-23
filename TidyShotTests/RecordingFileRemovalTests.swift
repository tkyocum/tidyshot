import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// `Recording.removeFiles`, the live removal behind a discard: one task removes the files in the
/// order given, so a discarded recording's file goes before its mute log (design, Privacy rule).
@Suite(.timeLimit(.minutes(1)))
struct RecordingFileRemovalTests {
    /// The URLs a fake removal was given, in the order it finished them.
    nonisolated final class Removed: Sendable {
        private let urls = Mutex<[URL]>([])

        var all: [URL] {
            urls.withLock { $0 }
        }

        func append(_ url: URL) {
            urls.withLock { $0.append(url) }
        }
    }

    struct Failed: Error {}

    let file = URL(filePath: "/private/tmp/RecordingFileRemovalTests/Recording/A.mp4")
    let log = URL(filePath: "/private/tmp/RecordingFileRemovalTests/Mute/A.json")

    /// The file's removal is slow, so a removal that ran the two side by side would finish the log
    /// first.
    @Test func theFileGoesBeforeItsLog() async {
        let removed = Removed()
        let file = file
        await Recording.removeFiles(at: [file, log]) { url in
            if url == file { Thread.sleep(forTimeInterval: 0.05) }
            removed.append(url)
        }.value
        #expect(removed.all == [file, log])
    }

    /// A file that stays keeps its log, so the next launch mutes it.
    @Test func aFileThatCannotBeRemovedKeepsItsLog() async {
        let removed = Removed()
        let file = file
        await Recording.removeFiles(at: [file, log]) { url in
            if url == file { throw Failed() }
            removed.append(url)
        }.value
        #expect(removed.all.isEmpty)
    }

    @Test func aFileAlreadyGoneStillTakesItsLog() async {
        let removed = Removed()
        let file = file
        await Recording.removeFiles(at: [file, log]) { url in
            if url == file { throw CocoaError(.fileNoSuchFile) }
            removed.append(url)
        }.value
        #expect(removed.all == [log])
    }

    @Test func theLiveRemovalDeletesEachFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "RecordingFileRemovalTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = [dir.appending(path: "A.mp4"), dir.appending(path: "A.json")]
        for url in urls {
            try Data([1]).write(to: url)
        }
        await Recording.removeFiles(at: urls).value
        #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) })
    }
}
