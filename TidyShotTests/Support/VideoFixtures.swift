import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Movies made on the spot for the video tests: H.264 at 10 fps from `AVAssetWriter`, or at given
/// frame times, with an AAC track when asked (mono at 44.1 kHz unless told otherwise), silent or
/// with a tone. Nothing needs Screen Recording or a real recording.
nonisolated enum VideoFixtures {
    enum FixtureError: Error {
        case cannotAddInput
        case noPixelBuffer
        case appendFailed(String)
        case writeFailed(String)
    }

    /// An empty edit of that many seconds in the audio track, where its sound would be.
    enum EmptyEdit: Sendable {
        /// The sound starts late.
        case leading(Double)
        /// The sound ends early.
        case trailing(Double)

        var seconds: Double {
            switch self {
            case .leading(let seconds), .trailing(let seconds): seconds
            }
        }
    }

    private static let framesPerSecond = 10
    /// The tone: 1 kHz at −6 dBFS.
    static let toneFrequency = 1_000.0
    static let toneAmplitude = 0.5012

    /// Writes an `.mp4` of `seconds` at `width` × `height` to `url`, replacing any file there.
    /// Frame `n` is a grey of level `64 + 16n mod 128`, or with `pattern` white with a 2 px black
    /// vertical line from that even column. It is at `n / 10` s, or at `frameTimes[n]` when given,
    /// for gaps and low source rates; the movie still ends at `seconds`. With `audio` the sound is
    /// silent, or with `tone` a 1 kHz sine at −6 dBFS within those ranges (seconds) and silent
    /// elsewhere, at `sampleRate` with the same sound in each of `channels`. With `emptyEdit` the
    /// sound starts late or ends early by that much, with an empty edit in its place, and the tone
    /// keeps its times. With `linearPCM` the sound is stored as 16-bit linear PCM in a QuickTime
    /// movie, which MP4 cannot hold. With `keyframeInterval` a sync sample comes at least every that
    /// many frames, with frame reordering off, so decode order is presentation order.
    @concurrent
    static func makeMP4(at url: URL, width: Int, height: Int, seconds: Double, audio: Bool,
                        pattern: Int? = nil, frameTimes: [Double]? = nil,
                        tone: [ClosedRange<Double>]? = nil, keyframeInterval: Int? = nil,
                        sampleRate: Int = 44_100, channels: Int = 1, emptyEdit: EmptyEdit? = nil,
                        linearPCM: Bool = false) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: linearPCM ? .mov : .mp4)

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
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: linearPCM ? [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ] : [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
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
        let format = sound == nil ? nil : try pcmFormat(sampleRate: sampleRate, channels: channels)
        let sampleCount = sound == nil ? 0 : Int((seconds * Double(sampleRate)).rounded())
        // Either empty edit is written as a late start, which `AVAssetWriter` gives an empty edit;
        // a trailing one is moved to the end below, so its tone counts from the first sample.
        let firstSample = min(sampleCount, Int(((emptyEdit?.seconds ?? 0) * Double(sampleRate)).rounded()))
        var toneOrigin = 0
        if case .trailing = emptyEdit { toneOrigin = firstSample }
        var frame = 0
        var sample = firstSample
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
                let samples = try audioSamples(format: format, start: sample, count: count, toneOrigin: toneOrigin,
                                               sampleRate: sampleRate, channels: channels, tone: tone ?? [])
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
        if firstSample == sampleCount { sound?.markAsFinished() }
        writer.endSession(atSourceTime: CMTime(seconds: seconds, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw FixtureError.writeFailed(writer.error?.localizedDescription ?? "status \(writer.status.rawValue)")
        }
        if sound != nil, case .trailing = emptyEdit { try moveEmptyEditToEnd(in: url) }
    }

    /// Swaps the two entries of the file's one edit list that starts empty, so the audio's leading
    /// empty edit ends it instead. `AVMutableMovie`, `AVMutableComposition` and a passthrough export
    /// all drop an empty edit at a track's end, so the bytes are changed in place: the list keeps its
    /// size, and its entries their lengths.
    private static func moveEmptyEditToEnd(in url: URL) throws {
        var data = try Data(contentsOf: url)
        func integer(at offset: Int, size: Int) -> UInt64 {
            data[offset..<offset + size].reduce(0) { $0 << 8 | UInt64($1) }
        }
        /// The bodies of the boxes of `type` directly inside `range`.
        func boxes(_ type: String, in range: Range<Int>) -> [Range<Int>] {
            var found: [Range<Int>] = []
            var offset = range.lowerBound
            while offset + 8 <= range.upperBound {
                var size = Int(integer(at: offset, size: 4))
                var header = 8
                if size == 1, offset + 16 <= range.upperBound {
                    size = Int(integer(at: offset + 8, size: 8))
                    header = 16
                } else if size == 0 {
                    size = range.upperBound - offset
                }
                guard size >= header, offset + size <= range.upperBound else { break }
                if String(decoding: data[offset + 4..<offset + 8], as: UTF8.self) == type {
                    found.append(offset + header..<offset + size)
                }
                offset += size
            }
            return found
        }
        let lists = boxes("moov", in: 0..<data.count)
            .flatMap { boxes("trak", in: $0) }
            .flatMap { boxes("edts", in: $0) }
            .flatMap { boxes("elst", in: $0) }
        var moved = 0
        for list in lists {
            // A version byte, three of flags and the entry count, then each entry's length and media
            // time (−1 for an empty edit), 32-bit or in version 1 64-bit, and its 32-bit rate.
            let wide = data[list.lowerBound] == 1
            let entrySize = wide ? 20 : 12
            let first = list.lowerBound + 8
            guard list.count >= 8 + 2 * entrySize, integer(at: list.lowerBound + 4, size: 4) == 2 else { continue }
            let mediaTime = wide ? Int64(bitPattern: integer(at: first + 8, size: 8))
                : Int64(Int32(bitPattern: UInt32(integer(at: first + 4, size: 4))))
            guard mediaTime == -1 else { continue }
            let empty = data[first..<first + entrySize]
            let media = data[first + entrySize..<first + 2 * entrySize]
            data.replaceSubrange(first..<first + 2 * entrySize, with: media + empty)
            moved += 1
        }
        guard moved == 1 else { throw FixtureError.writeFailed("\(moved) leading empty edits to move") }
        try data.write(to: url)
    }

    /// Writes a QuickTime movie to `url` that plays `source` (which must stay where it is) with its
    /// audio over `range` (seconds) sped up to last `duration`: an edit at another rate partway
    /// through the sound, whose frames the mute's decode cannot place.
    @concurrent
    static func makeAudioSpeedChange(of source: URL, over range: ClosedRange<Double>, lasting duration: Double,
                                     at url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let movie = AVMutableMovie(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let audio = try await movie.load(.tracks).first(where: { $0.mediaType == .audio }) else {
            throw FixtureError.writeFailed("no audio track to speed up")
        }
        let start = CMTime(seconds: range.lowerBound, preferredTimescale: 600)
        audio.scaleTimeRange(CMTimeRange(start: start, end: CMTime(seconds: range.upperBound, preferredTimescale: 600)),
                             toDuration: CMTime(seconds: duration, preferredTimescale: 600))
        try movie.writeHeader(to: url, fileType: .mov, options: .addMovieHeaderToDestination)
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

    /// 16-bit interleaved linear PCM at `sampleRate`.
    private static func pcmFormat(sampleRate: Int, channels: Int) throws -> CMAudioFormatDescription {
        var description = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil,
                                                    magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                                    formatDescriptionOut: &format)
        guard status == noErr, let format else { throw FixtureError.writeFailed("audio format \(status)") }
        return format
    }

    /// `count` frames starting at frame `start`: the tone in every channel where its time, counted
    /// from frame `toneOrigin`, is inside a `tone` range, zero elsewhere.
    private static func audioSamples(format: CMAudioFormatDescription, start: Int, count: Int, toneOrigin: Int,
                                     sampleRate: Int, channels: Int, tone: [ClosedRange<Double>]) throws -> CMSampleBuffer {
        let byteCount = count * 2 * channels
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: byteCount,
                                                        blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                                        dataLength: byteCount, flags: kCMBlockBufferAssureMemoryNowFlag,
                                                        blockBufferOut: &block)
        guard status == noErr, let block else { throw FixtureError.writeFailed("audio block \(status)") }
        status = CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: byteCount)
        guard status == noErr else { throw FixtureError.writeFailed("audio fill \(status)") }
        if !tone.isEmpty {
            var values = [Int16](repeating: 0, count: count * channels)
            for offset in 0..<count {
                let time = Double(start + offset - toneOrigin) / Double(sampleRate)
                guard tone.contains(where: { $0.contains(time) }) else { continue }
                let value = Int16((toneAmplitude * 32_767 * sin(2 * .pi * toneFrequency * time)).rounded())
                for channel in 0..<channels {
                    values[offset * channels + channel] = value
                }
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
