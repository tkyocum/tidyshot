import Foundation

/// A recording's one mute log writer (design, Mute log: One writer, last toggle wins). Each toggle
/// yields its snapshot synchronously into a stream that keeps only the newest, so snapshots enter in
/// the main actor's toggle order and quick toggles coalesce to the latest. One consumer task, off
/// the main actor, takes them one at a time and writes each atomically, skipping one whose sequence
/// number is not above the last written, so an earlier toggle never overwrites a later one. A failed
/// write is logged, and the controller's own list still applies.
nonisolated final class MuteLogWriter: Sendable {
    private let continuation: AsyncStream<MuteLog>.Continuation
    private let consumer: Task<Void, Never>

    init(url: URL, write: @escaping @Sendable (MuteLog, URL) throws -> Void = MuteLog.write) {
        let (logs, continuation) = AsyncStream.makeStream(of: MuteLog.self, bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        // A kill between a press and its write recovers that press's sound, so the write goes soon.
        consumer = Task.detached(priority: .userInitiated) {
            var lastWritten: Int?
            for await log in logs {
                if let lastWritten, log.sequence <= lastWritten { continue }
                do {
                    try write(log, url)
                    lastWritten = log.sequence
                } catch {
                    RecordingLog.note("Recording: the mute log \(url.lastPathComponent) could not be written: \(error.localizedDescription)")
                }
            }
        }
    }

    deinit {
        continuation.finish()
    }

    /// Hands the writer a toggle's snapshot. It replaces one not yet taken; once `finish` has been
    /// called it is dropped.
    func yield(_ log: MuteLog) {
        continuation.yield(log)
    }

    /// Ends the stream and returns once the consumer has written what it had, so no write lands
    /// after it: a removal of the log right after it stands.
    func finish() async {
        continuation.finish()
        await consumer.value
    }
}
