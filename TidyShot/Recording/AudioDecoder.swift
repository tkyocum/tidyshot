import AVFoundation
import CoreMedia
import Foundation

/// The audio's way to 16-bit interleaved PCM. The reader's own PCM output sets up an audio queue
/// on the output device, and a device slow to answer held a rewrite there for 90 s (design, The
/// suite's time); `AVAudioConverter` decodes the packets as stored without one. What the reader
/// marks for trimming (the AAC priming, the padding after the last frame) is dropped, each buffer
/// starts at its output time, and a gap before one (an empty edit) is filled with silence, as is
/// a gap after the last up to the end of the track's time range. So the sound runs from 0 to
/// there without a break, and each frame lands where the reader's PCM put it. Silence goes out at
/// most a second to a buffer, so a long gap never makes one huge buffer. A buffer the reader
/// marks for a decoder reset (where another edit starts) resets the converter first. One decoder
/// serves one pass: `RecordingMute`'s rewrite or `RecordingTrim`'s re-encode.
nonisolated final class AudioDecoder {
    private let format: CMAudioFormatDescription
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let converter: AVAudioConverter
    private let rate: Double
    private let framesPerPacket: Int
    private let bytesPerFrame: Int
    /// The most silence a buffer holds: a second's frames.
    private let chunk: Int
    /// The frame the track's time range ends at.
    private let end: Int
    /// The frame the next buffer starts at.
    private var next = 0
    /// What `nextBuffer()` has still to hand out: silence up to frame `start`, then `frames` of
    /// `sound`, the decoded buffer.
    private var waiting: (start: Int, sound: AVAudioPCMBuffer?, frames: Range<Int>)?

    /// Throws for a track whose packets the converter cannot take as AAC's, which have a variable
    /// size and a fixed number of frames, at a whole sample rate a `CMTimeScale` holds; and for an
    /// `end` (the track's) that is not numeric or out of range.
    init(format: CMAudioFormatDescription, end: CMTime) throws {
        guard let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              description.mBytesPerPacket == 0, description.mFramesPerPacket > 0,
              description.mSampleRate > 0, description.mSampleRate == description.mSampleRate.rounded(),
              description.mSampleRate <= Double(CMTimeScale.max) else {
            throw RecordingMuteError.couldNotRead
        }
        let input = AVAudioFormat(cmAudioFormatDescription: format)
        guard let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: input.sampleRate,
                                         channels: input.channelCount, interleaved: true),
              let converter = AVAudioConverter(from: input, to: output) else {
            throw RecordingMuteError.couldNotRead
        }
        // The converter neither drops nor adds frames at the start: the reader's trim drops the
        // priming, once.
        converter.primeMethod = .none
        self.format = format
        self.input = input
        self.output = output
        self.converter = converter
        rate = description.mSampleRate
        framesPerPacket = Int(description.mFramesPerPacket)
        bytesPerFrame = Int(output.streamDescription.pointee.mBytesPerFrame)
        chunk = Int(rate)
        self.end = try Self.frames(end, rate: rate)
    }

    /// Decodes `sample`'s packets and trims them, for `nextBuffer()` to place at its output time
    /// after the silence of any gap since the last; a marker or packets the trims take whole
    /// leave nothing. A decode that fails, or frames that cannot be placed, throw.
    func decode(_ sample: ReadySample) throws {
        guard waiting == nil else { throw RecordingMuteError.couldNotRead }
        try sample.withUnsafeSampleBuffer { buffer in
            guard buffer.numSamples > 0 else { return }
            guard let bufferFormat = buffer.formatDescription,
                  CMFormatDescriptionEqual(bufferFormat, otherFormatDescription: format),
                  let data = buffer.dataBuffer else { throw RecordingMuteError.couldNotRead }
            // Another edit starts here: its pre-roll packets decode without the last one's state.
            if (CMGetAttachment(buffer, key: kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding,
                                attachmentModeOut: nil) as? Bool) == true {
                converter.reset()
            }
            let pcm = try decode(packets: try buffer.audioStreamPacketDescriptions(), data: data,
                                 frames: try frames(buffer.duration))
            let dropped = try frames(trim(kCMSampleBufferAttachmentKey_TrimDurationAtStart, of: buffer))
            let cut = try frames(trim(kCMSampleBufferAttachmentKey_TrimDurationAtEnd, of: buffer))
            let start = try frames(buffer.outputPresentationTimeStamp)
            let count = try frames(buffer.outputDuration)
            // The trims account for every frame (no speed change), and nothing goes back in time.
            guard dropped >= 0, cut >= 0, count >= 0, dropped + count + cut == Int(pcm.frameLength),
                  start >= next else { throw RecordingMuteError.couldNotRead }
            guard count > 0 else { return }
            waiting = (start, pcm, dropped..<dropped + count)
        }
    }

    /// Leaves the silence from the last frame placed to the end of the track's time range, where
    /// an empty edit ends the sound, for `nextBuffer()`; nothing when the sound reaches it.
    func finish() throws {
        guard waiting == nil else { throw RecordingMuteError.couldNotRead }
        if end > next { waiting = (end, nil, 0..<0) }
    }

    /// The next PCM buffer of what `decode` or `finish` left, nil once it is all out: a second of
    /// silence while more than that is left before the sound, then the rest of the silence with
    /// the sound, if there is any.
    func nextBuffer() throws -> ReadySample? {
        guard let waiting else { return nil }
        let placed: CMSampleBuffer
        if waiting.start - next > chunk {
            placed = try place(nil, frames: 0..<0, at: next + chunk)
        } else {
            self.waiting = nil
            placed = try place(waiting.sound, frames: waiting.frames, at: waiting.start)
        }
        // A new buffer over a new block: nothing else holds it.
        nonisolated(unsafe) let made = placed
        return ReadySample(unsafeBuffer: made)
    }

    /// A PCM buffer from the last frame placed: silence up to frame `start`, then `frames` of
    /// `sound`.
    private func place(_ sound: AVAudioPCMBuffer?, frames: Range<Int>, at start: Int) throws -> CMSampleBuffer {
        let gap = start - next
        let count = frames.count
        // Nothing goes back in time, no buffer is made empty, and the frames are the sound's.
        guard gap >= 0, gap + count > 0, frames.lowerBound >= 0,
              frames.upperBound <= Int(sound?.frameLength ?? 0) else { throw RecordingMuteError.couldNotRead }
        let block = try CMBlockBuffer(length: (gap + count) * bytesPerFrame, flags: .assureMemoryNow)
        try block.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { throw RecordingMuteError.couldNotRead }
            memset(base, 0, gap * bytesPerFrame)
            guard count > 0 else { return }
            guard let source = sound?.audioBufferList.pointee.mBuffers.mData else {
                throw RecordingMuteError.couldNotRead
            }
            memcpy(base + gap * bytesPerFrame, source + frames.lowerBound * bytesPerFrame, count * bytesPerFrame)
        }
        let placed = try CMSampleBuffer(dataBuffer: block, formatDescription: output.formatDescription,
                                        numSamples: gap + count,
                                        presentationTimeStamp: CMTime(value: CMTimeValue(next),
                                                                      timescale: CMTimeScale(rate)),
                                        packetDescriptions: [])
        next = start + count
        return placed
    }

    /// One buffer's packets decoded in one pass. Exactly `frames` must come out: the converter
    /// holds nothing back, so the frames are those packets' own.
    private func decode(packets: [AudioStreamPacketDescription], data: CMBlockBuffer,
                        frames: Int) throws -> AVAudioPCMBuffer {
        guard let largest = packets.map({ Int($0.mDataByteSize) }).max(), largest > 0 else {
            throw RecordingMuteError.couldNotRead
        }
        let compressed = AVAudioCompressedBuffer(format: input, packetCapacity: AVAudioPacketCount(packets.count),
                                                 maximumPacketSize: largest)
        guard data.dataLength <= compressed.byteCapacity, let descriptions = compressed.packetDescriptions,
              let capacity = AVAudioFrameCount(exactly: frames + framesPerPacket),
              let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else {
            throw RecordingMuteError.couldNotRead
        }
        try data.copyDataBytes(to: UnsafeMutableRawBufferPointer(start: compressed.data, count: data.dataLength))
        compressed.byteLength = UInt32(data.dataLength)
        compressed.packetCount = AVAudioPacketCount(packets.count)
        for (index, packet) in packets.enumerated() {
            descriptions[index] = packet
        }
        var pending: AVAudioCompressedBuffer? = compressed
        var error: NSError?
        let status = converter.convert(to: pcm, error: &error) { _, status in
            status.pointee = pending == nil ? .noDataNow : .haveData
            defer { pending = nil }
            return pending
        }
        guard status != .error, Int(pcm.frameLength) == frames else {
            throw error ?? RecordingMuteError.couldNotRead
        }
        return pcm
    }

    /// `time` in whole frames.
    private func frames(_ time: CMTime) throws -> Int {
        try Self.frames(time, rate: rate)
    }

    /// `time` in whole frames at `rate`. A time that is not numeric, or past the 2^53 frames a
    /// `Double` counts exactly (thousands of years), throws, so no sum of a few of them overflows.
    private static func frames(_ time: CMTime, rate: Double) throws -> Int {
        let frames = (time.seconds * rate).rounded()
        guard time.isNumeric, abs(frames) <= 0x1p53 else { throw RecordingMuteError.couldNotRead }
        return Int(frames)
    }

    /// The trim `key` marks on `buffer`; zero when there is none.
    private func trim(_ key: CFString, of buffer: CMSampleBuffer) -> CMTime {
        guard let value = CMGetAttachment(buffer, key: key, attachmentModeOut: nil) else { return .zero }
        return CMTimeMakeFromDictionary(value as? NSDictionary as CFDictionary?)
    }
}
