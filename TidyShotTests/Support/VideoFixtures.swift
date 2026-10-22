import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Movies made on the spot for the video tests: H.264 at 10 fps from `AVAssetWriter`, with a
/// silent mono AAC track when asked. Nothing needs Screen Recording or a real recording.
nonisolated enum VideoFixtures {
    enum FixtureError: Error {
        case cannotAddInput
        case noPixelBuffer
        case appendFailed(String)
        case writeFailed(String)
    }

    private static let framesPerSecond = 10
    private static let sampleRate = 44_100

    /// Writes an `.mp4` of `seconds` at `width` × `height` to `url`, replacing any file there.
    @concurrent
    static func makeMP4(at url: URL, width: Int, height: Int, seconds: Double, audio: Bool) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(video) else { throw FixtureError.cannotAddInput }
        writer.add(video)

        var sound: AVAssetWriterInput?
        if audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ])
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { throw FixtureError.cannotAddInput }
            writer.add(input)
            sound = input
        }

        guard writer.startWriting() else {
            throw FixtureError.writeFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        // The small margin keeps 0.3 s at three frames despite 0.3 × 10 not being exact.
        let frameCount = max(1, Int((seconds * Double(framesPerSecond) - 1e-9).rounded(.up)))
        let format = sound == nil ? nil : try silentFormat()
        let sampleCount = sound == nil ? 0 : Int((seconds * Double(sampleRate)).rounded())
        var frame = 0
        var sample = 0
        // Each input is fed whenever it is ready, a frame's worth of audio at a time. The writer
        // holds the input that is ahead until the other catches up, so waiting on one input
        // alone can wait forever. A writer that stops taking both throws instead of hanging.
        let deadline = ContinuousClock.now + .seconds(30)
        while frame < frameCount || sample < sampleCount {
            var appended = false
            if frame < frameCount, video.isReadyForMoreMediaData {
                let time = CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(framesPerSecond))
                let buffer = try pixelBuffer(from: adaptor, shade: frame)
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw FixtureError.appendFailed(writer.error?.localizedDescription ?? "video frame \(frame)")
                }
                frame += 1
                appended = true
            }
            if let sound, let format, sample < sampleCount, sound.isReadyForMoreMediaData {
                let count = min(sampleRate / framesPerSecond, sampleCount - sample)
                let samples = try silence(format: format, start: sample, count: count)
                guard sound.append(samples) else {
                    throw FixtureError.appendFailed(writer.error?.localizedDescription ?? "audio at \(sample)")
                }
                sample += count
                appended = true
            }
            if !appended {
                guard ContinuousClock.now < deadline else {
                    throw FixtureError.writeFailed("the writer stopped taking media at frame \(frame), sample \(sample)")
                }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        video.markAsFinished()
        sound?.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw FixtureError.writeFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
    }

    /// Bytes that are not a movie, under an `.mp4` name.
    static func makeGarbage(at url: URL) throws {
        try Data(String(repeating: "not a movie ", count: 4_096).utf8).write(to: url)
    }

    /// A frame of one grey that changes with `shade`, so the encoder has something to encode.
    private static func pixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor, shade: Int) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw FixtureError.noPixelBuffer }
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw FixtureError.noPixelBuffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(64 + (shade * 16) % 128), CVPixelBufferGetDataSize(buffer))
        }
        return buffer
    }

    /// 16-bit mono linear PCM at `sampleRate`.
    private static func silentFormat() throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                                    magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                                    formatDescriptionOut: &format)
        guard status == noErr, let format else { throw FixtureError.writeFailed("audio format \(status)") }
        return format
    }

    /// `count` zero samples starting at sample `start`.
    private static func silence(format: CMAudioFormatDescription, start: Int, count: Int) throws -> CMSampleBuffer {
        let byteCount = count * 2
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount,
                                                        blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                        dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                        blockBufferOut: &block)
        guard status == noErr, let block else { throw FixtureError.writeFailed("audio block \(status)") }
        status = CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        guard status == noErr else { throw FixtureError.writeFailed("audio fill \(status)") }
        var sample: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw FixtureError.writeFailed("audio sample \(status)") }
        return sample
    }
}
