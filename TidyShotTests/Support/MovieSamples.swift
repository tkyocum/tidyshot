import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// What the mute and trim tests read back from a movie: its decoded sound as 16-bit samples, as it
/// plays or as stored, its video samples as stored, without decoding them, and its first frame.
nonisolated enum MovieSamples {
    enum ReadError: Error {
        case failed(String)
    }

    /// A movie's first audio track, decoded to 16-bit interleaved PCM.
    struct Audio {
        let sampleRate: Double
        let channels: Int
        /// Interleaved, from the track's start.
        let samples: [Int16]

        var duration: TimeInterval { Double(samples.count / max(1, channels)) / sampleRate }

        /// The largest absolute sample between `start` and `end` seconds, as a fraction of full scale.
        func peak(from start: TimeInterval, to end: TimeInterval) -> Double {
            let first = max(0, Int((start * sampleRate).rounded(.down))) * channels
            let last = min(samples.count, Int((end * sampleRate).rounded(.up)) * channels)
            guard last > first else { return 0 }
            var peak = 0
            for index in first..<last {
                peak = max(peak, abs(Int(samples[index])))
            }
            return Double(peak) / 32_768
        }

        /// The time of the first frame between `start` and `end` seconds with a channel louder than
        /// a tenth of full scale, or with `last` of the last one; nil when none is.
        func loudEdge(from start: TimeInterval, to end: TimeInterval, last: Bool = false) -> TimeInterval? {
            let first = max(0, Int((start * sampleRate).rounded(.down)))
            let stop = min(samples.count / channels, Int((end * sampleRate).rounded(.up)))
            guard stop > first else { return nil }
            func isLoud(_ frame: Int) -> Bool {
                (0..<channels).contains { abs(Int(samples[frame * channels + $0])) > 3_277 }
            }
            let frame = last ? (first..<stop).reversed().first(where: isLoud) : (first..<stop).first(where: isLoud)
            return frame.map { Double($0) / sampleRate }
        }
    }

    /// One stored video sample: its presentation time and its size in bytes.
    struct VideoSample: Equatable {
        let time: CMTime
        let size: Int
    }

    /// The decoded sound of `url`'s first audio track; nil without one.
    static func audio(of url: URL) async throws -> Audio? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        let provider = reader.outputProvider(for: output)
        try reader.start()
        var samples: [Int16] = []
        var rate = 0.0
        var channels = 1
        while let sample = try await provider.next() {
            let (data, format) = try sample.withUnsafeSampleBuffer { buffer in
                (try buffer.dataBuffer?.dataBytes() ?? Data(), buffer.formatDescription)
            }
            if let format, let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                rate = description.mSampleRate
                channels = Int(description.mChannelsPerFrame)
            }
            data.withUnsafeBytes { samples.append(contentsOf: $0.bindMemory(to: Int16.self)) }
        }
        guard reader.status == .completed else {
            throw ReadError.failed(reader.error?.localizedDescription ?? "status \(reader.status.rawValue)")
        }
        return Audio(sampleRate: rate, channels: channels, samples: samples)
    }

    /// `url`'s video samples as stored, in decode order, leaving out marker-only buffers.
    static func videoSamples(of url: URL) async throws -> [VideoSample] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let provider = reader.outputProvider(for: AVAssetReaderTrackOutput(track: track, outputSettings: nil))
        try reader.start()
        var found: [VideoSample] = []
        while let sample = try await provider.next() {
            let samples = sample.withUnsafeSampleBuffer { buffer in
                buffer.numSamples > 0
                    ? [VideoSample(time: buffer.presentationTimeStamp, size: buffer.totalSampleSize)] : []
            }
            found += samples
        }
        guard reader.status == .completed else {
            throw ReadError.failed(reader.error?.localizedDescription ?? "status \(reader.status.rawValue)")
        }
        return found
    }

    /// One stored sample as a sample cursor sees it, which ignores the edit list: its presentation
    /// time and duration in media time, and whether it is a full sync sample.
    struct StoredSample: Equatable {
        let time: CMTime
        let duration: CMTime
        let isSync: Bool
    }

    /// The first `mediaType` track's samples in decode order, every one the file stores, whatever
    /// its edit list shows.
    static func storedSamples(of url: URL, _ mediaType: AVMediaType) async throws -> [StoredSample] {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: mediaType).first else { return [] }
        guard let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else {
            throw ReadError.failed("no sample cursor")
        }
        var found: [StoredSample] = []
        repeat {
            found.append(StoredSample(time: cursor.presentationTimeStamp, duration: cursor.currentSampleDuration,
                                      isSync: cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue))
        } while cursor.stepInDecodeOrder(byCount: 1) == 1
        return found
    }

    /// The media time the first `mediaType` track's edit list starts showing it at: its first
    /// non-empty segment's source start.
    static func mediaStart(of url: URL, _ mediaType: AVMediaType) async throws -> CMTime? {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: mediaType).first else { return nil }
        return try await track.load(.segments).first { !$0.isEmpty }?.timeMapping.source.start
    }

    /// The first audio track's sound as stored: every packet in decode order, whatever the edit list
    /// hides, read from the file by its sample cursor and decoded with `AVAudioConverter`, so frame 0
    /// is the first packet's first frame. Each packet decodes to its own frames.
    static func storedAudio(of url: URL) async throws -> Audio? {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first else { return nil }
        guard let format = try await track.load(.formatDescriptions).first,
              let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else {
            throw ReadError.failed("no format or sample cursor")
        }
        let file = try Data(contentsOf: url, options: .mappedIfSafe)
        var packets: [Data] = []
        repeat {
            let range = cursor.currentSampleStorageRange
            guard range.offset >= 0, range.length > 0, Int(range.offset + range.length) <= file.count else {
                throw ReadError.failed("a packet outside the file")
            }
            packets.append(file[Int(range.offset)..<Int(range.offset + range.length)])
        } while cursor.stepInDecodeOrder(byCount: 1) == 1

        let input = AVAudioFormat(cmAudioFormatDescription: format)
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: input.sampleRate,
                                         channels: input.channelCount, interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw ReadError.failed("no converter")
        }
        converter.primeMethod = .none
        var samples: [Int16] = []
        for packet in packets {
            let compressed = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: packet.count)
            packet.copyBytes(to: compressed.data.assumingMemoryBound(to: UInt8.self), count: packet.count)
            compressed.byteLength = UInt32(packet.count)
            compressed.packetCount = 1
            compressed.packetDescriptions?[0] = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                             mDataByteSize: UInt32(packet.count))
            guard let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 4_096) else {
                throw ReadError.failed("no PCM buffer")
            }
            var pending: AVAudioCompressedBuffer? = compressed
            var error: NSError?
            let status = converter.convert(to: pcm, error: &error) { _, status in
                status.pointee = pending == nil ? .noDataNow : .haveData
                defer { pending = nil }
                return pending
            }
            guard status != .error, let data = pcm.int16ChannelData else {
                throw ReadError.failed(error?.localizedDescription ?? "a packet did not decode")
            }
            samples.append(contentsOf: UnsafeBufferPointer(start: data[0], count: Int(pcm.frameLength) * Int(output.channelCount)))
        }
        return Audio(sampleRate: input.sampleRate, channels: Int(input.channelCount), samples: samples)
    }

    /// The blue level of the centre pixel of the first frame the movie shows, decoded to BGRA; nil
    /// without a video track.
    static func firstFrameLevel(of url: URL) async throws -> Int? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        let provider = reader.outputProvider(for: AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]))
        try reader.start()
        while let sample = try await provider.next() {
            let level = sample.withUnsafeSampleBuffer { buffer -> Int? in
                guard let image = CMSampleBufferGetImageBuffer(buffer) else { return nil }
                CVPixelBufferLockBaseAddress(image, .readOnly)
                defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
                guard let base = CVPixelBufferGetBaseAddress(image) else { return nil }
                let offset = CVPixelBufferGetHeight(image) / 2 * CVPixelBufferGetBytesPerRow(image)
                    + CVPixelBufferGetWidth(image) / 2 * 4
                return Int(base.load(fromByteOffset: offset, as: UInt8.self))
            }
            if let level {
                reader.cancelReading()
                return level
            }
        }
        return nil
    }

    /// The first video track's encoded size, from its format description.
    static func videoSize(of url: URL) async throws -> CMVideoDimensions? {
        guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let format = try await track.load(.formatDescriptions).first else { return nil }
        return CMVideoFormatDescriptionGetDimensions(format)
    }

    /// The asset's duration in seconds.
    static func duration(of url: URL) async throws -> TimeInterval {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// The number of `mediaType` tracks.
    static func trackCount(of url: URL, _ mediaType: AVMediaType) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: mediaType).count
    }
}
