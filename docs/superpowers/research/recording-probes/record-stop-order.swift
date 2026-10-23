import AppKit
import ScreenCaptureKit
import AVFoundation
setbuf(stdout, nil)
// Usage: record-stop-order <area|full|kill> <output>, or record-stop-order watch <output> [seconds]
// `watch` records the area mode's rect with audio for `seconds` (default 180), printing every
// callback and each change of the frame status, for the sleep, lock and user-switch checks.
func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) }
final class Delegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    weak var output: SCRecordingOutput?
    var finished = false
    /// The finish or the fail callback arrived.
    var ended = false
    var stopped = false
    func log(_ what: String) { print(now(), what, "recordedDuration", output?.recordedDuration.seconds ?? 0) }
    func recordingOutputDidStartRecording(_ r: SCRecordingOutput) { log("didStart") }
    func recordingOutput(_ r: SCRecordingOutput, didFailWithError error: any Error) { ended = true; log("didFail \(error)") }
    func recordingOutputDidFinishRecording(_ r: SCRecordingOutput) { finished = true; ended = true; log("didFinish") }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { stopped = true; log("stream didStop \(error)") }
    func streamDidBecomeActive(_ stream: SCStream) { log("streamDidBecomeActive") }
    func streamDidBecomeInactive(_ stream: SCStream) { log("streamDidBecomeInactive") }
    func outputVideoEffectDidStart(for stream: SCStream) { log("outputVideoEffectDidStart") }
    func outputVideoEffectDidStop(for stream: SCStream) { log("outputVideoEffectDidStop") }
}
/// Prints each change of the frames' `SCFrameStatus` (watch mode).
final class FrameWatcher: NSObject, SCStreamOutput {
    var last: SCFrameStatus?
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw), status != last else { return }
        last = status
        let names: [SCFrameStatus: String] = [.complete: "complete", .idle: "idle", .blank: "blank", .suspended: "suspended", .started: "started", .stopped: "stopped"]
        print(now(), "frame status", names[status] ?? "\(raw)")
    }
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
@MainActor func run(mode: String, url: URL, seconds: Int) async {
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
        d.output = out
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: d)
        try stream.addRecordingOutput(out)
        let watcher = FrameWatcher()
        if mode == "watch" {
            try stream.addStreamOutput(watcher, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
        }
        print(now(), "mode", mode, "size", config.width, "x", config.height, mode == "watch" ? "seconds \(seconds)" : "")
        try await stream.startCapture()
        print(now(), "startCapture returned")
        if mode == "watch" {
            // Until the time is up or the stream stops by itself; then stop if still running and
            // wait for the finish callback before reading the file.
            for _ in 0..<(seconds * 10) where !d.stopped { try await Task.sleep(for: .milliseconds(100)) }
            if !d.stopped {
                print(now(), "calling stopCapture")
                do { try await stream.stopCapture() } catch { print(now(), "stopCapture threw", error) }
            }
            for _ in 0..<150 where !d.ended { try await Task.sleep(for: .milliseconds(100)) }
            print(now(), "finished =", d.finished, ":", await describe(url))
            _ = watcher
            exit(0)
        }
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
let seconds = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 180 : 180
Task { @MainActor in await run(mode: mode, url: url, seconds: seconds) }
app.run()
