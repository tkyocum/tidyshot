import Foundation
import Testing
@testable import TidyShot

/// Restore Closed Overlay's memory on a built coordinator (`AppCoordinator+Overlay`, spec 2.9): in memory only.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorOverlayTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    /// phase-6a :165. After a relaunch the closed-card list is empty, so Restore Closed Overlay is disabled, while
    /// Recent Captures keeps every record.
    @Test func aRelaunchForgetsClosedCardsButKeepsTheirRecords() {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil)
        coordinator.history.add(record)
        world.cards.showing.insert(record.id)
        world.cards.close(recordID: record.id, reason: .user)
        #expect(coordinator.canRestoreClosedOverlay)

        let relaunched = world.makeCoordinator()
        relaunched.history.load()

        #expect(!relaunched.canRestoreClosedOverlay)
        #expect(relaunched.history.records.map(\.id) == [record.id])
    }
}
