import Foundation
import Synchronization
import Testing
@testable import TidyShot

struct GIFFileSinkTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "GIFFileSinkTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// Free space as the sink reads it, counting the reads.
    nonisolated final class FreeSpace: Sendable {
        let bytes: Int64?
        let reads = Mutex(0)
        init(_ bytes: Int64?) { self.bytes = bytes }
        func read() -> Int64? {
            reads.withLock { $0 += 1 }
            return bytes
        }
    }

    func pattern(_ count: Int, seed: UInt8) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) }
    }

    /// Applies the same writes and patches to both sinks.
    struct Pair {
        var file: GIFFileSink
        var data = GIFDataSink()

        mutating func write(_ bytes: [UInt8]) throws {
            try bytes.withUnsafeBytes { try file.write($0) }
            try bytes.withUnsafeBytes { try data.write($0) }
            #expect(file.count == data.count)
        }

        mutating func overwrite(_ bytes: [UInt8], at offset: Int) throws {
            try file.overwrite(bytes, at: offset)
            try data.overwrite(bytes, at: offset)
        }
    }

    @Test func theFileHoldsWhatTheDataSinkHolds() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "out.gif")
        let space = FreeSpace(50_000_000_000)
        var pair = Pair(file: try GIFFileSink(url: url, freeBytes: { space.read() }))
        let buffer = GIFFileSink.bufferBytes

        try pair.write(pattern(100, seed: 1))
        try pair.overwrite([0xAA, 0xBB], at: 10)                  // still in the buffer
        try pair.write(pattern(buffer + buffer / 2, seed: 2))      // larger than the buffer
        try pair.overwrite([0xCC, 0xDD], at: 10)                  // after a flush
        try pair.write(pattern(buffer / 4, seed: 3))
        try pair.write(pattern(buffer - 10, seed: 4))             // flushes the quarter first
        let flushed = 100 + buffer + buffer / 2 + buffer / 4
        try pair.overwrite([0x11, 0x22], at: flushed - 1)         // across the flushed edge
        try pair.overwrite([0x33, 0x44], at: pair.data.count - 2) // the last bytes, in the buffer
        try pair.file.close()
        try pair.data.close()

        let written = try Data(contentsOf: url)
        #expect(written.count == pair.data.bytes.count)
        #expect(written == Data(pair.data.bytes))
        #expect(space.reads.withLock { $0 } == 0)
    }

    @Test func closingTwiceIsHarmlessAndWritingAfterCloseThrows() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "out.gif")
        var sink = try GIFFileSink(url: url, freeBytes: { nil })
        try [UInt8](repeating: 7, count: 10).withUnsafeBytes { try sink.write($0) }
        try sink.close()
        try sink.close()
        #expect(throws: GIFMakerError.couldNotWrite) {
            try [UInt8(1)].withUnsafeBytes { try sink.write($0) }
        }
        #expect(try Data(contentsOf: url) == Data(repeating: 7, count: 10))
    }

    /// Free space is read after every 32 MB written; under 1 GB stops the GIF.
    @Test func lessThan1GBFreeAtA32MBBoundaryThrows() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let space = FreeSpace(999_999_999)
        var sink = try GIFFileSink(url: folder.appending(path: "out.gif"), freeBytes: { space.read() })
        let chunk = [UInt8](repeating: 1, count: 64 << 10)
        var thrown: (any Error)?
        while sink.count < 40 << 20 {
            do {
                try chunk.withUnsafeBytes { try sink.write($0) }
            } catch {
                thrown = error
                break
            }
        }
        try? sink.close()
        #expect(thrown as? GIFMakerError == .notEnoughSpace)
        #expect(sink.count >= GIFFileSink.spaceCheckBytes)
        #expect(sink.count <= GIFFileSink.spaceCheckBytes + GIFFileSink.bufferBytes + chunk.count)
        #expect(space.reads.withLock { $0 } == 1)
    }

    @Test func enoughFreeSpaceIsReadOncePer32MB() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        let space = FreeSpace(1_000_000_000)
        var sink = try GIFFileSink(url: folder.appending(path: "out.gif"), freeBytes: { space.read() })
        let chunk = [UInt8](repeating: 2, count: 1 << 20)
        for _ in 0..<66 {
            try chunk.withUnsafeBytes { try sink.write($0) }
        }
        try sink.close()
        #expect(GIFFileSink.spaceCheckBytes == 32 << 20)
        #expect(GIFFileSink.bufferBytes == 1 << 20)
        #expect(space.reads.withLock { $0 } == 2)
    }

    @Test func aFolderThatRefusesWritesThrowsCouldNotWrite() throws {
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: folder.path(percentEncoded: false))
            try? FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))
        #expect(throws: GIFMakerError.couldNotWrite) {
            _ = try GIFFileSink(url: folder.appending(path: "out.gif"), freeBytes: { nil })
        }
    }

    @Test func errorsDescribeThemselves() {
        #expect(GIFMakerError.notEnoughSpace.localizedDescription == "Not enough disk space to make the GIF.")
        #expect(GIFMakerError.couldNotWrite.localizedDescription == "The GIF could not be written. The disk may be full.")
    }
}
