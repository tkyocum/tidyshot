import AppKit
import CoreMedia
import ScreenCaptureKit
import os

/// What the stream and its recording output report to the controller, on the main actor.
nonisolated enum RecordingStreamEvent: Equatable, Sendable {
    /// `recordingOutputDidStartRecording`: the first frame is in the file.
    case recordingStarted
    /// `recordingOutputDidFinishRecording`: the file is complete.
    case recordingFinished
    /// `recordingOutput(_:didFailWithError:)`, with the error's description.
    case outputFailed(String)
    /// `stream(_:didStopWithError:)`, with the error's description.
    case streamStopped(String)
    case streamInactive
    case streamActive
}

/// The TidyShot windows a recording must leave out (the panel and the area frame, and the Quick
/// Access cards) and the covers it keeps in, by window number.
struct RecordingExclusions: Equatable {
    var chromeWindows: Set<CGWindowID>
    var cardWindows: Set<CGWindowID>
    var coverWindows: Set<CGWindowID>
}

/// Why a stream could not start. The window and display cases are the driver's own content read,
/// after the hand-off's (design, Excluded windows; plan Gap 9).
nonisolated enum RecordingStartError: LocalizedError {
    case cannotHideOwnWindows
    case windowGone
    case displayGone

    var errorDescription: String? {
        switch self {
        case .cannotHideOwnWindows: "TidyShot could not hide its own windows."
        case .windowGone: "The window is no longer on screen."
        case .displayGone: "The display is no longer connected."
        }
    }
}

/// Records one stream to a file: `SCStream` with `SCRecordingOutput` in the app, a fake in tests.
/// One driver serves one recording: `start` once, then `stop`.
protocol RecordingStreamDriver: AnyObject {
    /// Makes the filter from fresh shareable content and starts writing `outputURL`. `events` is
    /// called on the main actor, from the start until the driver is released.
    func start(_ configuration: RecordingConfiguration, outputURL: URL, exclusions: RecordingExclusions,
               events: @escaping (RecordingStreamEvent) -> Void) async throws
    /// `stopCapture()`. The file is complete only at `recordingFinished`, which can arrive before
    /// or after this returns.
    func stop() async throws
}

