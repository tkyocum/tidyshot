import Testing
@testable import TidyShot

/// The camera session's run rules: requests, starts in flight, losses and rebuilds (design,
/// Webcam bubble, The camera session).
struct CameraRunStateTests {
    nonisolated static let losses: [CameraRunState.Event] = [
        .runtimeError, .wasInterrupted, .didStopRunning, .deviceDisconnected,
    ]

    @Test func itStartsOff() {
        let state = CameraRunState()
        #expect(!state.wantsOn)
        #expect(state.generation == 0)
        #expect(!state.isLost)
        #expect(!state.rebuildPending)
    }

    @Test func eachRequestBumpsTheGeneration() {
        var state = CameraRunState()
        #expect(state.request(true) == (generation: 1, rebuild: false))
        #expect(state.wantsOn)
        #expect(state.request(false) == (generation: 2, rebuild: false))
        #expect(!state.wantsOn)
    }

    // MARK: A start in flight

    @Test func aStartThatReturnsUnchallengedKeepsRunning() {
        var state = CameraRunState()
        let start = state.request(true)
        #expect(!state.stopsAfterStart(generation: start.generation))
    }

    @Test func aStopRequestedWhileAStartIsInFlightStopsItWhenItReturns() {
        var state = CameraRunState()
        let start = state.request(true)
        _ = state.request(false)
        #expect(state.stopsAfterStart(generation: start.generation))
    }

    @Test func offOnOffWhileAStartIsInFlightStopsTheFirstStart() {
        var state = CameraRunState()
        let first = state.request(true)
        _ = state.request(false)
        let second = state.request(true)
        _ = state.request(false)
        #expect(state.stopsAfterStart(generation: first.generation))
        #expect(state.stopsAfterStart(generation: second.generation))
    }

    /// An older start stops; the latest one, still wanted, keeps running.
    @Test func onlyTheLatestWantedStartKeepsRunning() {
        var state = CameraRunState()
        let first = state.request(true)
        _ = state.request(false)
        let second = state.request(true)
        #expect(state.stopsAfterStart(generation: first.generation))
        #expect(!state.stopsAfterStart(generation: second.generation))
    }

    // MARK: Losses

    @Test func aStopTidyShotAskedForIsNotALoss() {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.request(false)
        #expect(state.handle(.didStopRunning) == .none)
        #expect(!state.isLost)
    }

    @Test(arguments: losses)
    func aLossWhileMeantToBeOn(event: CameraRunState.Event) {
        var state = CameraRunState()
        _ = state.request(true)
        #expect(state.handle(event) == .lost)
        #expect(state.isLost)
    }

    @Test(arguments: losses)
    func aLossIsReportedOnce(event: CameraRunState.Event) {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.handle(.runtimeError)
        #expect(state.handle(event) == .none)
    }

    @Test(arguments: losses)
    func nothingIsLostWhileOff(event: CameraRunState.Event) {
        var state = CameraRunState()
        #expect(state.handle(event) == .none)
        _ = state.request(true)
        _ = state.request(false)
        #expect(state.handle(event) == .none)
        #expect(!state.isLost)
    }

    // MARK: Coming back

    @Test(arguments: [CameraRunState.Event.interruptionEnded, .didStartRunning])
    func thePictureComesBack(event: CameraRunState.Event) {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.handle(.wasInterrupted)
        #expect(state.handle(event) == .back)
        #expect(!state.isLost)
    }

    @Test(arguments: [CameraRunState.Event.interruptionEnded, .didStartRunning])
    func nothingComesBackThatWasNotLost(event: CameraRunState.Event) {
        var state = CameraRunState()
        _ = state.request(true)
        #expect(state.handle(event) == .none)
    }

    @Test func nothingComesBackWhileOff() {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.handle(.runtimeError)
        _ = state.request(false)
        #expect(state.handle(.didStartRunning) == .none)
    }

    /// After a return, a second loss is reported again.
    @Test func aLossAfterAReturnIsReported() {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.handle(.wasInterrupted)
        _ = state.handle(.interruptionEnded)
        #expect(state.handle(.deviceDisconnected) == .lost)
    }

    @Test func turningOnAgainClearsALoss() {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.handle(.runtimeError)
        _ = state.request(false)
        _ = state.request(true)
        #expect(!state.isLost)
        #expect(state.handle(.didStopRunning) == .lost)
    }

    // MARK: Reconnects

    @Test func aReconnectWhileOnRebuilds() {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.handle(.deviceDisconnected)
        #expect(state.handle(.deviceConnected) == .rebuild)
        #expect(!state.rebuildPending)
    }

    @Test func aReconnectWhileOffWaitsForTheNextOnAndOnlyThat() {
        var state = CameraRunState()
        _ = state.request(true)
        _ = state.handle(.deviceDisconnected)
        _ = state.request(false)
        #expect(state.handle(.deviceConnected) == .none)
        #expect(state.rebuildPending)
        #expect(state.request(true).rebuild)
        #expect(!state.rebuildPending)
        _ = state.request(false)
        #expect(!state.request(true).rebuild)
    }

    @Test func turningOffKeepsAWaitingRebuild() {
        var state = CameraRunState()
        _ = state.handle(.deviceConnected)
        #expect(!state.request(false).rebuild)
        #expect(state.request(true).rebuild)
    }
}
