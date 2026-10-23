#if DEBUG
import AppKit
import CoreMedia
import ScreenCaptureKit
import Synchronization
import os

/// The R1 sandbox spike: records 3 s of an 800×500 pt area centred on the main display, with
/// system audio, to `tmp/Recording` from inside the sandboxed app, then logs what the file holds.
/// Launch the Debug build with `-RecordingSpike YES`. Debug builds only.
///
/// Lines go through `Logger` as public, because `NSLog`'s text shows as `<private>` in
/// `log show`. Read them with
/// `/usr/bin/log show --last 2m --style compact --predicate 'process == "TidyShot"' | grep "Recording spike"`.
enum RecordingSpike {
    private enum SpikeError: LocalizedError {
        case noMainDisplay

        var errorDescription: String? { "The main display is not in the shareable content." }
    }

    static func run() async {
        // Asking for permission would show the system prompt; the spike only reports.
        guard ScreenCapturePermission.isGranted else {
            report("Recording spike: this build has no Screen Recording permission, nothing recorded")
            return
        }
        let url = Recording.fileURL(for: UUID())
        let line: String
        do {
            line = try await record(to: url)
        } catch {
            line = "Recording spike: \(error.localizedDescription) (\(error))"
        }
        report(line)
        keepAside(url)
    }

    private static func record(to url: URL) async throws -> String {
        try Recording.makeDirectory()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw SpikeError.noMainDisplay
        }
        let scale = CaptureEngine.scale(forDisplayID: displayID)
        let area = CGSize(width: 800, height: 500)

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: ((display.frame.width - area.width) / 2).rounded(),
                                          y: ((display.frame.height - area.height) / 2).rounded(),
                                          width: area.width, height: area.height)
        configuration.width = Int(area.width * scale)
        configuration.height = Int(area.height * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true

        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = url
        outputConfiguration.outputFileType = .mp4
        outputConfiguration.videoCodecType = .h264

        let delegate = SpikeDelegate()
        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: delegate)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: delegate)
        try stream.addRecordingOutput(output)
        note("Recording spike event: starting \(configuration.width)×\(configuration.height) at \(configuration.sourceRect) on display \(displayID), scale \(scale)")
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(3))

        // The delegate latches the first end callback from the start, and the waiter is armed
        // before the stop, so a finish that arrives before `stopCapture()` returns is not missed.
        let waiter = Task { await delegate.waitForEnd(timeout: RecordingLimits.stopTimeout) }
        do {
            try await stream.stopCapture()
        } catch {
            note("Recording spike event: stopCapture threw \(error.localizedDescription)")
        }
        let end = await waiter.value ?? "the 15 s timeout"
        note("Recording spike event: the wait ended with \(end), recordedDuration \(output.recordedDuration.seconds) s")

        let facts = await VideoValidation.inspect(url)
        let size = facts.naturalSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? "no size"
        return "Recording spike: \(url.path(percentEncoded: false)), \(size), vide×\(facts.videoTracks) soun×\(facts.audioTracks), "
            + String(format: "%.2f s, ", facts.duration) + "\(facts.byteCount) bytes"
    }

    private static func report(_ line: String) {
        note(line)
        Notifier().notify(title: "Recording spike", body: line)
    }

    /// Moves the file to `tmp/RecordingSpike`, so the launch check never adopts it.
    private static func keepAside(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "RecordingSpike", directoryHint: .isDirectory)
        let destination = folder.appending(path: url.lastPathComponent, directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: destination)
            note("Recording spike event: moved to \(destination.path(percentEncoded: false))")
        } catch {
            note("Recording spike event: the file stays in tmp/Recording: \(error.localizedDescription)")
        }
    }
}

nonisolated private let spikeLog = Logger(subsystem: "io.tky.tidyshot", category: "RecordingSpike")

nonisolated private func note(_ message: String) {
    spikeLog.notice("\(message, privacy: .public)")
}

/// Logs every stream and output callback, and remembers the first that ends the recording.
nonisolated private final class SpikeDelegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, Sendable {
    private let end = Mutex<String?>(nil)

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        note("Recording spike event: recordingOutputDidStartRecording")
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        ended("recordingOutputDidFinishRecording")
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        ended("recordingOutput didFailWithError: \(error.localizedDescription)")
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        ended("stream didStopWithError: \(error.localizedDescription)")
    }

    private func ended(_ callback: String) {
        note("Recording spike event: \(callback)")
        end.withLock { if $0 == nil { $0 = callback } }
    }

    /// The first end callback, or nil after `timeout`.
    func waitForEnd(timeout: Duration) async -> String? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let callback = end.withLock({ $0 }) { return callback }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return end.withLock { $0 }
    }
}
#endif