/// The `Recording:` lines. They go through `Logger` as public, because `NSLog`'s text shows as
/// `<private>` in `log show`; read them with
/// `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`.
nonisolated enum RecordingLog {
    private static let logger = Logger(subsystem: "io.tky.tidyshot", category: "Recording")

    static func note(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}

/// The real driver (design, Stream and Excluded windows). Area and fullscreen recordings leave
/// out every TidyShot window, including windows opened later, except the desktop covers; a window
/// recording shows only the window.
final class ScreenRecordingDriver: RecordingStreamDriver {
    private let engine: CaptureEngine
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var delegate: RecordingStreamDelegate?
    private var events: ((RecordingStreamEvent) -> Void)?

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    func start(_ configuration: RecordingConfiguration, outputURL: URL, exclusions: RecordingExclusions,
               events: @escaping (RecordingStreamEvent) -> Void) async throws {
        self.events = events
        let content = try await engine.shareableContent()
        let filter = try await makeFilter(configuration.filter, content: content, exclusions: exclusions)

        let delegate = RecordingStreamDelegate { [weak self] event in self?.events?(event) }
        let output = SCRecordingOutput(configuration: Self.outputConfiguration(outputURL), delegate: delegate)
        delegate.output = output
        let stream = SCStream(filter: filter, configuration: Self.streamConfiguration(configuration), delegate: delegate)
        try stream.addRecordingOutput(output)
        // Held for the stream's life: the stream and the output keep their delegate weakly.
        self.delegate = delegate
        self.output = output
        RecordingLog.note("Recording: starting \(configuration.pixelWidth)×\(configuration.pixelHeight) at \(configuration.framesPerSecond) fps, \(configuration.filter)")
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        guard let stream else { return }
        try await stream.stopCapture()
    }

    /// An H.264 `.mp4`: Clop skips `.m4v`, and Clop and other receivers may not take HEVC.
    static func outputConfiguration(_ url: URL) -> SCRecordingOutputConfiguration {
        let output = SCRecordingOutputConfiguration()
        output.outputURL = url
        output.outputFileType = .mp4
        output.videoCodecType = .h264
        return output
    }

    static func streamConfiguration(_ configuration: RecordingConfiguration) -> SCStreamConfiguration {
        let stream = SCStreamConfiguration()
        stream.width = configuration.pixelWidth
        stream.height = configuration.pixelHeight
        stream.minimumFrameInterval = configuration.minimumFrameInterval
        stream.showsCursor = configuration.showsCursor
        stream.capturesAudio = configuration.capturesAudio
        stream.excludesCurrentProcessAudio = configuration.excludesCurrentProcessAudio
        stream.ignoreShadowsSingleWindow = configuration.ignoresShadowsSingleWindow
        stream.scalesToFit = configuration.scalesToFit
        stream.preservesAspectRatio = configuration.preservesAspectRatio
        if case .area(_, let sourceRect) = configuration.filter {
            stream.sourceRect = sourceRect
        }
        return stream
    }

    /// The filter from fresh shareable content. A window or display that went since the hand-off
    /// throws. The covers are found by number; one that cannot be found shows its icons, and the
    /// start goes ahead.
    private func makeFilter(_ plan: RecordingFilterPlan, content: SCShareableContent,
                            exclusions: RecordingExclusions) async throws -> SCContentFilter {
        let displayID: CGDirectDisplayID
        switch plan {
        case .window(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw RecordingStartError.windowGone
            }
            return SCContentFilter(desktopIndependentWindow: window)
        case .area(let id, _), .display(let id):
            displayID = id
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw RecordingStartError.displayGone
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        guard !own.isEmpty else {
            return try await fallbackFilter(display: display, exclusions: exclusions)
        }
        let covers = exclusions.coverWindows.isEmpty
            ? [] : await OverlayWindowLookup.windows(numbers: exclusions.coverWindows, engine: engine)
        return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: covers)
    }

    /// TidyShot is missing from the shareable applications: the chrome and the cards are left out
    /// by number, as `ScrollFrameSource` does, and the covers show anyway. The chrome must be
    /// found; a card that is not found shows.
    private func fallbackFilter(display: SCDisplay, exclusions: RecordingExclusions) async throws -> SCContentFilter {
        RecordingLog.note("Recording: TidyShot is not in the shareable applications; its windows are left out by number, so windows opened later will show")
        let found = await OverlayWindowLookup.windows(numbers: exclusions.chromeWindows.union(exclusions.cardWindows),
                                                      engine: engine)
        guard exclusions.chromeWindows.isSubset(of: Set(found.map(\.windowID))) else {
            throw RecordingStartError.cannotHideOwnWindows
        }
        return SCContentFilter(display: display, excludingWindows: found)
    }
}

/// Logs every stream and output callback where it arrives, with the output's
/// `recordedDuration`, then hands it to the main actor in the order it came.
nonisolated private final class RecordingStreamDelegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    /// Set once, before the stream starts.
    weak var output: SCRecordingOutput?
    private let send: @MainActor @Sendable (RecordingStreamEvent) -> Void

    init(send: @escaping @MainActor @Sendable (RecordingStreamEvent) -> Void) {
        self.send = send
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        report("recordingOutputDidStartRecording", .recordingStarted, recorded: recordingOutput.recordedDuration)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        report("recordingOutputDidFinishRecording", .recordingFinished, recorded: recordingOutput.recordedDuration)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        report("recordingOutput(_:didFailWithError:): \(error.localizedDescription)",
               .outputFailed(error.localizedDescription), recorded: recordingOutput.recordedDuration)
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        report("stream(_:didStopWithError:): \(error.localizedDescription)",
               .streamStopped(error.localizedDescription), recorded: output?.recordedDuration)
    }

    func streamDidBecomeInactive(_ stream: SCStream) {
        report("streamDidBecomeInactive", .streamInactive, recorded: output?.recordedDuration)
    }

    func streamDidBecomeActive(_ stream: SCStream) {
        report("streamDidBecomeActive", .streamActive, recorded: output?.recordedDuration)
    }

    private func report(_ callback: String, _ event: RecordingStreamEvent, recorded: CMTime?) {
        let seconds = recorded.map { $0.isNumeric ? $0.seconds : 0 } ?? 0
        RecordingLog.note("Recording: \(callback), recordedDuration \(String(format: "%.2f", seconds)) s")
        // The main queue keeps the callbacks in order: a start is never seen after its finish.
        let send = send
        DispatchQueue.main.async {
            MainActor.assumeIsolated { send(event) }
        }
    }
}
