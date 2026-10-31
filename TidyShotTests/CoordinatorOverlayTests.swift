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

    var destination: FakeDestination { world.factory.standard }

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

    /// phase-6a:158 (:161), full with `CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore`
    /// (the editor cases); this test pins the delete under way. A closed card whose Delete was confirmed and is
    /// still aborting its stored upload (the Abort held) is not restorable: `canRestoreClosedOverlay` is false, so
    /// the menu item stays disabled (StatusMenuController.swift:115), and the shortcut's `restoreClosedOverlay()`
    /// shows nothing and keeps the id. Once the delete ends the record is gone and the card is closed as deleted.
    /// Network Link Conditioner's `100% Loss` is the held Abort.
    @Test func aCardWhoseDeleteIsUnderWayIsNotRestorable() async throws {
        defer { world.removeAll() }
        destination.state.withLock { $0.holdingAbortsRemaining = 1 }
        defer { destination.releaseAborts() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
        try CoordinatorWorld.writeSparseFile(at: url, byteCount: 3)
        let stored = MultipartUploadState(uploadID: "stored-1", key: "s/STORED.mp4", location: world.location,
                                          partSize: 262_144, byteCount: 3, sourceModified: Date(),
                                          sourcePath: "/nowhere/Recording.mp4", startedAt: Date())
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."), mediaKind: .video,
                                   durationSeconds: 10, byteCount: 3, multipart: stored)
        coordinator.history.add(record)
        world.cards.showing.insert(id)
        world.cards.close(recordID: id, reason: .user)
        #expect(coordinator.closedOverlays.ids == [id])
        #expect(coordinator.canRestoreClosedOverlay)
        let delete = Task { await coordinator.deleteCapture(recordID: id) }
        defer { delete.cancel() }
        let watch = TaskWatch(delete)
        try await eventually { destination.state.withLock { $0.aborts.count } == 1 }
        #expect(world.confirm.asked == [.delete(record)])
        #expect(coordinator.deletingIDs.contains(id))
        try #require(!coordinator.canRestoreClosedOverlay)
        await coordinator.restoreClosedOverlay()
        #expect(!world.cards.calls.contains(.show(id)))
        #expect(coordinator.closedOverlays.ids == [id])
        destination.releaseAborts()
        try await eventually { watch.hasReturned }
        await delete.value
        #expect(coordinator.history.record(id: id) == nil)
        #expect(world.cards.calls.contains(.close(id, .deleted)))
        #expect(!coordinator.canRestoreClosedOverlay)
    }
}
