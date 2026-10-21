import Foundation
import Testing
@testable import TidyShot

struct ScrollEndDetectorTests {
    func moved(_ dy: Int) -> OverlapMatch { .moved(dy: dy, top: 80, bandEnd: 850, score: 1) }

    let retry = ScrollEndDetector.EndDecision.retryAfter(.milliseconds(700))

    /// The decision for each match, in order, from a fresh detector.
    func decisions(_ matches: [OverlapMatch]) -> [ScrollEndDetector.EndDecision] {
        var detector = ScrollEndDetector()
        return matches.map { detector.decide(after: $0) }
    }

    @Test func movingForwardContinues() {
        #expect(decisions([moved(462), moved(300)]) == [.continue, .continue])
    }

    @Test func twoStillsEndAfterTheLazyLoadRetry() {
        #expect(decisions([moved(462), .still, .still]) == [.continue, retry, .end(.reachedEnd)])
    }

    @Test func movementAfterTheRetryResetsTheStillCount() {
        // The lazy-loaded content arrived: the page moved after all.
        #expect(decisions([.still, moved(200), .still, .still]) == [retry, .continue, retry, .end(.reachedEnd)])
    }

    @Test func aFirstStepBackwardsReversesTheDirectionOnce() {
        // Backwards later is not a second reversal: it counts as a loss.
        #expect(decisions([moved(-231), moved(231), moved(-100)]) == [.reverseDirection, .continue, .shrinkStep])
        #expect(decisions([moved(-231), moved(-231)]) == [.reverseDirection, .shrinkStep])
    }

    @Test func aBackwardsStepAfterAForwardOneIsNotReversed() {
        #expect(decisions([moved(231), moved(-100)]) == [.continue, .shrinkStep])
    }

    @Test func lossesShrinkTheStepAndThreeInARowHandOver() {
        #expect(decisions([moved(231), .lost, .lost, .lost]) == [.continue, .shrinkStep, .shrinkStep, .handOver])
    }

    @Test func movementOrStillnessBreaksTheRunOfLosses() {
        let expected: [ScrollEndDetector.EndDecision] = [.shrinkStep, .shrinkStep, .continue, .shrinkStep, .shrinkStep,
                                                         retry, .shrinkStep, .shrinkStep, .handOver]
        #expect(decisions([.lost, .lost, moved(100), .lost, .lost, .still, .lost, .lost, .lost]) == expected)
    }

    /// A loss between two stills means the page changed, so the end has not been reached.
    @Test func aLossRestartsTheStillCount() {
        #expect(decisions([.still, .lost, .still]) == [retry, .shrinkStep, retry])
    }

    @Test func theHeightCapEndsWhateverTheMatchWas() {
        for match in [moved(462), .lost, .still, moved(-5)] as [OverlapMatch] {
            var detector = ScrollEndDetector()
            #expect(detector.decide(after: match, isFull: true) == .end(.heightLimit))
        }
        // After a normal step, too.
        var detector = ScrollEndDetector()
        let first = detector.decide(after: moved(462))
        let second = detector.decide(after: moved(462), isFull: true)
        #expect(first == .continue)
        #expect(second == .end(.heightLimit))
    }

    @Test func aSessionThatNeverMovesEndsOnTheSecondStill() {
        #expect(decisions([.still, .still]) == [retry, .end(.reachedEnd)])
    }
}
