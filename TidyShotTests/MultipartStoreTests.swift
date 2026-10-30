import Foundation
import Testing
@testable import TidyShot

struct MultipartStoreTests {
    let dir: URL
    let store: MultipartStore

    init() {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        store = MultipartStore(nextTo: dir.appending(path: "history.json"))
    }

    private func sidecar(_ uploadID: String, parts: Int = 2, completeSent: Bool = false) -> MultipartSidecar {
        MultipartSidecar(uploadID: uploadID, completeSent: completeSent,
                         parts: (1...parts).map { MultipartPart(number: $0, etag: "\"etag-\($0)\"", size: 16_777_216) })
    }

    private func names() -> Set<String> {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path(percentEncoded: false))) ?? []
        return Set(entries)
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test func theFolderIsMultipartNextToTheHistoryAndFilesAreNamedByID() {
        let id = UUID()
        #expect(MultipartStore.directoryName == "multipart")
        #expect(store.directory.lastPathComponent == "multipart")
        #expect(store.directory.deletingLastPathComponent().lastPathComponent == dir.lastPathComponent)
        #expect(store.sidecarURL(for: id) == store.directory.appending(path: "\(id.uuidString).json"))
        #expect(store.keptCopyURL(for: id, ext: "mp4") == store.directory.appending(path: "\(id.uuidString).mp4"))
    }

    @Test func aWrittenSidecarReadsBackCreatingTheFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let written = sidecar("upload-1", completeSent: true)
        #expect(!exists(store.directory))

        try store.writeSidecar(written, id: id)

        #expect(store.readSidecar(id: id, uploadID: "upload-1") == written)
    }

    @Test func aMissingSidecarReadsNil() {
        #expect(store.readSidecar(id: UUID(), uploadID: "upload-1") == nil)
    }

    @Test func aCorruptSidecarReadsNil() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{\"uploadID\": \"upload-1\", \"parts\": [".utf8).write(to: store.sidecarURL(for: id))

        #expect(store.readSidecar(id: id, uploadID: "upload-1") == nil)
    }

    /// A sidecar left by an earlier upload id counts as missing.
    @Test func anotherUploadIDsSidecarReadsNil() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try store.writeSidecar(sidecar("upload-old"), id: id)

        #expect(store.readSidecar(id: id, uploadID: "upload-new") == nil)
    }

    @Test func aRewriteReplacesTheSidecarAndLeavesNoOtherFile() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try store.writeSidecar(sidecar("upload-1", parts: 1), id: id)
        let second = sidecar("upload-1", parts: 3)

        try store.writeSidecar(second, id: id)

        #expect(store.readSidecar(id: id, uploadID: "upload-1") == second)
        #expect(names() == ["\(id.uuidString).json"])
    }

    @Test func removeClearsTheSidecarAndTheKeptCopyAndNothingElse() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let other = UUID()
        try store.writeSidecar(sidecar("upload-1"), id: id)
        try Data([1, 2, 3]).write(to: store.keptCopyURL(for: id, ext: "mp4"))
        try store.writeSidecar(sidecar("upload-2"), id: other)
        try Data([4]).write(to: store.keptCopyURL(for: other, ext: "gif"))

        store.remove(id: id)

        #expect(names() == ["\(other.uuidString).json", "\(other.uuidString).gif"])
        store.remove(id: id)
        store.remove(id: UUID())
    }

    @Test func removeWithNoFolderIsNotAnError() {
        store.remove(id: UUID())
        #expect(!exists(store.directory))
    }

    /// Clop's result is moved out of `tmp/Clop` (which launch removes) into `multipart/<id>.mp4`.
    @Test func keepClopCopyMovesTheFileInAndTheSourceIsGone() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appending(path: "clop-result.mp4")
        try Data([1, 2, 3]).write(to: source)
        let id = UUID()

        let kept = try store.keepClopCopy(source, id: id, ext: "mp4")

        #expect(kept == store.directory.appending(path: "\(id.uuidString).mp4"))
        #expect(kept.deletingLastPathComponent().lastPathComponent == "multipart")
        #expect(try Data(contentsOf: kept) == Data([1, 2, 3]))
        #expect(!exists(source))
    }

    @Test func keepClopCopyReplacesAnEarlierCopy() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data([9, 9]).write(to: store.keptCopyURL(for: id, ext: "mp4"))
        let source = dir.appending(path: "clop-result.mp4")
        try Data([1, 2, 3]).write(to: source)

        let kept = try store.keepClopCopy(source, id: id, ext: "mp4")

        #expect(try Data(contentsOf: kept) == Data([1, 2, 3]))
        #expect(!exists(source))
    }

    /// A missing source throws and leaves an earlier copy in place.
    @Test func keepClopCopyOfAMissingFileThrowsAndKeepsTheEarlierCopy() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data([9, 9]).write(to: store.keptCopyURL(for: id, ext: "mp4"))

        #expect(throws: (any Error).self) {
            try store.keepClopCopy(dir.appending(path: "gone.mp4"), id: id, ext: "mp4")
        }
        #expect(try Data(contentsOf: store.keptCopyURL(for: id, ext: "mp4")) == Data([9, 9]))
    }

    @Test func sweepRemovalsDropsNoStateAndStatesOlderThanSevenDays() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let noState = UUID()
        let old = UUID()
        let recent = UUID()
        let day: TimeInterval = 86_400
        let states = [old: now.addingTimeInterval(-7 * day - 1), recent: now.addingTimeInterval(-6 * day)]

        let removals = MultipartStore.sweepRemovals(fileIDs: [noState, old, recent], states: states, now: now)

        #expect(removals == [noState, old])
    }

    /// "More than" 7 days: a state exactly 7 days old is kept. A state with no files is not listed.
    @Test func sweepRemovalsKeepsAStateExactlySevenDaysOldAndListsOnlyFileIDs() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let edge = UUID()
        let filesGone = UUID()
        let states = [edge: now.addingTimeInterval(-MultipartPlan.stateLifetime),
                      filesGone: now.addingTimeInterval(-30 * 86_400)]

        #expect(MultipartStore.sweepRemovals(fileIDs: [edge], states: states, now: now).isEmpty)
    }

    @Test func sweepLeavesOnlyTheFilesOfAStateYoungerThanSevenDays() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let noState = UUID()
        let old = UUID()
        let recent = UUID()
        for id in [noState, old, recent] {
            try store.writeSidecar(sidecar("upload-\(id.uuidString)"), id: id)
            try Data([1]).write(to: store.keptCopyURL(for: id, ext: "mp4"))
        }
        let states = [old: now.addingTimeInterval(-8 * 86_400), recent: now.addingTimeInterval(-6 * 86_400)]

        store.sweep(states: states, now: now)

        #expect(names() == ["\(recent.uuidString).json", "\(recent.uuidString).mp4"])
    }

    /// Only a file named by a record id is ever removed as a kept copy or sidecar.
    @Test func sweepLeavesAFileNotNamedByAnID() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data([1]).write(to: store.directory.appending(path: "notes.txt"))

        store.sweep(states: [:], now: Date())

        #expect(names() == ["notes.txt"])
    }

    @Test func sweepWithNoFolderIsNotAnError() {
        store.sweep(states: [:], now: Date())
        #expect(!exists(store.directory))
    }
}
