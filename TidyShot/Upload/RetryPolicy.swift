import Foundation

/// Exponential backoff: attempt 2 waits `baseDelay`, attempt 3 waits twice that, and so on,
/// capped at `maxDelay`.
nonisolated struct RetryPolicy: Sendable, Equatable {
    var maxAttempts: Int
    var baseDelay: Duration
    var maxDelay: Duration

    static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: .seconds(1), maxDelay: .seconds(30))
    /// For tests: same attempt count, no waiting.
    static let immediate = RetryPolicy(maxAttempts: 3, baseDelay: .zero, maxDelay: .zero)

    /// The wait before `attempt` (2-based: the first retry is attempt 2).
    func delay(beforeAttempt attempt: Int) -> Duration {
        guard attempt >= 2 else { return .zero }
        let multiplier = 1 << min(attempt - 2, 30)
        return min(baseDelay * multiplier, maxDelay)
    }
}
