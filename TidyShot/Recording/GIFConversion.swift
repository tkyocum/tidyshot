import Foundation

/// One conversion's progress, as the status menu reads it.
nonisolated struct GIFProgress: Equatable, Sendable {
    var fraction: Double
    /// The output frame count, which weighs this conversion against others.
    var frameCount: Int
}

/// The GIF step of a recording's save (design, Conversion; plan Gap 4): between the recorder's
/// `.keep` and `saveRecording`, with its parts injected so it runs in tests. Every path calls
/// `save` exactly once, so the recording leaves `recordingSavesInFlight` once: the GIF on success,
/// otherwise the MP4 as a video, in quit mode while the app quits. A recording is never lost.
struct GIFConversion {
    /// The free space of `tmp/Recording`; nil when it cannot be read.
    var freeBytes: () -> Int64?
    /// `GIFMaker.make` from the MP4 to the GIF's URL with the settings, passing progress on.
    var make: (URL, URL, GIFSettings, @escaping @Sendable (Double) -> Void) async throws -> GIFResult
    /// `saveRecording` with its notice (`GIF not made`) and mode. The record, or nil when the file
    /// stayed in `tmp/Recording`.
    var save: (Recording, RecordingNotice?, RecordingSaveMode) async -> CaptureRecord?
    var removeFile: (URL) -> Void
    var isQuitting: () -> Bool

    static let notMadeTitle = "GIF not made"
    /// `Stop Making GIF`'s reason.
    static let stoppedReason = "Stopped."

    static func notMade(_ reason: String) -> RecordingNotice {
        RecordingNotice(title: notMadeTitle, body: "\(reason) The recording was saved as an MP4.")
    }

    /// Makes the GIF from `mp4` and saves it, or saves `mp4` instead. `onProgress` runs on the main
    /// actor while `make` runs, and never after this returns.
    func run(_ mp4: Recording, settings: GIFSettings, onProgress: @escaping (GIFProgress) -> Void) async {
        // A quit before the conversion began skips it.
        if isQuitting() {
            _ = await save(mp4, nil, .quit)
            return
        }
        guard RecordingLimits.hasRoom(for: 0, freeBytes: freeBytes()) else {
            _ = await save(mp4, Self.notMade(GIFMakerError.notEnoughSpace.localizedDescription), .normal)
            return
        }

        let gifURL = Recording.gifURL(for: mp4.id)
        let frameCount = GIFMaker.outputFrameCount(duration: mp4.duration, fps: settings.fps)
        // `make` reports off the main actor; the newest fraction waits here for the main actor.
        let (fractions, reported) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let forwarding = Task {
            for await fraction in fractions {
                onProgress(GIFProgress(fraction: fraction, frameCount: frameCount))
            }
        }
        let made: Result<GIFResult, any Error>
        do {
            made = .success(try await make(mp4.fileURL, gifURL, settings) { reported.yield($0) })
        } catch {
            made = .failure(error)
        }
        reported.finish()
        await forwarding.value

        switch made {
        case .success(let result):
            let gif = Recording(id: mp4.id, fileURL: gifURL, startedAt: mp4.startedAt,
                                pixelWidth: result.pixelWidth, pixelHeight: result.pixelHeight,
                                duration: result.duration, poster: mp4.poster, displayID: mp4.displayID,
                                mediaKind: .gif, recoveryURL: mp4.fileURL)
            // Until the GIF has left `tmp/Recording` with its record, the MP4 is the recording.
            if await save(gif, nil, .normal) != nil {
                removeFile(mp4.fileURL)
            } else {
                removeFile(gifURL)
            }
        case .failure(let error):
            removeFile(gifURL)
            if isQuitting() {
                _ = await save(mp4, nil, .quit)
            } else if error is CancellationError {
                _ = await save(mp4, Self.notMade(Self.stoppedReason), .normal)
            } else {
                _ = await save(mp4, Self.notMade(error.localizedDescription), .normal)
            }
        }
    }
}
