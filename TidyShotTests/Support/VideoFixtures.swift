import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Movies made on the spot for the video tests: H.264 at 10 fps from `AVAssetWriter`, or at given
/// frame times, with a mono AAC track when asked, silent or with a tone. Nothing needs Screen
/// Recording or a real recording.
nonisolated enum VideoFixtures {
    enum FixtureError: Error {
        case cannotAddInput
        case noPixelBuffer
        case appendFailed(String)
        case writeFailed(String)
    }

    private static let framesPerSecond = 10
    private static let sampleRate = 44_100
    /// The tone: 1 kHz at −6 dBFS.
    static let toneFrequency = 1_000.0
    static let toneAmplitude = 0.5012

    /// Writes an `.mp4` of `seconds` at `width` × `height` to `url`, replacing any file there.
    /// Frame `n` is a grey of level `64 + 16n mod 128`, or with `pattern` white with a 2 px black
    /// vertical line from that even column. It is at `n / 10` s, or at `frameTimes[n]` when given,
    /// for gaps and low source rates; the movie still ends at `seconds`. With `audio` the sound is
    /// silent, or with `tone` a 1 kHz sine at −6 dBFS within those ranges (seconds) and silent
    /// elsewhere. With `keyframeInterval` a sync sample comes at least every that many frames, with
    /// frame reordering off, so decode order is presentation order.
    @concurrent
    static func makeMP4(at url: URL, width: Int, height: Int, seconds: Double, audio: Bool,
                        pattern: Int? = nil, frameTimes: [Double]? = nil,
                        tone: [ClosedRange<Double>]? = nil, keyframeInterval: Int? = nil) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        if let keyframeInterval {
            settings[AVVideoCompressionPropertiesKey] = [
                AVVideoMaxKeyFrameIntervalKey: keyframeInterval,
                AVVideoAllowFrameReorderingKey: false,
            ]
        }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
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
        let frameCount = frameTimes?.count ?? max(1, Int((seconds * Double(framesPerSecond) - 1e-9).rounded(.up)))
        let format = sound == nil ? nil : try monoFormat()
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
                let time = frameTimes.map { CMTime(seconds: $0[frame], preferredTimescale: 600) }
                    ?? CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(framesPerSecond))
                let buffer = try pixelBuffer(from: adaptor, shade: frame, pattern: pattern)
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw FixtureError.appendFailed(writer.error?.localizedDescription ?? "video frame \(frame)")
                }
                frame += 1
                appended = true
                // Finished as soon as it is complete, so the writer stops holding the other input
                // back to interleave with it.
                if frame == frameCount { video.markAsFinished() }
            }
            if let sound, let format, sample < sampleCount, sound.isReadyForMoreMediaData {
                let count = min(sampleRate / framesPerSecond, sampleCount - sample)
                let samples = try audioSamples(format: format, start: sample, count: count, tone: tone ?? [])
                guard sound.append(samples) else {
                    throw FixtureError.appendFailed(writer.error?.localizedDescription ?? "audio at \(sample)")
                }
                sample += count
                appended = true
                if sample == sampleCount { sound.markAsFinished() }
            }
            if !appended {
                guard ContinuousClock.now < deadline else {
                    throw FixtureError.writeFailed("the writer stopped taking media at frame \(frame), sample \(sample)")
                }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        if sampleCount == 0 { sound?.markAsFinished() }
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

    /// A frame of one grey that changes with `shade`, so the encoder has something to encode; with
    /// `pattern`, white with black BGR at columns `pattern` and `pattern + 1` of every row.
    private static func pixelBuffer(from adaptor: AVAssetWriterInputPixelBufferAdaptor, shade: Int,
                                    pattern: Int?) throws -> CVPixelBuffer {
        guard let pool = adaptor.pixelBufferPool else { throw FixtureError.noPixelBuffer }
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw FixtureError.noPixelBuffer }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return buffer }
        guard let pattern else {
            memset(base, Int32(64 + (shade * 16) % 128), CVPixelBufferGetDataSize(buffer))
            return buffer
        }
        memset(base, 255, CVPixelBufferGetDataSize(buffer))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let columns = [pattern, pattern + 1].filter { $0 >= 0 && $0 < CVPixelBufferGetWidth(buffer) }
        for row in 0..<CVPixelBufferGetHeight(buffer) {
            let pixels = base.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in columns {
                pixels[column * 4] = 0
                pixels[column * 4 + 1] = 0
                pixels[column * 4 + 2] = 0
            }
        }
        return buffer
    }

    /// 16-bit mono linear PCM at `sampleRate`.
    private static func monoFormat() throws -> CMAudioFormatDescription {
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

    /// `count` samples starting at sample `start`: the tone where its time is inside a `tone` range,
    /// zero elsewhere.
    private static func audioSamples(format: CMAudioFormatDescription, start: Int, count: Int,
                                     tone: [ClosedRange<Double>]) throws -> CMSampleBuffer {
        let byteCount = count * 2
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount,
                                                        blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                        dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                        blockBufferOut: &block)
        guard status == noErr, let block else { throw FixtureError.writeFailed("audio block \(status)") }
        status = CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        guard status == noErr else { throw FixtureError.writeFailed("audio fill \(status)") }
        if !tone.isEmpty {
            var values = [Int16](repeating: 0, count: count)
            for offset in 0..<count {
                let time = Double(start + offset) / Double(sampleRate)
                guard tone.contains(where: { $0.contains(time) }) else { continue }
                values[offset] = Int16((toneAmplitude * 32_767 * sin(2 * .pi * toneFrequency * time)).rounded())
            }
            status = values.withUnsafeBytes {
                CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                              dataLength: byteCount)
            }
            guard status == noErr else { throw FixtureError.writeFailed("audio tone \(status)") }
        }
        var sample: CMSampleBuffer?
        status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw FixtureError.writeFailed("audio sample \(status)") }
        return sample
    }
}
