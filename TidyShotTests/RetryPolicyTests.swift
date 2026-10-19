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

    @Test func retryTableClassifiesErrors() {
        #expect(UploadError.httpStatus(500, body: "").isRetryable)
        #expect(UploadError.httpStatus(503, body: "").isRetryable)
        #expect(UploadError.httpStatus(429, body: "").isRetryable)
        #expect(!UploadError.httpStatus(400, body: "").isRetryable)
        #expect(!UploadError.httpStatus(403, body: "").isRetryable)
        #expect(!UploadError.httpStatus(404, body: "").isRetryable)
        #expect(UploadError.noHTTPResponse.isRetryable)
        #expect(!UploadError.keyCollisionsExhausted.isRetryable)
        #expect(!UploadError.notConfigured.isRetryable)
        #expect(!UploadError.fileUnreadable("/tmp/x").isRetryable)
        #expect(UploadError.isRetryable(URLError(.timedOut)))
        #expect(!UploadError.isRetryable(URLError(.cancelled)))
        #expect(!UploadError.isRetryable(CancellationError()))
        #expect(!UploadError.isRetryable(NSError(domain: "x", code: 1)))
    }
}
