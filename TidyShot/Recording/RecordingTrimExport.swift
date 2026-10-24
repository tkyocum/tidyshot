import AVFoundation
import CoreMedia
import Foundation

// Trim's export (design, Trim, Export): the method, Save's export, the export and the re-encode, off
// the main actor. The decisions are in RecordingTrim.swift.
nonisolated extension RecordingTrim {
    // MARK: The method

    /// Whether the video sample shown at `start`, in the asset's time, is a full sync sample, so a
    /// passthrough from there keeps no earlier frame (design, Method). A sample cursor works in media
    /// time, and a recording's video track starts with an edit to a later media time, so `start` is
    /// mapped through the track's edit list first (Decided 2026-10-24, 3). A start in an empty edit or
    /// outside every edit, and a track that cannot give a cursor, are false: doubt re-encodes. An
    /// empty edit's source has no numeric start, which `mediaTime` refuses.
    @concurrent
    static func startsOnSyncSample(_ url: URL, at start: CMTime) async throws -> Bool {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingTrimError.couldNotRead
        }
        let (canProvideCursors, segments) = try await track.load(.canProvideSampleCursors, .segments)
        guard canProvideCursors, let media = mediaTime(of: start, through: segments.map(\.timeMapping)),
              let cursor = track.makeSampleCursor(presentationTimeStamp: media) else { return false }
        // The cursor's sample is the one shown at that time only when it starts at or before it.
        return CMTimeCompare(cursor.presentationTimeStamp, media) <= 0
            && cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue
    }

    /// `time`, on a track's timeline, as the media time its edit list shows there: the segment whose
    /// target range holds it gives its source start plus how far into the segment `time` is, scaled
    /// by the segment's rate. Nil in an empty edit (a source with no numeric start) and outside every
    /// segment.
    static func mediaTime(of time: CMTime, through mappings: [CMTimeMapping]) -> CMTime? {
        guard time.isNumeric,
              let mapping = mappings.first(where: { $0.target.isValid && $0.target.containsTime(time) }),
              mapping.source.isValid, mapping.source.start.isNumeric, mapping.source.duration.isNumeric else {
            return nil
        }
        return CMTimeMapTimeFromRangeToRange(time, fromRange: mapping.target, toRange: mapping.source)
    }

    // MARK: The export for Save

    /// What a pass writes in its folder, before the 1 GB `RecordingLimits.hasRoom` adds (design, Disk
    /// space): the source's size for a passthrough, twice that for a re-encode, which can come out
    /// larger than its source (Decided 2026-10-24, 2), and the source's size again for the mute step's
    /// copy.
    static func bytesNeeded(sourceBytes: Int64, method: TrimMethod, mutes: Bool) -> Int64 {
        sourceBytes * (method == .reencode ? 2 : 1) + (mutes ? sourceBytes : 0)
    }

    /// Save's export (design, Export, Disk space, Cleanup). It makes `directory` when it is missing
    /// (the launch clears `tmp/Trim`, and a pending or save-folder source downloads nothing into it),
    /// then refuses with `notEnoughSpace` before writing anything unless `freeBytes` leaves room for
    /// `bytesNeeded` plus 1 GB. A source whose size cannot be read throws `couldNotRead` there: the
    /// check fails closed. A record with `unmutedIntervals` is muted first, with
    /// `RecordingMute.apply` into `<id>-muted.mp4`, and that copy trimmed, so its muted sound never
    /// reaches the trimmed file. It returns `<id>-trimmed.mp4`. `<id>-muted.mp4` is gone on every
    /// exit, and a failed or cancelled export removes its own output. `source` is only read.
    /// `directory` is for tests.
    @concurrent
    static func exportForSave(_ source: URL, id: UUID, range: CMTimeRange, method: TrimMethod,
                              unmutedIntervals: [MuteInterval], directory: URL = RecordingTrim.directory,
                              freeBytes: @escaping @Sendable () -> Int64?,
                              progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let trimmed = trimmedURL(for: id, in: directory)
        let muted = mutedURL(for: id, in: directory)
        // Each step clears its output first, so neither may be the recording.
        guard !isSameFile(source, trimmed), !isSameFile(source, muted) else { throw RecordingTrimError.couldNotWrite }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: muted) }
        let mutes = !unmutedIntervals.isEmpty
        guard let sourceSize = FileSizes.byteCount(of: source) else { throw RecordingTrimError.couldNotRead }
        guard RecordingLimits.hasRoom(for: bytesNeeded(sourceBytes: Int64(sourceSize), method: method, mutes: mutes),
                                      freeBytes: freeBytes()) else {
            throw RecordingTrimError.notEnoughSpace
        }
        var input = source
        if mutes {
            try await RecordingMute.apply(source, intervals: unmutedIntervals, to: muted)
            input = muted
        }
        try await export(input, range: range, method: method, to: trimmed, progress: progress)
        return trimmed
    }

    // MARK: The export

    /// Writes `range` of `source` to `output` as an MP4 (design, Export): `.passthrough` with an
    /// `AVAssetExportSession`, or `.reencode` with TidyShot's own pass. `progress` gets fractions
    /// that never decrease, then 1 once the file is written; a passthrough reports only the 1.
    /// `output`'s folder is made when it is missing, and any file there is replaced. A throw or a
    /// cancel removes what was written. `source` is only read.
    @concurrent
    static func export(_ source: URL, range: CMTimeRange, method: TrimMethod, to output: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !isSameFile(source, output) else { throw RecordingTrimError.couldNotWrite }
        guard range.isValid, range.start.isNumeric, range.duration.isNumeric, range.duration > .zero else {
            throw RecordingTrimError.couldNotRead
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        do {
            try Task.checkCancellation()
            switch method {
            case .passthrough: try await passthrough(source, range: range, to: output)
            case .reencode: try await reencode(source, range: range, to: output, progress: progress)
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        progress(1)
    }

    /// Whether two file URLs name the same file, symbolic links resolved: by the file system's
    /// identity when both exist, so a hard link or another spelling of the path (APFS ignores case)
    /// counts, and otherwise by their standardized paths.
    static func isSameFile(_ one: URL, _ other: URL) -> Bool {
        let one = one.standardizedFileURL.resolvingSymlinksInPath()
        let other = other.standardizedFileURL.resolvingSymlinksInPath()
        if let first = fileIdentity(of: one), let second = fileIdentity(of: other) {
            return first.isEqual(second)
        }
        return one.path(percentEncoded: false) == other.path(percentEncoded: false)
    }

    /// The file's `fileResourceIdentifier`, read afresh; nil when it cannot be read, as for a file
    /// that is not there.
    private static func fileIdentity(of url: URL) -> (any NSCopying & NSSecureCoding & NSObjectProtocol)? {
        var url = url
        url.removeAllCachedResourceValues()
        return try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
    }

    /// The design's `.passthrough`: the samples from the sync sample shown at the start, copied, with
    /// at most two AAC packets of audio before the start, hidden by the edit list (Decided 2026-10-23, 3).
    private static func passthrough(_ source: URL, range: CMTimeRange, to output: URL) async throws {
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source),
                                                 presetName: AVAssetExportPresetPassthrough) else {
            throw RecordingTrimError.couldNotWrite
        }
        session.timeRange = range
        try await session.export(to: output, as: .mp4)
    }

    // MARK: The re-encode

    /// The design's `.reencode` (Decided 2026-10-24, 1 and 4), built as `RecordingMute.apply` is: one
    /// reader limited to `range`, one writer, and a task per track. The first video track is decoded
    /// and encoded again as H.264 at the source's size; the first audio track is read as stored,
    /// decoded by `AudioDecoder`, cut at the range's ends to the frame and encoded again as AAC. So
    /// nothing from before the start is in the file. The session runs from 0 to the range's duration.
    private static func reencode(_ source: URL, range: CMTimeRange, to output: URL,
                                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingTrimError.couldNotRead
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)

        let (formats, transform, dataRate, dataLength, videoRange) = try await videoTrack.load(
            .formatDescriptions, .preferredTransform, .estimatedDataRate, .totalSampleDataLength, .timeRange)
        guard let videoFormat = formats.first else { throw RecordingTrimError.couldNotRead }
        let bitRate = averageBitRate(estimated: dataRate, bytes: dataLength, over: videoRange.duration)
        guard let videoInput = videoInput(for: videoFormat, bitRate: bitRate, transform: transform, canApply: {
            writer.canApply(outputSettings: $0, forMediaType: .video)
        }) else { throw RecordingTrimError.couldNotWrite }
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        let video = VideoCut(provider: reader.outputProvider(for: videoOutput),
                             receiver: writer.inputReceiver(for: videoInput), range: range, progress: progress)

        var audio: AudioCut?
        if let audioTrack {
            let (formats, audioRange) = try await audioTrack.load(.formatDescriptions, .timeRange)
            guard let format = formats.first,
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
                throw RecordingTrimError.couldNotRead
            }
            let decoder = try AudioDecoder(format: format, end: audioRange.end)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: TrackPass.aacSettings(for: description))
            audioInput.expectsMediaDataInRealTime = false
            audio = AudioCut(provider: reader.outputProvider(for: AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)),
                             receiver: writer.inputReceiver(for: audioInput), decoder: decoder,
                             frames: try frames(of: range, rate: description.mSampleRate), rate: description.mSampleRate)
        }

        // Each track on a task of its own, as in `RecordingMute.apply`, and the session to the range's
        // duration (`TrackPass.run`).
        var tracks: [() async throws -> Void] = [{ try await video.run() }]
        if let audio {
            tracks.append { try await audio.run() }
        }
        try await TrackPass.run(reader: reader, writer: writer, tracks: tracks, endingAt: range.duration,
                                readError: RecordingTrimError.couldNotRead, writeError: RecordingTrimError.couldNotWrite)
    }

    /// The video's average bit rate: its estimated data rate, or its sample data over its duration
    /// when that is 0. Nil when neither is known, which leaves the encoder its own.
    static func averageBitRate(estimated: Float, bytes: Int64, over duration: CMTime) -> Int? {
        if estimated.isFinite, estimated >= 1 { return Int(estimated) }
        guard bytes > 0, duration.isNumeric, duration.seconds > 0 else { return nil }
        return Int(Double(bytes) * 8 / duration.seconds)
    }

    /// The re-encode's H.264 settings at `format`'s encoded size (design, `.reencode`): High profile,
    /// `bitRate` on average, a sync frame at least every 2 s and no frame reordering. First with the
    /// source's colour primaries, transfer function and YCbCr matrix when its format description
    /// carries all three, then without them, for a writer that cannot apply them.
    static func videoSettings(for format: CMFormatDescription, bitRate: Int?) -> [[String: Any]] {
        let size = CMVideoFormatDescriptionGetDimensions(format)
        var compression: [String: Any] = [
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if let bitRate { compression[AVVideoAverageBitRateKey] = bitRate }
        let plain: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: compression,
        ]
        func colour(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
        }
        guard let primaries = colour(kCMFormatDescriptionExtension_ColorPrimaries),
              let transfer = colour(kCMFormatDescriptionExtension_TransferFunction),
              let matrix = colour(kCMFormatDescriptionExtension_YCbCrMatrix) else { return [plain] }
        var coloured = plain
        coloured[AVVideoColorPropertiesKey] = [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix,
        ]
        return [coloured, plain]
    }

    /// The re-encode's video writer input: the first of `videoSettings` that `canApply` takes (the
    /// writer's own check, asked first because `AVAssetWriterInput` raises on settings it cannot take),
    /// with the source track's `transform`. Nil when it takes none.
    static func videoInput(for format: CMFormatDescription, bitRate: Int?, transform: CGAffineTransform,
                           canApply: ([String: Any]) -> Bool) -> AVAssetWriterInput? {
        guard let settings = videoSettings(for: format, bitRate: bitRate).first(where: canApply) else { return nil }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.transform = transform
        input.expectsMediaDataInRealTime = false
        return input
    }

    /// `range` in whole frames at `rate`, as `AudioDecoder` places them: from the frame at its start to
    /// the one at its end.
    static func frames(of range: CMTimeRange, rate: Double) throws -> Range<Int> {
        let start = (range.start.seconds * rate).rounded()
        let end = (range.end.seconds * rate).rounded()
        guard range.start.isNumeric, range.end.isNumeric, start >= 0, end >= start, end <= 0x1p53 else {
            throw RecordingTrimError.couldNotRead
        }
        return Int(start)..<Int(end)
    }

    /// The video's way through a re-encode: decoded frames, each written at its presentation time
    /// minus the range's start, the frame shown at the start at 0, and none from before it or from the
    /// range's end on. Each is shown until the next or the range's end, so a last frame held over a
    /// still screen lasts to the end. `progress` gets the last written frame's time over the range's
    /// duration, at most every 0.1 s and never less than before.
    private struct VideoCut {
        let provider: AVAssetReaderOutput.Provider<ReadySample>
        let receiver: AVAssetWriterInput.SampleBufferReceiver
        let range: CMTimeRange
        let progress: @Sendable (Double) -> Void

        /// Writes the frames, then finishes the input. A failure finishes it too, so the writer stops
        /// holding the other track back for it. A range with no frame to show throws, rather than give
        /// a file with no picture.
        func run() async throws {
            do {
                // The latest frame at or before the start: the one shown there.
                var shown: ReadySample?
                var last: CMTime?
                var reported = 0.0
                var reportedAt: ContinuousClock.Instant?
                while true {
                    // Before each read, as in `RecordingMute.apply`.
                    try Task.checkCancellation()
                    guard let read = try await provider.next() else { break }
                    let time = read.presentationTimeStamp
                    guard read.withUnsafeSampleBuffer({ CMSampleBufferGetImageBuffer($0) != nil }), time.isNumeric else {
                        continue
                    }
                    if time <= range.start {
                        shown = read
                        continue
                    }
                    guard time < range.end else { break }
                    if let frame = shown {
                        last = try await write(frame, at: .zero, after: last)
                        shown = nil
                    }
                    last = try await write(read, at: time - range.start, after: last)
                    let fraction = (time - range.start).seconds / range.duration.seconds
                    let now = ContinuousClock.now
                    if fraction > reported, fraction < 1, reportedAt.map({ now - $0 >= .milliseconds(100) }) ?? true {
                        progress(fraction)
                        reported = fraction
                        reportedAt = now
                    }
                }
                if let frame = shown {
                    last = try await write(frame, at: .zero, after: last)
                }
                guard last != nil else { throw RecordingTrimError.couldNotRead }
            } catch {
                receiver.finish()
                throw error
            }
            receiver.finish()
        }

        /// Appends `frame` retimed to `time`, unless that is not after `last`; gives the last time
        /// written. Its duration runs to the range's end: the writer takes a frame's duration from the
        /// next one's time, so only the last keeps it, and without it the last lasts as long as the one
        /// before it.
        private func write(_ frame: ReadySample, at time: CMTime, after last: CMTime?) async throws -> CMTime? {
            if let last, time <= last { return last }
            let retimed = try frame.withUnsafeSampleBuffer { buffer -> CMSampleBuffer in
                let timing = CMSampleTimingInfo(duration: range.duration - time, presentationTimeStamp: time,
                                                decodeTimeStamp: .invalid)
                let copy = try CMSampleBuffer(copying: buffer, withNewTiming: [timing])
                // A new buffer: nothing else holds it.
                nonisolated(unsafe) let made = copy
                return made
            }
            nonisolated(unsafe) let made = retimed
            try await receiver.append(ReadySample(unsafeBuffer: made))
            return time
        }
    }

    /// The sound's way through a re-encode: packets as stored, decoded by `AudioDecoder`, and only the
    /// frames from the range's start to its end, moved back by the start, so the sound starts and ends
    /// with the range to the frame (Decided 2026-10-24, 4).
    private struct AudioCut {
        let provider: AVAssetReaderOutput.Provider<ReadySample>
        let receiver: AVAssetWriterInput.SampleBufferReceiver
        let decoder: AudioDecoder
        /// The range in frames at the source's rate.
        let frames: Range<Int>
        let rate: Double

        /// Appends the range's sound, then finishes the input. A failure finishes it too.
        func run() async throws {
            do {
                var ended = false
                while !ended {
                    try Task.checkCancellation()
                    guard let read = try await provider.next() else { break }
                    try decoder.decode(read)
                    ended = try await appendDecoded()
                }
                if !ended {
                    // Silence to the track's end, where an empty edit ends the sound.
                    try Task.checkCancellation()
                    try decoder.finish()
                    _ = try await appendDecoded()
                }
            } catch {
                receiver.finish()
                throw error
            }
            receiver.finish()
        }

        /// Appends what `decoder` holds inside the range; true once it reaches the range's end, after
        /// which nothing more is wanted.
        private func appendDecoded() async throws -> Bool {
            while let sample = try decoder.nextBuffer() {
                try Task.checkCancellation()
                if let inside = try RecordingTrim.cut(sample, to: frames, rate: rate) {
                    try await receiver.append(inside)
                }
                let first = Int((sample.presentationTimeStamp.seconds * rate).rounded())
                if first + sample.sampleCount >= frames.upperBound { return true }
            }
            return false
        }
    }

    /// The frames of `sample`, a PCM buffer of the decoder's, that fall inside `frames`, copied and
    /// moved back by its lower bound; nil when none does. The reader's time range already ends the
    /// sound at the range's end; the upper bound here holds it there whatever the reader gives.
    static func cut(_ sample: ReadySample, to frames: Range<Int>, rate: Double) throws -> ReadySample? {
        let inside = try sample.withUnsafeSampleBuffer { buffer -> CMSampleBuffer? in
            guard let format = buffer.formatDescription,
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  description.mBytesPerFrame > 0, buffer.presentationTimeStamp.isNumeric,
                  let data = buffer.dataBuffer else { throw RecordingTrimError.couldNotRead }
            let first = Int((buffer.presentationTimeStamp.seconds * rate).rounded())
            let lower = max(first, frames.lowerBound)
            let upper = min(first + buffer.numSamples, frames.upperBound)
            guard upper > lower else { return nil }
            let bytesPerFrame = Int(description.mBytesPerFrame)
            let offset = (lower - first) * bytesPerFrame
            let length = (upper - lower) * bytesPerFrame
            let block = try CMBlockBuffer(length: length, flags: .assureMemoryNow)
            try block.withUnsafeMutableBytes { destination in
                try data.withContiguousStorage { source in
                    guard let to = destination.baseAddress, let from = source.baseAddress,
                          offset + length <= source.count else { throw RecordingTrimError.couldNotRead }
                    memcpy(to, from + offset, length)
                }
            }
            let cut = try CMSampleBuffer(dataBuffer: block, formatDescription: format, numSamples: upper - lower,
                                         presentationTimeStamp: CMTime(value: CMTimeValue(lower - frames.lowerBound),
                                                                       timescale: CMTimeScale(rate)),
                                         packetDescriptions: [])
            // A new buffer over a new block: nothing else holds it.
            nonisolated(unsafe) let made: CMSampleBuffer? = cut
            return made
        }
        guard let inside else { return nil }
        nonisolated(unsafe) let made = inside
        return ReadySample(unsafeBuffer: made)
    }
}
