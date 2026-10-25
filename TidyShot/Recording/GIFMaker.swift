import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import VideoToolbox

/// What `GIFMaker.make` wrote.
nonisolated struct GIFResult: Equatable, Sendable {
    var pixelWidth: Int
    var pixelHeight: Int
    /// Output frames at the GIF's rate, held ones included.
    var outputFrameCount: Int
    /// Frames in the file, after merging and the splitting of long delays.
    var gifFrameCount: Int
    /// From the frames: `GIFTiming.centiseconds(through: outputFrameCount, fps:) / 100` s.
    var duration: TimeInterval
    var byteCount: Int
}

/// Makes a GIF from a finished recording's MP4 (design, Conversion), off the main actor. Two
/// sequential reads of the video track: the first builds the palette from 32 sampled output
/// frames, the second hands every output frame that shows a new source frame to `GIFEncoder`,
/// which writes the file as it goes. It holds no GIF logic of its own.
nonisolated enum GIFMaker {
    /// The palette pass's share of the progress, from the spike's timing (0.6 s of 3.8 s).
    static let paletteShare = 0.15
    static let paletteSampleCount = 32

    /// Writes `gif` from `mp4` at `fps`, the longer side at most `maxSide` (never upscaled).
    /// `freeBytes` is the GIF's volume, read again every 32 MB written. `progress` goes from 0 to 1,
    /// at most 10 times a second, never decreasing, and once at 1. Any throw, a cancel included,
    /// closes and removes `gif`.
    @concurrent
    static func make(from mp4: URL, to gif: URL, fps: Int, maxSide: Int,
                     freeBytes: @escaping @Sendable () -> Int64?,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> GIFResult {
        let reporter = ProgressReporter(progress)
        do {
            let source = try await Source(mp4)
            let frameCount = outputFrameCount(duration: source.duration, fps: fps)
            let size = outputSize(width: source.width, height: source.height, maxSide: maxSide)
            let canvas = try Canvas(width: size.width, height: size.height)
            let palette = try await makePalette(source, frameCount: frameCount, fps: fps, canvas: canvas, reporter: reporter)
            let summary = try await encode(source, to: gif, frameCount: frameCount, fps: fps, palette: palette,
                                           canvas: canvas, freeBytes: freeBytes, reporter: reporter)
            reporter.report(1)
            return GIFResult(pixelWidth: size.width, pixelHeight: size.height, outputFrameCount: frameCount,
                             gifFrameCount: summary.gifFrameCount,
                             duration: Double(GIFTiming.centiseconds(through: frameCount, fps: fps)) / 100,
                             byteCount: summary.byteCount)
        } catch {
            try? FileManager.default.removeItem(at: gif)
            throw error
        }
    }

    /// `F = max(1, ⌈duration × fps − 10⁻⁶⌉)`: output frame `i` is at `i / fps`.
    static func outputFrameCount(duration: TimeInterval, fps: Int) -> Int {
        guard duration.isFinite, duration > 0, fps > 0 else { return 1 }
        return max(1, Int((duration * Double(fps) - 1e-6).rounded(.up)))
    }

    /// The palette pass's output frames: 32 spread evenly, `round(k × (F − 1) / 31)`, or every
    /// one when there are at most 32.
    static func paletteSampleIndices(frameCount: Int) -> [Int] {
        guard frameCount > paletteSampleCount else { return Array(0..<max(1, frameCount)) }
        let steps = paletteSampleCount - 1
        // Rounded half up in integers.
        return (0..<paletteSampleCount).map { (2 * $0 * (frameCount - 1) + steps) / (2 * steps) }
    }

    /// The longer side at `maxSide` and the other rounded to whole pixels, never upscaled.
    static func outputSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        let longer = max(width, height)
        guard maxSide > 0, longer > maxSide else { return (max(1, width), max(1, height)) }
        let scale = Double(maxSide) / Double(longer)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    // MARK: The passes

    /// Pass 1: the sampled output frames, each scaled and added once per source frame. It reports
    /// up to the last sample; the palette share itself is reported once the GIF's file is open.
    private static func makePalette(_ source: Source, frameCount: Int, fps: Int, canvas: Canvas,
                                    reporter: ProgressReporter) async throws -> GIFPalette {
        var builder = GIFPaletteBuilder()
        var frames = try await FrameReader(source)
        let samples = paletteSampleIndices(frameCount: frameCount)
        let last = samples.last ?? 0
        var added: Int?
        for index in samples {
            try Task.checkCancellation()
            try await frames.advance(to: time(of: index, fps: fps))
            if frames.shownNumber != added {
                try frames.drawShown(into: canvas)
                canvas.withPixels { builder.add(rgba: $0) }
                added = frames.shownNumber
            }
            if index < last {
                reporter.report(paletteShare * Double(index) / Double(last))
            }
        }
        frames.cancel()
        return builder.build()
    }

    /// Pass 2: every output frame in order. One that shows the same source frame as the one before
    /// is held and costs nothing; any other is scaled and added.
    private static func encode(_ source: Source, to gif: URL, frameCount: Int, fps: Int, palette: GIFPalette,
                               canvas: Canvas, freeBytes: @escaping @Sendable () -> Int64?,
                               reporter: ProgressReporter) async throws -> GIFEncoderSummary {
        var frames = try await FrameReader(source)
        var sink = try GIFFileSink(url: gif, freeBytes: freeBytes)
        var encoder: GIFEncoder<GIFFileSink>
        do {
            encoder = try GIFEncoder(sink: sink, width: canvas.width, height: canvas.height, fps: fps, palette: palette)
        } catch {
            try? sink.close()
            throw error
        }
        do {
            reporter.report(paletteShare, force: true)
            var added: Int?
            for index in 0..<frameCount {
                try Task.checkCancellation()
                reporter.report(paletteShare + (1 - paletteShare) * Double(index) / Double(frameCount))
                try await frames.advance(to: time(of: index, fps: fps))
                guard frames.shownNumber != added else { continue }
                try frames.drawShown(into: canvas)
                try canvas.withPixels { try encoder.add(rgba: $0, at: index) }
                added = frames.shownNumber
            }
            frames.cancel()
            return try encoder.finish(frameCount: frameCount)
        } catch {
            frames.cancel()
            encoder.abandon()
            throw error
        }
    }

    private static func time(of index: Int, fps: Int) -> CMTime {
        CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps))
    }

    // MARK: Reading

    /// The MP4's video track, with its pixel size and the asset's duration. Recordings are
    /// unrotated, so no track transform applies.
    private struct Source {
        let asset: AVURLAsset
        let track: AVAssetTrack
        let width: Int
        let height: Int
        let duration: TimeInterval

        init(_ url: URL) async throws {
            asset = AVURLAsset(url: url)
            do {
                let time = try await asset.load(.duration)
                guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw GIFMakerError.couldNotRead
                }
                let size = try await track.load(.naturalSize)
                self.track = track
                width = Int(size.width.rounded())
                height = Int(size.height.rounded())
                duration = time.isNumeric ? max(0, time.seconds) : 0
            } catch {
                if Task.isCancelled { throw CancellationError() }
                RecordingLog.note("Recording: \(url.lastPathComponent) could not be read for a GIF: \(error.localizedDescription)")
                throw GIFMakerError.couldNotRead
            }
            guard width > 0, height > 0 else { throw GIFMakerError.couldNotRead }
        }
    }

    /// One sequential read of the video track as BGRA frames. It holds at most two samples: the
    /// frame shown at the time reached, and the next.
    private struct FrameReader {
        private let reader: AVAssetReader
        private let provider: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>
        private var shown: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
        private var next: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>?
        /// Counts the source frames `shown` has been, so a repeat is known without its pixels.
        private(set) var shownNumber = 0

        /// Starts the read and takes the first frame, which every time before it shows.
        init(_ source: Source) async throws {
            do {
                reader = try AVAssetReader(asset: source.asset)
            } catch {
                RecordingLog.note("Recording: no reader for a GIF: \(error.localizedDescription)")
                throw GIFMakerError.couldNotRead
            }
            let output = AVAssetReaderTrackOutput(track: source.track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            output.alwaysCopiesSampleData = false
            provider = reader.outputProvider(for: output)
            do {
                try reader.start()
            } catch {
                RecordingLog.note("Recording: a GIF's read did not start: \(error.localizedDescription)")
                throw GIFMakerError.couldNotRead
            }
            guard let first = try await Self.read(provider, reader) else {
                RecordingLog.note("Recording: a GIF's source has no first frame")
                reader.cancelReading()
                throw GIFMakerError.couldNotRead
            }
            shown = first
            next = try await Self.read(provider, reader)
        }

        /// Moves `shown` to the latest source frame whose presentation time is at or before `time`.
        /// A cancel stops it between source frames, as the palette pass skips many between samples.
        mutating func advance(to time: CMTime) async throws {
            while let candidate = next, candidate.presentationTimeStamp <= time {
                try Task.checkCancellation()
                shown = candidate
                shownNumber += 1
                next = nil
                next = try await Self.read(provider, reader)
            }
        }

        /// Draws the shown frame over the whole canvas.
        func drawShown(into canvas: Canvas) throws {
            try shown.withUnsafeSampleBuffer { sample in
                var image: CGImage?
                guard let pixels = CMSampleBufferGetImageBuffer(sample),
                      VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image) == noErr,
                      let image else { throw GIFMakerError.couldNotRead }
                canvas.draw(image)
            }
        }

        func cancel() {
            reader.cancelReading()
        }

        /// The next sample that holds a picture, or nil at the end. A failed read throws.
        private static func read(_ provider: AVAssetReaderOutput.Provider<CMReadySampleBuffer<CMSampleBuffer.DynamicContent>>,
                                 _ reader: AVAssetReader) async throws -> CMReadySampleBuffer<CMSampleBuffer.DynamicContent>? {
            while true {
                let sample: CMReadySampleBuffer<CMSampleBuffer.DynamicContent>?
                do {
                    sample = try await provider.next()
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    RecordingLog.note("Recording: a GIF's read failed: \(error.localizedDescription)")
                    throw GIFMakerError.couldNotRead
                }
                guard let sample else {
                    if reader.status == .failed {
                        RecordingLog.note("Recording: a GIF's read failed: \(reader.error?.localizedDescription ?? "no error")")
                        throw GIFMakerError.couldNotRead
                    }
                    return nil
                }
                if case .pixelBuffer = sample.content { return sample }
            }
        }
    }

    // MARK: Scaling and progress

    /// One reused 8-bit sRGB RGBA bitmap at the output size. Frames are opaque, so drawing with
    /// `.copy` replaces every pixel.
    private final class Canvas {
        let width: Int
        let height: Int
        private let context: CGContext

        init(width: Int, height: Int) throws {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                              | CGBitmapInfo.byteOrder32Big.rawValue)
            else { throw GIFMakerError.couldNotRead }
            context.setBlendMode(.copy)
            context.interpolationQuality = .high
            self.width = width
            self.height = height
            self.context = context
        }

        func draw(_ image: CGImage) {
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        /// The bitmap's bytes, row by row from the top, 4 a pixel.
        func withPixels<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
            let start = context.data?.assumingMemoryBound(to: UInt8.self)
            return try body(UnsafeBufferPointer(start: start, count: start == nil ? 0 : width * height * 4))
        }
    }

    /// `progress` through `UploadQueue.ProgressThrottle`: never decreasing, at most 10 times a
    /// second, and a fraction of 1 once. `force` passes a phase's boundary through the throttle.
    private final class ProgressReporter {
        private let send: @Sendable (Double) -> Void
        private var throttle = UploadQueue.ProgressThrottle()
        private var last = -1.0

        init(_ send: @escaping @Sendable (Double) -> Void) {
            self.send = send
        }

        func report(_ fraction: Double, force: Bool = false) {
            let value = min(1, fraction)
            guard value > last, force || throttle.admits(value, at: .now) else { return }
            last = value
            send(value)
        }
    }
}
