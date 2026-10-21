import Foundation

/// Turns the result of each auto-scroll step into the next move (spec 2.8, Settling and the end).
/// One detector per session. Manual mode has none: the user clicks Done.
nonisolated struct ScrollEndDetector: Sendable {
    enum EndReason: Equatable, Sendable {
        case reachedEnd
        case heightLimit
    }

    enum EndDecision: Equatable, Sendable {
        /// The step worked; scroll again.
        case `continue`
        /// Nothing moved: wait, then look again (lazy loading may add content).
        case retryAfter(Duration)
        /// The first step moved backwards: flip the scroll direction, once.
        case reverseDirection
        /// The place was lost: halve the next step.
        case shrinkStep
        /// Three losses in a row: stop scrolling and let the user take over.
        case handOver
        case end(EndReason)
    }

    /// How long the first `.still` waits before the second look.
    static let retryDelay: Duration = .milliseconds(700)
    /// Losses in a row that hand over to manual mode.
    static let lossesBeforeHandOver = 3

    private var decisions = 0
    private var stills = 0
    private var losses = 0

    /// `isFull` is `StitchStep.isFull`: the output reached `ScrollCaptureLimits.maxPixelHeight`.
    ///
    /// - `.moved` forward resets both counts. Backwards on the very first step reverses the
    ///   direction once (natural scrolling may invert synthetic deltas); backwards later counts as
    ///   a loss, so a page that scrolls the wrong way hands over instead of looping.
    /// - The first `.still` retries after 700 ms and a second one ends with `.reachedEnd`; a loss
    ///   in between restarts that count.
    /// - `.lost` halves the next step; the third in a row (a `.still` breaks the run) hands over.
    mutating func decide(after match: OverlapMatch, isFull: Bool = false) -> EndDecision {
        let isFirst = decisions == 0
        decisions += 1
        if isFull { return .end(.heightLimit) }
        switch match {
        case .moved(let dy, _, _, _):
            if dy > 0 {
                stills = 0
                losses = 0
                return .continue
            }
            if isFirst { return .reverseDirection }
            return registerLoss()
        case .still:
            losses = 0
            stills += 1
            return stills == 1 ? .retryAfter(Self.retryDelay) : .end(.reachedEnd)
        case .lost:
            return registerLoss()
        }
    }

    private mutating func registerLoss() -> EndDecision {
        stills = 0
        losses += 1
        return losses >= Self.lossesBeforeHandOver ? .handOver : .shrinkStep
    }
}
