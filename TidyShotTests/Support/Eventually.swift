import Foundation

nonisolated struct EventuallyTimedOut: Error, CustomStringConvertible {
    var description: String { "condition did not become true within 2 seconds" }
}

/// Polls `condition` every 10 ms for up to two seconds and throws `EventuallyTimedOut` if it
/// never holds, which fails the calling test. `async` so the condition can read actor state.
@MainActor
func eventually(_ condition: () async -> Bool) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw EventuallyTimedOut()
}
