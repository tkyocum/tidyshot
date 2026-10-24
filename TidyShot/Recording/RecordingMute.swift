import AVFoundation
import CoreMedia
import Foundation

/// Muting a recording's file (design, After the end, Privacy rule). The muted stretches are widened
/// into segments, the audio inside them is zeroed in a rewrite of the whole file, and the rewrite
/// is put over the original. When that fails the audio is removed instead, and when that fails too
/// the file is kept unmuted and marked, so its sound never leaves TidyShot.
nonisolated enum RecordingMute {
    /// How far before a press a segment starts: mouse-up and one AAC packet.
    static let lead: TimeInterval = 0.1
    /// A recording's lag with no microphone (design, Lag).
    static let defaultLag: TimeInterval = 0.3
    /// 128 kbps, the rewrite's AAC.
    static let audioBitRate = 128_000

    static let soundRemovedNotice = RecordingNotice(title: "Sound removed",
                                                    body: "Muting failed, so the recording has no sound.")

    /// The privacy ladder's result.
    enum Outcome: Equatable, Sendable {
        /// The rewrite replaced the file.
        case muted
        /// The rewrite failed, and a copy without audio replaced the file.
        case soundRemoved
        /// Neither step replaced the file, or there was no room to try: it still holds the sound.
        case notMuted
    }

    struct Resolution: Equatable, Sendable {
        var outcome: Outcome
        /// The merged segments, which a `.notMuted` file is marked with.
        var segments: [MuteInterval]
    }

    /// The ladder's steps: `apply`, `stripAudio` and the replace over the original.
    struct Steps: Sendable {
        var apply: @Sendable (URL, [MuteInterval], URL) async throws -> Void
        var stripAudio: @Sendable (URL, URL) async throws -> Void
        var replace: @Sendable (URL, URL) throws -> Void

        /// The real steps, which `-MuteFailure` makes fail in Debug builds. The end of a recording
        /// and the launch check both run the ladder with these.
        static var live: Steps {
            let steps = Steps(apply: { try await RecordingMute.apply($0, intervals: $1, to: $2) },
                              stripAudio: { try await RecordingMute.stripAudio($0, to: $1) },
                              replace: { try RecordingMute.replaceOriginal($0, with: $1) })
            #if DEBUG
            if let failure = MuteFailure(argument: UserDefaults.standard.string(forKey: MuteFailure.argumentKey)) {
                return failure.wrap(steps)
            }
            #endif
            return steps
        }
    }

    /// `tmp/Mute/<id>.mp4`, the ladder's output for `tmp/Recording/<id>.mp4`. Never in
    /// `tmp/Recording`, so the launch check cannot take it for a second recording.
    static func rewriteURL(for id: UUID) -> URL {
        MuteLog.directory.appending(path: "\(id.uuidString).\(MediaKind.video.fileExtension)", directoryHint: .notDirectory)
    }

    // MARK: Segments

    /// The stretches to silence: each interval, an open one closed at `duration`, widened to
    /// `[start − lead, end + lag]` and clamped to the file, then overlapping ones merged, in time
    /// order. None is dropped, however short: with a 0.3 s lag a 0.05 s interval becomes 0.45 s.
    static func segments(duration: TimeInterval, intervals: [MuteInterval], lead: TimeInterval,
                         lag: TimeInterval) -> [MuteInterval] {
        let end = max(0, duration)
        func clamped(_ time: TimeInterval) -> TimeInterval { min(max(0, time), end) }
        let widened = intervals.map { interval in
            (start: clamped(interval.start - lead), end: clamped(max(interval.start, interval.end ?? end) + lag))
        }
        var merged: [(start: TimeInterval, end: TimeInterval)] = []
        for next in widened.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, next.start <= last.end {
                merged[merged.count - 1].end = max(last.end, next.end)
            } else {
                merged.append(next)
            }
        }
        return merged.map { MuteInterval(start: $0.start, end: $0.end) }
    }

    // MARK: The ladder

    /// The privacy ladder (design, After the end; plan Gap 4), with its steps injected:
    /// 1. without room for the rewrite (`hasRoom(file)`), `.notMuted`, and neither step runs;
    /// 2. `apply` into `output`, then `replace` over `file`: `.muted`;
    /// 3. after either fails, `output` is removed, then `stripAudio` into it and `replace`: `.soundRemoved`;
    /// 4. after either of those fails, `.notMuted`.
    /// `output` is removed on every exit. The segments come back whatever the outcome.
    static func resolve(file: URL, output: URL, duration: TimeInterval, intervals: [MuteInterval], lag: TimeInterval,
                        hasRoom: (URL) -> Bool,
                        apply: (URL, [MuteInterval], URL) async throws -> Void,
                        stripAudio: (URL, URL) async throws -> Void,
                        replace: (URL, URL) throws -> Void) async -> Resolution {
        let muted = segments(duration: duration, intervals: intervals, lead: lead, lag: lag)
        defer { removeOutput(output) }
        guard hasRoom(file) else {
            RecordingLog.note("Recording: mute skipped, not enough disk space")
            return Resolution(outcome: .notMuted, segments: muted)
        }
        do {
            try await apply(file, muted, output)
            try replace(file, output)
            return Resolution(outcome: .muted, segments: muted)
        } catch {
            RecordingLog.note("Recording: mute failed: \(error.localizedDescription)")
        }
        removeOutput(output)
        do {
            try await stripAudio(file, output)
            try replace(file, output)
            return Resolution(outcome: .soundRemoved, segments: muted)
        } catch {
            RecordingLog.note("Recording: the sound could not be removed either: \(error.localizedDescription)")
            return Resolution(outcome: .notMuted, segments: muted)
        }
    }

    /// The ladder over `steps`, off the main actor, with the room checked in `tmp/Mute`: what the
    /// end of a recording and the launch check run, both with `Steps.live`.
    @concurrent
    static func resolve(file: URL, output: URL, duration: TimeInterval, intervals: [MuteInterval], lag: TimeInterval,
                        steps: Steps) async -> Resolution {
        await resolve(file: file, output: output, duration: duration, intervals: intervals, lag: lag,
                      hasRoom: hasRoomInMuteFolder(for:), apply: steps.apply, stripAudio: steps.stripAudio,
                      replace: steps.replace)
    }

    /// Room in `tmp/Mute` for a rewrite of `file`: its size plus 1 GB free. The folder is made
    /// first, so its own volume is read; an unreadable value counts as enough.
    private static func hasRoomInMuteFolder(for file: URL) -> Bool {
        try? FileManager.default.createDirectory(at: MuteLog.directory, withIntermediateDirectories: true)
        let size = Int64(FileSizes.byteCount(of: file) ?? 0)
        return RecordingLimits.hasRoom(for: size, freeBytes: RecordingLimits.freeBytes(at: MuteLog.directory))
    }

    private static func removeOutput(_ output: URL) {
        try? FileManager.default.removeItem(at: output)
    }

    // MARK: The steps

    /// Rewrites `source` to `output` with the audio inside `intervals` (segments; an open one runs
    /// to the end) silent. Video samples pass through untouched. Audio is read as stored and decoded
    /// to 16-bit interleaved PCM with `AVAudioConverter`, which needs no audio device (`AudioDecoder`),
    /// zeroed on a copy, and encoded again as AAC at the source's rate and channel count. No empty
    /// edit and no audio mix: the output's audio is one continuous segment, which FFmpeg-based
    /// readers, Clop among them, play right. A file with no audio track comes through with its video
    /// alone. `output`'s folder is made when it is missing, any file there is replaced, and a throw
    /// or a cancel removes what was written.
    @concurrent
    static func apply(_ source: URL, intervals: [MuteInterval], to output: URL) async throws {
        try prepareOutput(output)
        do {
            try await rewrite(source, segments: intervals, to: output)
        } catch {
            removeOutput(output)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Writes `source`'s video track alone to `output`, exported with passthrough: the ladder's
    /// fallback when `apply` fails. `output`'s folder is made when it is missing, any file there is
    /// replaced, and a throw or a cancel removes the partial file the export leaves.
    @concurrent
    static func stripAudio(_ source: URL, to output: URL) async throws {
        try prepareOutput(output)
        do {
            let asset = AVURLAsset(url: source)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw RecordingMuteError.couldNotRead
            }
            let (range, transform) = try await track.load(.timeRange, .preferredTransform)
            let composition = AVMutableComposition()
            guard let video = composition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw RecordingMuteError.couldNotWrite
            }
            try video.insertTimeRange(range, of: track, at: range.start)
            video.preferredTransform = transform
            guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                throw RecordingMuteError.couldNotWrite
            }
            try await session.export(to: output, as: .mp4)
        } catch {
            removeOutput(output)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Puts `output` over `original` with same-volume `replaceItemAt`, which leaves the original in
    /// place when it fails. If the original is gone anyway, `output` is renamed into its place and
    /// the step counts as done: a mute step's output never holds muted sound (design, A failed
    /// replace).
    static func replaceOriginal(_ original: URL, with output: URL) throws {
        let manager = FileManager.default
        do {
            _ = try manager.replaceItemAt(original, withItemAt: output)
        } catch {
            guard !manager.fileExists(atPath: original.path(percentEncoded: false)),
                  (try? manager.moveItem(at: output, to: original)) != nil else { throw error }
        }
    }

    /// Makes `output`'s folder when it is missing (`tmp/Mute` exists only once a log write has
    /// succeeded, and the launch clear removes `tmp/Trim`), and removes any file at `output`.
    private static func prepareOutput(_ output: URL) throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        removeOutput(output)
    }

    // MARK: The rewrite

    private typealias Sample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>

    /// One reader and one writer. The first video track is copied as stored, and the first audio
    /// track read as stored, decoded, silenced and encoded again, each on a task of its own, so the
    /// writer can interleave them. Recordings have no other tracks.
    private static func rewrite(_ source: URL, segments: [MuteInterval], to output: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingMuteError.couldNotRead
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)

        let (videoFormats, transform) = try await videoTrack.load(.formatDescriptions, .preferredTransform)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormats.first)
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        let video = Passage(from: reader.outputProvider(for: AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)),
                            to: writer.inputReceiver(for: videoInput))

        var audio: Passage?
        if let audioTrack {
            let (formats, range) = try await audioTrack.load(.formatDescriptions, .timeRange)
            guard let format = formats.first,
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
                throw RecordingMuteError.couldNotRead
            }
            let decoder = try AudioDecoder(format: format, end: range.end)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: description.mSampleRate,
                AVNumberOfChannelsKey: Int(description.mChannelsPerFrame),
                AVEncoderBitRateKey: audioBitRate,
            ])
            audioInput.expectsMediaDataInRealTime = false
            audio = Passage(from: reader.outputProvider(for: AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)),
                            to: writer.inputReceiver(for: audioInput), decoder: decoder)
        }

        try reader.start()
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        do {
            try await run(video, audio, silencing: segments)
        } catch {
            // Only once neither track reads or appends: a reader cancelled under a read crashed,
            // and a writer cancelled under an append it held never let the append return.
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
        guard reader.status != .failed else {
            writer.cancelWriting()
            throw reader.error ?? RecordingMuteError.couldNotRead
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? RecordingMuteError.couldNotWrite
        }
    }

    /// Runs both passages, each on a task of its own. At the first failure the other passage's task
    /// is cancelled, and it ends at its next sample: the failed passage has finished its input, so
    /// the writer holds no append back for it. The failure is thrown once both have ended.
    private static func run(_ video: Passage, _ audio: Passage?, silencing segments: [MuteInterval]) async throws {
        // Each passage goes to its own task, and nothing here touches it again.
        nonisolated(unsafe) let video = video
        nonisolated(unsafe) let audio = audio
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await video.run(silencing: nil) }
            if audio != nil {
                group.addTask { try await audio?.run(silencing: segments) }
            }
            do {
                while try await group.next() != nil {}
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// One track's way from the reader to the writer, through `decoder` for the audio.
    private struct Passage {
        let provider: AVAssetReaderOutput.Provider<Sample>
        let receiver: AVAssetWriterInput.SampleBufferReceiver
        let decoder: AudioDecoder?

        init(from provider: AVAssetReaderOutput.Provider<Sample>, to receiver: AVAssetWriterInput.SampleBufferReceiver,
             decoder: AudioDecoder? = nil) {
            self.provider = provider
            self.receiver = receiver
            self.decoder = decoder
        }

        /// Appends every sample, decoded when there is a decoder and with `segments` silenced when
        /// given, then the decoder's silence to the track's end, and finishes the input. A failure
        /// finishes it too, so the writer stops holding the other track back for it.
        func run(silencing segments: [MuteInterval]?) async throws {
            do {
                while true {
                    // Before each read, so a passage cancelled while the writer held its append
                    // ends here instead of reading on.
                    try Task.checkCancellation()
                    guard let read = try await provider.next() else { break }
                    if let decoder {
                        try decoder.decode(read)
                        try await append(from: decoder, silencing: segments)
                    } else {
                        try await append(read, silencing: segments)
                    }
                }
                try Task.checkCancellation()
                if let decoder {
                    try decoder.finish()
                    try await append(from: decoder, silencing: segments)
                }
            } catch {
                receiver.finish()
                throw error
            }
            receiver.finish()
        }

        /// Appends what `decoder` holds, a buffer at a time; a marker, or packets the trims take
        /// whole, leave it nothing.
        private func append(from decoder: AudioDecoder, silencing segments: [MuteInterval]?) async throws {
            while let sample = try decoder.nextBuffer() {
                try Task.checkCancellation()
                try await append(sample, silencing: segments)
            }
        }

        private func append(_ sample: Sample, silencing segments: [MuteInterval]?) async throws {
            try await receiver.append(try segments.map { try silenced(sample, segments: $0) } ?? sample)
        }
    }

    /// `sample`, a buffer of the decoder's, with its frames inside `segments` zeroed on a copy of its
    /// data; `sample` itself when none falls inside. A marker leaves the decoder nothing, so the
    /// check for a buffer with no sound is defensive. A buffer whose frames cannot be placed
    /// throws, so its sound never passes unmuted.
    private static func silenced(_ sample: Sample, segments: [MuteInterval]) throws -> Sample {
        let copy = try sample.withUnsafeSampleBuffer { buffer -> CMSampleBuffer? in
            guard buffer.numSamples > 0 else { return nil }
            guard let format = buffer.formatDescription,
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  description.mBytesPerFrame > 0, description.mSampleRate > 0,
                  buffer.presentationTimeStamp.isNumeric,
                  let source = buffer.dataBuffer else { throw RecordingMuteError.couldNotRead }
            let inside = frames(inside: segments, start: buffer.presentationTimeStamp.seconds,
                                count: buffer.numSamples, rate: description.mSampleRate)
            guard !inside.isEmpty else { return nil }
            // `CMBlockBufferCreateContiguous` with `kCMBlockBufferAlwaysCopyDataFlag`.
            let data = try source.makeContiguous(flags: .alwaysCopyData)
            let bytesPerFrame = Int(description.mBytesPerFrame)
            try data.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                for range in inside {
                    let lower = min(bytes.count, range.lowerBound * bytesPerFrame)
                    let upper = min(bytes.count, range.upperBound * bytesPerFrame)
                    if upper > lower { memset(base + lower, 0, upper - lower) }
                }
            }
            let silenced = try CMSampleBuffer(dataBuffer: data, formatDescription: format, numSamples: buffer.numSamples,
                                              presentationTimeStamp: buffer.presentationTimeStamp, packetDescriptions: [])
            buffer.propagateAttachments(to: silenced)
            // A new buffer over the new copy: nothing else holds it.
            nonisolated(unsafe) let made: CMSampleBuffer? = silenced
            return made
        }
        guard let copy else { return sample }
        nonisolated(unsafe) let made = copy
        return Sample(unsafeBuffer: made)
    }

    /// The frames of a buffer of `count` frames from `start` s whose time falls inside a segment,
    /// rounded outward to whole frames. An open segment runs to the end.
    private static func frames(inside segments: [MuteInterval], start: TimeInterval, count: Int,
                               rate: Double) -> [Range<Int>] {
        func frame(at time: TimeInterval, _ rule: FloatingPointRoundingRule) -> Int {
            Int(min(Double(count), max(0, ((time - start) * rate).rounded(rule))))
        }
        return segments.compactMap { segment in
            let first = frame(at: segment.start, .down)
            let last = segment.end.map { frame(at: $0, .up) } ?? count
            return last > first ? first..<last : nil
        }
    }
}

