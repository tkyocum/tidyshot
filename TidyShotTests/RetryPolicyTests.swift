import Foundation
import Testing
@testable import TidyShot

struct RetryPolicyTests {
    @Test func defaultBackoffDoubles() {
        let policy = RetryPolicy.default
        #expect(policy.maxAttempts == 3)
        #expect(policy.delay(beforeAttempt: 1) == .zero)
        #expect(policy.delay(beforeAttempt: 2) == .seconds(1))
        #expect(policy.delay(beforeAttempt: 3) == .seconds(2))
        #expect(policy.delay(beforeAttempt: 4) == .seconds(4))
    }

    @Test func delayIsCapped() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: .seconds(1), maxDelay: .seconds(5))
        #expect(policy.delay(beforeAttempt: 6) == .seconds(5))
        #expect(policy.delay(beforeAttempt: 40) == .seconds(5))
    }

    @Test func immediatePolicyNeverWaits() {
        #expect(RetryPolicy.immediate.delay(beforeAttempt: 3) == .zero)
    }
}
