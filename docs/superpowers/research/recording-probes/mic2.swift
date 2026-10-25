import AppKit
import ScreenCaptureKit
import AVFoundation
setbuf(stdout, nil)
func now() -> String { String(format: "%.2f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 100)) }
final class D: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    var finished = false
    func recordingOutput(_ r: SCRecordingOutput, didFailWithError error: any Error) { print(now(), "output failed", error) }
    func recordingOutputDidFinishRecording(_ r: SCRecordingOutput) { finished = true; print(now(), "finished") }
    func stream(_ s: SCStream, didStopWithError error: any Error) { print(now(), "stream stopped", error) }
}
@MainActor func run() async {
    print("mic auth before:", AVCaptureDevice.authorizationStatus(for: .audio).rawValue)
    let granted = await AVCaptureDevice.requestAccess(for: .audio)
    print("mic granted:", granted)
    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    print("mics:", devices.map { "\($0.localizedName) [\($0.uniqueID)]" })
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = content.displays.first!
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 100, y: 100, width: 400, height: 300); config.width = 800; config.height = 600
        config.capturesAudio = CommandLine.arguments[2] == "both"
        config.captureMicrophone = true
        if let id = AVCaptureDevice.default(for: .audio)?.uniqueID { config.microphoneCaptureDeviceID = id }
        let rc = SCRecordingOutputConfiguration()
        let url = URL(fileURLWithPath: CommandLine.arguments[1]); try? FileManager.default.removeItem(at: url)
        rc.outputURL = url; rc.outputFileType = .mp4; rc.videoCodecType = .h264
        let d = D()
        let out = SCRecordingOutput(configuration: rc, delegate: d)
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: d)
        try stream.addRecordingOutput(out)
        try await stream.startCapture(); print(now(), "started")
        try await Task.sleep(for: .seconds(4))
        try await stream.stopCapture()
        for _ in 0..<50 where !d.finished { try await Task.sleep(for: .milliseconds(100)) }
        let a = AVURLAsset(url: url)
        let dur = try await a.load(.duration).seconds
        var desc: [String] = []
        for t in try await a.load(.tracks) {
            let f = try await t.load(.formatDescriptions)
            let ch = f.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
            let range = try await t.load(.timeRange)
            desc.append("\(t.mediaType.rawValue)\(ch.map { " \($0)ch" } ?? "") \(String(format: "%.2f-%.2f", range.start.seconds, range.end.seconds))")
        }
        print("file", String(format: "%.2fs", dur), desc)
        _ = d
    } catch { print("error", error) }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
