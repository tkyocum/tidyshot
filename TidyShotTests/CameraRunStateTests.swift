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
        #expect(!state.stopAsked)
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
        #expect(state.stopsAfterStart(generation: start.generation) == false)
    }

    @Test func aStopRequestedWhileAStartIsInFlightStopsItWhenItReturns() {
        var state = CameraRunState()
        let start = state.request(true)
        _ = state.request(false)
        #expect(state.stopsAfterStart(generation: start.generation) == true)
    }

    @Test func offOnOffWhileAStartIsInFlightStopsTheFirstStart() {
        var state = CameraRunState()
        let first = state.request(true)
        _ = state.request(false)
        let second = state.request(true)
        _ = state.request(false)
        #expect(state.stopsAfterStart(generation: first.generation) == true)
        #expect(state.stopsAfterStart(generation: second.generation) == true)
    }

    /// An older start stops; the latest one, still wanted, keeps running.
    @Test func onlyTheLatestWantedStartKeepsRunning() {
        var state = CameraRunState()
        let first = state.request(true)
        _ = state.request(false)
        let second = state.request(true)
        #expect(state.stopsAfterStart(generation: first.generation) == true)
        #expect(state.stopsAfterStart(generation: second.generation) == false)
    }

    /// The stop after an overtaken start is TidyShot's own, so its notification is no loss,
    /// although the bubble is meant to be on again by then, and the latest start brings nothing back.
    @Test func theStopAfterAnOvertakenStartIsNotALoss() {
        var state = CameraRunState()
        let first = state.request(true)
        _ = state.request(false)
        _ = state.request(true)
        _ = state.request(false)
        let latest = state.request(true)
        #expect(state.stopsAfterStart(generation: first.generation) == true)
        #expect(state.handle(.didStopRunning) == .none)
        #expect(!state.isLost)
        #expect(state.stopsAfterStart(generation: latest.generation) == false)
        #expect(state.handle(.didStartRunning) == .none)
    }

    /// The bubble turned on again after the stop was decided but before its notification came.
    @Test func aStopDecidedWhileOffIsNotALossOnceOnAgain() {
        var state = CameraRunState()
        let start = state.request(true)
        _ = state.request(false)
        #expect(state.stopsAfterStart(generation: start.generation) == true)
        _ = state.request(true)
        #expect(state.handle(.didStopRunning) == .none)
        #expect(!state.isLost)
    }

    /// One asked-for stop excuses one notification; the next stop while on is a loss.
    @Test func anAskedForStopExcusesOneNotification() {
        var state = CameraRunState()
        let first = state.request(true)
        _ = state.request(false)
        _ = state.request(true)
        _ = state.stopsAfterStart(generation: first.generation)
        _ = state.handle(.didStopRunning)
        #expect(state.handle(.didStopRunning) == .lost)
    }

    /// A start that keeps running asks for no stop, so a stop after it is a loss.
    @Test func aKeptStartAsksForNoStop() {
        var state = CameraRunState()
        let start = state.request(true)
        #expect(state.stopsAfterStart(generation: start.generation) == false)
        #expect(state.handle(.didStopRunning) == .lost)
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
