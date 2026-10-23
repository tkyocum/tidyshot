import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The launch check of `tmp/Recording` (design, Relaunch after a crash), on a folder of its own
/// with generated movies.
@Suite(.timeLimit(.minutes(1)))
struct RecordingRecoveryTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @Test func aPlayableFileIsFoundWithItsFacts() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let url = dir.appending(path: "\(id.uuidString).mp4")
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: 2, audio: true)
        let created = try #require(try url.resourceValues(forKeys: [.creationDateKey]).creationDate)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.count == 1)
        let first = try #require(found.first)
        #expect(first.url.lastPathComponent == url.lastPathComponent)
        #expect(first.id == id)
        #expect(first.created == created)
        #expect(first.facts.isPlayable)
        #expect(abs(first.facts.duration - 2) <= 0.1)
        #expect(first.facts.naturalSize == CGSize(width: 320, height: 200))
        #expect(first.facts.videoTracks == 1)
        #expect(first.facts.audioTracks == 1)
        // A found file stays where it is, for the coordinator to move.
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    /// A crash gives no Stop, so a playable file under the end rule's 0.5 s is kept too.
    @Test func aShortPlayableFileIsFound() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "\(UUID().uuidString).mp4")
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: 0.3, audio: false)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.count == 1)
        #expect(found.first?.facts.meetsMinimum == false)
    }

    @Test func garbageIsRemovedAndAPlayableFileBesideItIsFound() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let garbage = dir.appending(path: "\(UUID().uuidString).mp4")
        try VideoFixtures.makeGarbage(at: garbage)
        let empty = dir.appending(path: "empty.mp4")
        try Data().write(to: empty)
        let playable = dir.appending(path: "\(UUID().uuidString).mp4")
        try await VideoFixtures.makeMP4(at: playable, width: 320, height: 200, seconds: 1, audio: false)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.map(\.url.lastPathComponent) == [playable.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: garbage.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: empty.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: playable.path(percentEncoded: false)))
    }

    /// A crash during a GIF's conversion leaves the MP4 and a partial GIF: the MP4 is recovered
    /// and the GIF, which does not play, removed.
    @Test func anMP4BesideAPartialGIFIsFoundAndTheGIFRemoved() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let mp4 = dir.appending(path: "\(id.uuidString).mp4")
        let gif = dir.appending(path: "\(id.uuidString).gif")
        try await VideoFixtures.makeMP4(at: mp4, width: 320, height: 200, seconds: 1, audio: false)
        // A header, a logical screen and part of a global table, as a conversion cut short leaves it.
        try Data(Array("GIF89a".utf8) + [0x40, 0x01, 0xC8, 0x00, 0xF7, 0, 0] + Array(repeating: 0x80, count: 300)).write(to: gif)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.map(\.url.lastPathComponent) == [mp4.lastPathComponent])
        #expect(found.first?.id == id)
        #expect(!FileManager.default.fileExists(atPath: gif.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: mp4.path(percentEncoded: false)))
    }

    /// The GIF's record exists, so its MP4 was saved already: only a `.gif` record with the found
    /// file's id counts.
    @Test func isSavedAsGIFHoldsOnlyForAnIDWithAGIFRecord() {
        let id = UUID()
        let found = RecordingRecovery.Found(url: URL(filePath: "/tmp/Recording/\(id.uuidString).mp4"), id: id,
                                            facts: .playable(seconds: 3), created: .now)
        func record(_ recordID: UUID, _ kind: MediaKind) -> CaptureRecord {
            CaptureRecord(id: recordID, fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, mediaKind: kind)
        }
        #expect(RecordingRecovery.isSavedAsGIF(found, records: [record(UUID(), .image), record(id, .gif)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: [record(id, .video)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: [record(id, .image)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: [record(UUID(), .gif)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: []))
        let unnamed = RecordingRecovery.Found(url: URL(filePath: "/tmp/Recording/clip.mp4"), id: nil,
                                              facts: .playable(seconds: 3), created: .now)
        #expect(!RecordingRecovery.isSavedAsGIF(unnamed, records: [record(id, .gif)]))
    }

    @Test func aMissingFolderFindsNothing() async {
        defer { try? FileManager.default.removeItem(at: dir) }
        let found = await RecordingRecovery.scan(dir.appending(path: "missing", directoryHint: .isDirectory))
        #expect(found.isEmpty)
    }

    @Test func anEmptyFolderFindsNothing() async {
        defer { try? FileManager.default.removeItem(at: dir) }
        let found = await RecordingRecovery.scan(dir)
        #expect(found.isEmpty)
    }

    @Test func aUUIDNameGivesThatIDAndAnotherNameGivesNil() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let named = dir.appending(path: "\(id.uuidString).mp4")
        let other = dir.appending(path: "clip.mp4")
        try await VideoFixtures.makeMP4(at: named, width: 320, height: 200, seconds: 1, audio: false)
        try await VideoFixtures.makeMP4(at: other, width: 320, height: 200, seconds: 1, audio: false)

        let found = await RecordingRecovery.scan(dir)
        let ids = Dictionary(uniqueKeysWithValues: found.map { ($0.url.lastPathComponent, $0.id) })
        #expect(ids.count == 2)
        #expect(ids[named.lastPathComponent] == .some(id))
        #expect(ids[other.lastPathComponent] == .some(nil))
    }
}
