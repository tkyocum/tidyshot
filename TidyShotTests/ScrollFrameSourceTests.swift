import CoreVideo
import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// The parts of the stream source that run without ScreenCaptureKit: the copy out of a pixel
/// buffer and the one-deep buffer rule. The stream itself is a manual check.
struct ScrollFrameSourceTests {
    func makePixelBuffer(width: Int, height: Int, format: OSType) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary
        try #require(CVPixelBufferCreate(nil, width, height, format, attributes, &buffer) == kCVReturnSuccess)
        return try #require(buffer)
    }

    func frame(_ value: UInt8) -> ScrollFrame {
        ScrollFrame(bgra: Data(repeating: value, count: 2 * 2 * 4), width: 2, height: 2, bytesPerRow: 8)
    }

    /// The first byte of a frame event, which `frame(_:)` fills with its value; nil otherwise.
    func value(of event: FrameEvent?) -> UInt8? {
        guard case .frame(let frame)? = event else { return nil }
        return frame.bgra.first
    }

    /// 37 pixels are 148 bytes, which CoreVideo pads to 192 per row. The frame holds the 148
    /// bytes of each row and none of the padding, which is filled with 0xEE here.
    @Test func copyFramePacksAPaddedPixelBuffer() throws {
        let buffer = try makePixelBuffer(width: 37, height: 5, format: kCVPixelFormatType_32BGRA)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        try #require(bytesPerRow > 37 * 4)
        var expected: [UInt8] = []
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for y in 0..<5 {
            for x in 0..<bytesPerRow {
                let value = x < 37 * 4 ? UInt8((x * 7 + y * 31) & 0xFF) : 0xEE
                base[y * bytesPerRow + x] = value
                if x < 37 * 4 { expected.append(value) }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let frame = try #require(ScrollFrameSource.copyFrame(from: buffer))
        #expect(frame.width == 37)
        #expect(frame.height == 5)
        #expect(Array(frame.bgra) == expected)
        #expect(frame.gray.count == 37 * 5)

        let argb = try makePixelBuffer(width: 4, height: 4, format: kCVPixelFormatType_32ARGB)
        #expect(ScrollFrameSource.copyFrame(from: argb) == nil)
    }

    /// One event is buffered. A newer frame replaces an unread one, an idle never does, and
    /// finishing still delivers the frame that is buffered.
    @Test func anIdleNeverPushesOutAPendingFrame() async throws {
        let (events, continuation) = AsyncStream.makeStream(of: FrameEvent.self, bufferingPolicy: .bufferingNewest(1))
        var iterator = events.makeAsyncIterator()

        ScrollFrameSource.send(.frame(frame(1)), to: continuation)
        ScrollFrameSource.send(.idle, to: continuation)
        ScrollFrameSource.send(.idle, to: continuation)
        #expect(value(of: await iterator.next(isolation: #isolation)) == 1)

        ScrollFrameSource.send(.idle, to: continuation)
        guard case .idle? = await iterator.next(isolation: #isolation) else {
            Issue.record("an idle with nothing pending is delivered")
            return
        }

        ScrollFrameSource.send(.frame(frame(2)), to: continuation)
        ScrollFrameSource.send(.frame(frame(3)), to: continuation)
        #expect(value(of: await iterator.next(isolation: #isolation)) == 3)

        ScrollFrameSource.send(.frame(frame(4)), to: continuation)
        continuation.finish()
        #expect(value(of: await iterator.next(isolation: #isolation)) == 4)
        let end = await iterator.next(isolation: #isolation)
        #expect(end == nil)
    }

    nonisolated struct StreamBroke: Error {}

    /// A stream that stops by itself records why and finishes the events, so the frame still
    /// buffered is delivered before the end, and the reason is there when the end is seen.
    @Test func aStopByItselfKeepsTheBufferedFrame() async throws {
        let (events, continuation) = AsyncStream.makeStream(of: FrameEvent.self, bufferingPolicy: .bufferingNewest(1))
        var iterator = events.makeAsyncIterator()
        let reason = Mutex<(any Error)?>(nil)

        ScrollFrameSource.send(.frame(frame(5)), to: continuation)
        ScrollFrameSource.stopped(by: StreamBroke(), recordingIn: reason, finishing: continuation)
        #expect(value(of: await iterator.next(isolation: #isolation)) == 5)
        let end = await iterator.next(isolation: #isolation)
        #expect(end == nil)
        #expect(reason.withLock { $0 } is StreamBroke)
    }
}
