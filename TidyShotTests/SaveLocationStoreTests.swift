import Foundation
import Testing
@testable import TidyShot

/// `store(_:)`, which every folder panel lands in (Settings > General's Choose… and a save's own,
/// through `ensureFolder`): the folder becomes current and `didStoreFolder` is told, so the cards'
/// Trim items follow a folder chosen at either.
struct SaveLocationStoreTests {
    @Test func storingAFolderMakesItCurrentThenTellsTheHook() throws {
        let suite = "SaveLocationStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let location = SaveLocation(defaults: defaults)
        var seen: [URL?] = []
        location.didStoreFolder = { [unowned location] in seen.append(location.currentURL) }
        try location.store(folder)
        #expect(seen == [folder])
    }
}
