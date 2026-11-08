import AVFoundation
import CoreMedia
import Foundation

/// A sample buffer as an `AVAssetReader` output's provider gives it and an `AVAssetWriter` input's
/// receiver takes it: what `RecordingMute`'s rewrite, `RecordingTrim`'s re-encode and `AudioDecoder`
/// hand along.
typealias ReadySample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>

/// What `RecordingMute`'s rewrite and `RecordingTrim`'s re-encode share: one reader, one writer, a
/// task per track, and the same AAC for the sound.
nonisolated enum TrackPass {
    /// The AAC both passes encode the sound to: the source's sample rate and channel count at
    /// `RecordingMute.audioBitRate`.
    static func aacSettings(for description: AudioStreamBasicDescription) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: description.mSampleRate,
            AVNumberOfChannelsKey: Int(description.mChannelsPerFrame),
            AVEncoderBitRateKey: RecordingMute.audioBitRate,
        ]
    }

    /// The sound's lane of a pass: `track` read as stored, decoded by `AudioDecoder`, and written
    /// again as AAC at the source's rate and channel count (`aacSettings`).
    struct AudioLane {
        let provider: AVAssetReaderOutput.Provider<ReadySample>
        let receiver: AVAssetWriterInput.SampleBufferReceiver
        let decoder: AudioDecoder
        /// The source's sample rate.
        let rate: Double
    }

    /// Builds the audio lane both passes use. A track with no format description throws `readError`.
    static func audioLane(of track: AVAssetTrack, reader: AVAssetReader, writer: AVAssetWriter,
                          readError: any Error) async throws -> AudioLane {
        let (formats, range) = try await track.load(.formatDescriptions, .timeRange)
        guard let format = formats.first,
              let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { throw readError }
        let decoder = try AudioDecoder(format: format, end: range.end)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings(for: description))
        input.expectsMediaDataInRealTime = false
        return AudioLane(provider: reader.outputProvider(for: AVAssetReaderTrackOutput(track: track, outputSettings: nil)),
                         receiver: writer.inputReceiver(for: input), decoder: decoder, rate: description.mSampleRate)
    }

    /// Makes `output`'s folder when it is missing, removes any file at `output`, and runs `body`,
    /// which writes it. A throw removes what was written and is rethrown, as `CancellationError`
    /// when the task was cancelled.
    static func writing(to output: URL, _ body: () async throws -> Void) async throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        do {
            try await body()
        } catch {
            try? FileManager.default.removeItem(at: output)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Starts `reader` and `writer`, the writer's session from 0, and runs each of `tracks` on a task
    /// of its own. At the first failure, or a cancel, the other tracks' tasks are cancelled and each
    /// ends at its next sample: a failed track has finished its writer input, so the writer holds no
    /// append back for it. The reader and writer are cancelled, and the failure thrown, only once
    /// every track has ended: a reader cancelled under a read crashed, and a writer cancelled under an
    /// append it held never let the append return (Mute, as built: A failure partway). A reader that
    /// failed throws its error, or `readError`. With `end`, for a pass over a range, the reader is
    /// cancelled first, as a track that reached the range's end can leave samples unread, and the
    /// session ends there. A writer that does not complete throws its error, or `writeError`.
    static func run(reader: AVAssetReader, writer: AVAssetWriter, tracks: [() async throws -> Void],
                    endingAt end: CMTime? = nil, readError: any Error, writeError: any Error) async throws {
        try reader.start()
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        do {
            try await runEach(tracks)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
        guard reader.status != .failed else {
            writer.cancelWriting()
            throw reader.error ?? readError
        }
        if let end {
            reader.cancelReading()
            writer.endSession(atSourceTime: end)
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? writeError
        }
    }

    /// Each track on a task of its own; the first failure cancels the rest and is thrown once all
    /// have ended.
    private static func runEach(_ tracks: [() async throws -> Void]) async throws {
        // Each track goes to its own task, and nothing here touches it again.
        nonisolated(unsafe) let tracks = tracks
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in tracks.indices {
                group.addTask { try await tracks[index]() }
            }
            // A throw here cancels the tasks still running and waits for them before it propagates.
            for try await _ in group {}
        }
    }
}
