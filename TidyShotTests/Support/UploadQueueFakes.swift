import Foundation
import Synchronization
@testable import TidyShot

/// Counts security-scope starts and stops, per folder, in order.
nonisolated final class FakeSecurityScope: Sendable {
    let calls = Mutex<[String]>([])

    var scope: UploadQueue.SecurityScope {
        UploadQueue.SecurityScope(
            start: { url in self.calls.withLock { $0.append("start \(url.lastPathComponent)") }; return true },
            stop: { url in self.calls.withLock { $0.append("stop \(url.lastPathComponent)") } })
    }

    var starts: Int { calls.withLock { $0.count { $0.hasPrefix("start") } } }
    var stops: Int { calls.withLock { $0.count { $0.hasPrefix("stop") } } }
}

/// The queue's `Upload:` log lines, in order.
nonisolated final class LogLines: Sendable {
    let lines = Mutex<[String]>([])
}

/// The backoff sleeps a queue asked for, recorded instead of waited.
nonisolated final class SleepLog: Sendable {
    let durations = Mutex<[Duration]>([])
}

@MainActor
final class EventLog {
    var events: [UploadEvent] = []
}
