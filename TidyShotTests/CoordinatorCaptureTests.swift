import Foundation
import Testing
@testable import TidyShot

/// The capture lock on a built coordinator (`withCaptureLock`): a capture command while another capture holds
/// it returns at once and reads no content (`world.source.contentReads`, the fake capture source).
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorCaptureTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    nonisolated enum Entry: CaseIterable, Sendable {
        case area
        case window
        case previousArea
    }

    /// phase-1 :25, phase-6a :215, in part. While a capture holds the lock (the selection overlay is up, or a
    /// self-timer or a scrolling session runs), Capture Area, Capture Window and Capture Previous Area (⌃⇧6)
    /// return at once and post, show and copy nothing. By hand (phase-6a :215): the disabled menu item (D16).
    @Test(arguments: Entry.allCases)
    func aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing(entry: Entry) async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let gate = TestGate()
        let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
        try await eventually { gate.isWaiting }
        let intent = CaptureIntent(action: .save)

        // Gated with `eventually`: a lock that let the capture through would read the fake content and ask the overlay.
        let capture = TaskWatch(Task {
            switch entry {
            case .area: await coordinator.captureArea(intent: intent)
            case .window: await coordinator.captureWindow(intent: intent)
            case .previousArea: await coordinator.capturePreviousArea(intent: intent)
            }
        })
        try await eventually { capture.hasReturned }

        #expect(world.notifier.calls.isEmpty)
        #expect(world.cards.calls.isEmpty)
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.source.contentReads == 0)
        #expect(coordinator.isCapturing)
        gate.open()
        _ = await lock.value
        #expect(!coordinator.isCapturing)
    }
}