/// Why a mute step failed when AVFoundation gave no error of its own.
nonisolated enum RecordingMuteError: LocalizedError {
    case couldNotRead
    case couldNotWrite

    var errorDescription: String? {
        switch self {
        case .couldNotRead: "The recording could not be read."
        case .couldNotWrite: "The muted copy could not be written."
        }
    }
}

#if DEBUG
extension RecordingMute {
    /// Fault injection (design, Fault injection): `-MuteFailure apply` makes the live `apply` throw,
    /// and `-MuteFailure both` makes `stripAudio` throw too, at the end of a recording and in
    /// recovery alike (`open TidyShot.app --args -MuteFailure both`). Debug builds only.
    nonisolated enum MuteFailure: Equatable {
        case apply
        case both

        static let argumentKey = "MuteFailure"

        init?(argument: String?) {
            switch argument {
            case "apply": self = .apply
            case "both": self = .both
            default: return nil
            }
        }

        /// `steps` with the failing ones replaced by a throw.
        func wrap(_ steps: Steps) -> Steps {
            var wrapped = steps
            wrapped.apply = { _, _, _ in throw Injected() }
            if self == .both {
                wrapped.stripAudio = { _, _ in throw Injected() }
            }
            return wrapped
        }

        struct Injected: LocalizedError {
            var errorDescription: String? { "It failed on purpose (-MuteFailure)." }
        }
    }
}
#endif
