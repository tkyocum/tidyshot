import Foundation
import Testing
@testable import TidyShot

/// The harness itself (harness design 2.4): a coordinator over a world of temp folders and fakes starts
/// empty, keeps its files in the world's folders, and reaches the world's settings and destination.
struct CoordinatorWorldTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    @Test func aCoordinatorOverTheWorldKeepsToTheWorld() throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()

        #expect(coordinator.history.records.isEmpty)
        #expect(coordinator.history.fileURL == world.historyFileURL)
        #expect(coordinator.pendingFiles.directory.deletingLastPathComponent().path(percentEncoded: false)
                == world.historyFileURL.deletingLastPathComponent().path(percentEncoded: false))
        #expect(coordinator.dragFiles.directory.deletingLastPathComponent().path(percentEncoded: false)
                == world.temporaryDirectory.path(percentEncoded: false))
        #expect(coordinator.settings === world.settings)
        #expect(coordinator.recordingPhase == .idle)
        #expect(world.cards.onDidClose != nil)
        let target = try #require(coordinator.makeDestination())
        #expect(target.location == world.location)
        #expect(world.factory.askedLocations == [world.location])
        #expect(world.notifier.calls.isEmpty)
        #expect(world.logLines.isEmpty)
    }
}
