import Foundation
import Testing
@testable import TidyShot

/// The mute log's one writer (design, Mute log): snapshots go in in toggle order and coalesce to
/// the latest, a later toggle is never overwritten by an earlier one, and nothing lands once
/// `finish` has returned.
@Suite(.timeLimit(.minutes(1)))
struct MuteLogWriterTests {
    let dir: URL
    let url: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "MuteLogWriterTests-\(UUID().uuidString)")
        url = dir.appending(path: "Mute/\(UUID().uuidString).json")
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: dir)
    }

    /// The log after `sequence` toggles: closed stretches a second long, one each 2 s, the last open
    /// on an odd sequence.
    func log(_ sequence: Int, lag: TimeInterval = 0.3) -> MuteLog {
        let intervals = (0..<(sequence + 1) / 2).map { index in
            let start = Double(index * 2)
            return MuteInterval(start: start, end: index * 2 + 2 <= sequence ? start + 1 : nil)
        }
        return MuteLog(intervals: intervals, lag: lag, sequence: sequence)
    }

    @Test func snapshotsFasterThanASlowWriteLeaveTheLastOnDisk() async throws {
        defer { cleanUp() }
        let writes = MuteLogWrites(delay: 0.02, writesToDisk: true)
        let writer = MuteLogWriter(url: url, write: writes.write)
        for sequence in 1...20 {
            writer.yield(log(sequence))
        }
        await writer.finish()

        #expect(MuteLog.read(url) == .log(log(20)))
        let sequences = writes.logs.map(\.sequence)
        #expect(sequences.last == 20)
        // They coalesce to the latest rather than queue.
        #expect(sequences.count < 20)
        #expect(sequences == sequences.sorted())
    }

    /// A lower sequence number, then an equal one, each yielded once the last has been written.
    @Test(arguments: [3, 5])
    func aSnapshotNotAboveTheLastWrittenIsSkipped(_ sequence: Int) async throws {
        defer { cleanUp() }
        let writes = MuteLogWrites(writesToDisk: true)
        let writer = MuteLogWriter(url: url, write: writes.write)
        writer.yield(log(5))
        await writes.waitForWrites(1)
        writer.yield(log(sequence, lag: 0.6))
        await writer.finish()

        #expect(writes.logs == [log(5)])
        #expect(writes.ended == 1)
        #expect(MuteLog.read(url) == .log(log(5)))
    }

    @Test func onceFinishHasReturnedNoWriteLands() async throws {
        defer { cleanUp() }
        let writes = MuteLogWrites(delay: 0.02, writesToDisk: true)
        let writer = MuteLogWriter(url: url, write: writes.write)
        for sequence in 1...5 {
            writer.yield(log(sequence))
        }
        await writer.finish()
        let written = writes.logs
        #expect(written.last == log(5))

        // A discard removes the log right after the finish, and the removal stands.
        try FileManager.default.removeItem(at: url)
        writer.yield(log(6))
        try await Task.sleep(for: .milliseconds(100))
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        #expect(writes.logs == written)
    }

    /// A failed write is logged, and the next toggle's snapshot is written.
    @Test func aFailedWriteDoesNotStopTheWriter() async throws {
        defer { cleanUp() }
        let writes = MuteLogWrites(writesToDisk: true)
        writes.failNext(1)
        let writer = MuteLogWriter(url: url, write: writes.write)
        writer.yield(log(2))
        await writes.waitForWrites(1)
        #expect(writes.logs.isEmpty)
        #expect(MuteLog.read(url) == .none)
        writer.yield(log(3))
        await writer.finish()

        #expect(writes.logs == [log(3)])
        #expect(MuteLog.read(url) == .log(log(3)))
    }

    /// The default write is `MuteLog.write`, which makes the folder and writes the JSON.
    @Test func theDefaultWriteMakesTheFolderAndWritesTheLog() async throws {
        defer { cleanUp() }
        let writer = MuteLogWriter(url: url)
        writer.yield(log(3, lag: 0.65))
        await writer.finish()

        #expect(MuteLog.read(url) == .log(log(3, lag: 0.65)))
    }

    @Test func aWriterNeverGivenALogWritesNothing() async throws {
        defer { cleanUp() }
        let writes = MuteLogWrites(writesToDisk: true)
        let writer = MuteLogWriter(url: url, write: writes.write)
        await writer.finish()

        #expect(writes.ended == 0)
        #expect(MuteLog.read(url) == .none)
    }
}
