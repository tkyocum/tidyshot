/// The camera session's run rules (design, Webcam bubble, The camera session), held on the
/// camera's queue: which start is still wanted, which notification is a loss, when the picture
/// comes back and when a reconnected camera is rebuilt.
nonisolated struct CameraRunState: Equatable, Sendable {
    /// The session's and the device's notifications.
    enum Event: Equatable, Sendable {
        case runtimeError
        case wasInterrupted
        case interruptionEnded
        case didStopRunning
        case didStartRunning
        case deviceDisconnected
        case deviceConnected
    }

    /// What an event asks of the bubble and the session.
    enum Change: Equatable, Sendable {
        case none
        case lost
        case back
        case rebuild
    }

    /// The latest request: the bubble is meant to be on.
    private(set) var wantsOn = false
    /// Bumped by every request, so a start that returns late can tell it was overtaken.
    private(set) var generation = 0
    private(set) var isLost = false
    /// The camera came back while the bubble was off; the next on rebuilds the session.
    private(set) var rebuildPending = false
    /// A stop `stopsAfterStart` asked for whose notification has not come yet. The bubble may be
    /// meant to be on again by then, so the request alone cannot excuse it.
    private(set) var stopAsked = false

    /// Records a request before the queue acts on it. Turning on clears a loss and takes a
    /// waiting rebuild, once.
    mutating func request(_ on: Bool) -> (generation: Int, rebuild: Bool) {
        wantsOn = on
        generation += 1
        var rebuild = false
        if on {
            isLost = false
            rebuild = rebuildPending
            rebuildPending = false
        }
        return (generation, rebuild)
    }

    /// After `startRunning` returns: stop again if a later request overtook this start or the
    /// latest request was off. A stop it asks for is recorded, so its notification is no loss.
    mutating func stopsAfterStart(generation: Int) -> Bool {
        let stops = generation != self.generation || !wantsOn
        if stops { stopAsked = true }
        return stops
    }

    /// A stop TidyShot asked for is no loss: it comes after `stopsAfterStart` said stop, or while
    /// the bubble is meant to be off.
    mutating func handle(_ event: Event) -> Change {
        switch event {
        case .didStopRunning where stopAsked:
            stopAsked = false
            return .none
        case .runtimeError, .wasInterrupted, .didStopRunning, .deviceDisconnected:
            guard wantsOn, !isLost else { return .none }
            isLost = true
            return .lost
        case .interruptionEnded, .didStartRunning:
            guard wantsOn, isLost else { return .none }
            isLost = false
            return .back
        case .deviceConnected:
            guard wantsOn else {
                rebuildPending = true
                return .none
            }
            return .rebuild
        }
    }
}
