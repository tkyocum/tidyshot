import AppKit
import ScreenCaptureKit
import AVFoundation
setbuf(stdout, nil)

final class Delegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { print("delegate: started") }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { print("delegate: failed", error) }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { print("delegate: finished") }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { print("stream stopped", error) }
}

@MainActor func run() async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = content.displays.first!
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 200, y: 200, width: 800, height: 500)
        config.width = 1600; config.height = 1000
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.capturesAudio = true
        let rc = SCRecordingOutputConfiguration()
        let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "out.mp4")
        try? FileManager.default.removeItem(at: url)
        rc.outputURL = url
        print("codecs", rc.availableVideoCodecTypes.map(\.rawValue), "types", rc.availableOutputFileTypes.map(\.rawValue))
        rc.outputFileType = .mp4
        rc.videoCodecType = .h264
        let d = Delegate()
        let out = SCRecordingOutput(configuration: rc, delegate: d)
        let stream = SCStream(filter: filter, configuration: config, delegate: d)
        try stream.addRecordingOutput(out)
        let t0 = Date()
        try await stream.startCapture()
        print("capture started after", Date().timeIntervalSince(t0))
        try await Task.sleep(for: .seconds(4))
        try await stream.stopCapture()
        print("stopped; recordedDuration", out.recordedDuration.seconds, "recordedFileSize", out.recordedFileSize)
        try await Task.sleep(for: .seconds(1))
        let asset = AVURLAsset(url: url)
        let dur = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] ?? 0
        print("file duration", dur.seconds, "tracks", tracks.map(\.mediaType.rawValue), "bytes", size)
        _ = d
    } catch { print("error", error) }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
