import AppKit
import ScreenCaptureKit
import AVFoundation
setbuf(stdout, nil)
func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) }
final class Delegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    var finished = false
    func recordingOutputDidStartRecording(_ r: SCRecordingOutput) { print(now(), "didStart") }
    func recordingOutput(_ r: SCRecordingOutput, didFailWithError error: any Error) { print(now(), "didFail", error) }
    func recordingOutputDidFinishRecording(_ r: SCRecordingOutput) { finished = true; print(now(), "didFinish") }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { print(now(), "stream didStop", error) }
}
func describe(_ url: URL) async -> String {
    let asset = AVURLAsset(url: url)
    do {
        let d = try await asset.load(.duration).seconds
        let tracks = try await asset.load(.tracks)
        var s = String(format: "%.2fs", d)
        for t in tracks { if t.mediaType == .video { let n = try await t.load(.naturalSize); s += " video \(Int(n.width))x\(Int(n.height))" } else { s += " \(t.mediaType.rawValue)" } }
        return s + " \((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0) bytes"
    } catch { return "unreadable: \(error.localizedDescription)" }
}
@MainActor func run(mode: String, url: URL) async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = content.displays.first!
        let config = SCStreamConfiguration()
        if mode == "full" { config.width = display.width * 2; config.height = display.height * 2 }
        else { config.sourceRect = CGRect(x: 100, y: 100, width: 600, height: 400); config.width = 1200; config.height = 800 }
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.capturesAudio = true
        let rc = SCRecordingOutputConfiguration()
        try? FileManager.default.removeItem(at: url)
        rc.outputURL = url; rc.outputFileType = .mp4; rc.videoCodecType = .h264
        let d = Delegate()
        let out = SCRecordingOutput(configuration: rc, delegate: d)
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: d)
        try stream.addRecordingOutput(out)
        print(now(), "mode", mode, "size", config.width, "x", config.height)
        try await stream.startCapture()
        print(now(), "startCapture returned")
        if mode == "kill" { try await Task.sleep(for: .seconds(5)); print(now(), "killing"); kill(getpid(), SIGKILL) }
        try await Task.sleep(for: .seconds(mode == "full" ? 4 : 3))
        print(now(), "calling stopCapture")
        try await stream.stopCapture()
        print(now(), "stopCapture returned; finished =", d.finished, "recordedDuration", out.recordedDuration.seconds)
        print(now(), "asset right after stop:", await describe(url))
        for _ in 0..<30 where !d.finished { try await Task.sleep(for: .milliseconds(100)) }
        print(now(), "after waiting, finished =", d.finished, ":", await describe(url))
    } catch { print(now(), "error", error) }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let mode = CommandLine.arguments[1]; let url = URL(fileURLWithPath: CommandLine.arguments[2])
Task { @MainActor in await run(mode: mode, url: url) }
app.run()
