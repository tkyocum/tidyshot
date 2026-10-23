import Testing
@testable import TidyShot

/// A drag clean-up whose delay is over (design, Copy File; Gap 7): it leaves a folder a card shows
/// again, waits again while the clipboard still holds Copy File's reference to the copy, and
/// otherwise removes the folder, so a copy does not stay until the next launch.
struct DragCleanupTests {
    @Test func aCardShowingTheRecordLeavesTheFolder() {
        #expect(AppCoordinator.dragCleanupStep(isShowing: true, copyFileCount: nil, changeCount: 4) == .leave)
        #expect(AppCoordinator.dragCleanupStep(isShowing: true, copyFileCount: 4, changeCount: 4) == .leave)
    }

    @Test func theClipboardStillHoldingCopyFilesReferenceWaitsAgain() {
        #expect(AppCoordinator.dragCleanupStep(isShowing: false, copyFileCount: 4, changeCount: 4) == .waitAgain)
    }

    @Test func aClipboardThatMovedOnRemovesTheFolder() {
        #expect(AppCoordinator.dragCleanupStep(isShowing: false, copyFileCount: 4, changeCount: 5) == .remove)
    }

    @Test func noCopyFileRemovesTheFolder() {
        #expect(AppCoordinator.dragCleanupStep(isShowing: false, copyFileCount: nil, changeCount: 4) == .remove)
    }
}
