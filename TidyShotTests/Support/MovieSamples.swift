import AVFoundation
import CoreMedia
import Foundation

/// What the mute tests read back from a movie: its decoded sound as 16-bit samples, and its video
/// samples as stored, without decoding them.
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

    /// The asset's duration in seconds.
    static func duration(of url: URL) async throws -> TimeInterval {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    /// The number of `mediaType` tracks.
    static func trackCount(of url: URL, _ mediaType: AVMediaType) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: mediaType).count
    }
}
