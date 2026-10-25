import AppKit
import ScreenCaptureKit
import AVFoundation
setbuf(stdout, nil)

// Measures the offset between the main-actor time of the start callback (as RecordingController
// reads it: after a DispatchQueue.main.async hop) and the file's timeline, using a visual flash
// and a system-audio tone fired at known main-actor times.
final class D: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    nonisolated(unsafe) var finished = false
    nonisolated(unsafe) var cbTime = 0.0
    nonisolated(unsafe) var hopTime = 0.0
    nonisolated(unsafe) var startedFlag = false
    func recordingOutputDidStartRecording(_ r: SCRecordingOutput) {
        cbTime = CACurrentMediaTime()
        print(String(format: "cb thread time %.4f", cbTime))
        DispatchQueue.main.async { [self] in hopTime = CACurrentMediaTime(); startedFlag = true; print(String(format: "main hop time %.4f (+%.1f ms)", hopTime, (hopTime - cbTime) * 1000)) }
    }
    func recordingOutputDidFinishRecording(_ r: SCRecordingOutput) { finished = true }
    func recordingOutput(_ r: SCRecordingOutput, didFailWithError error: any Error) { print("output failed", error) }
    func stream(_ s: SCStream, didStopWithError error: any Error) { print("stream stopped", error) }
}

func toneWav(url: URL) {
    // 1 kHz, 50 ms, with 2 ms ramps, 48 kHz mono 16-bit
    let sr = 48000, n = sr / 20
    var data = Data()
    func le32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func le16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append("RIFF".data(using: .ascii)!); le32(UInt32(36 + n * 2)); data.append("WAVEfmt ".data(using: .ascii)!)
    le32(16); le16(1); le16(1); le32(UInt32(sr)); le32(UInt32(sr * 2)); le16(2); le16(16)
    data.append("data".data(using: .ascii)!); le32(UInt32(n * 2))
    for i in 0..<n {
        let ramp = min(1.0, Double(i) / 96.0, Double(n - i) / 96.0)
        let v = Int16(sin(2 * .pi * 1000 * Double(i) / Double(sr)) * 20000 * ramp)
        le16(UInt16(bitPattern: v))
    }
    try! data.write(to: url)
}

@MainActor func run() async {
    let outPath = CommandLine.arguments[1]
    let screen = NSScreen.main!
    let sh = screen.frame.height
    let win = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
    win.level = .floating; win.ignoresMouseEvents = true; win.backgroundColor = .black; win.hasShadow = false
    win.orderFrontRegardless()
    try? await Task.sleep(for: .milliseconds(300))
    let wav = URL(fileURLWithPath: outPath + ".tone.wav"); toneWav(url: wav)
    let players = (0..<4).map { _ in try! AVAudioPlayer(contentsOf: wav) }
    players.forEach { $0.prepareToPlay() }
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first!
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: 200, y: sh - 200 - 300, width: 300, height: 300); config.width = 300; config.height = 300
        config.capturesAudio = true
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        let rc = SCRecordingOutputConfiguration()
        let url = URL(fileURLWithPath: outPath); try? FileManager.default.removeItem(at: url)
        rc.outputURL = url; rc.outputFileType = .mp4; rc.videoCodecType = .h264
        let d = D()
        let out = SCRecordingOutput(configuration: rc, delegate: d)
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: d)
        try stream.addRecordingOutput(out)
        let t0 = CACurrentMediaTime()
        try await stream.startCapture()
        let t1 = CACurrentMediaTime()
        print(String(format: "startCapture call %.4f returned %.4f (%.1f ms)", t0, t1, (t1 - t0) * 1000))
        // wait for the start callback's main hop
        while !d.startedFlag { try await Task.sleep(for: .milliseconds(5)) }
        print(String(format: "cb thread time relative to startCapture return: %+.1f ms", (d.cbTime - t1) * 1000))
        var calls: [Double] = []
        for i in 0..<4 {
            // fire at hop + (i+1) s
            let target = d.hopTime + Double(i + 1)
            while CACurrentMediaTime() < target - 0.003 { try await Task.sleep(for: .milliseconds(1)) }
            while CACurrentMediaTime() < target {}
            let tc = CACurrentMediaTime()
            win.backgroundColor = (i % 2 == 0) ? .white : .black
            win.displayIfNeeded(); CATransaction.flush()
            players[i].play()
            calls.append(tc)
            print(String(format: "event %d at %.4f s after the main hop", i, tc - d.hopTime))
        }
        try await Task.sleep(for: .milliseconds(800))
        let ts = CACurrentMediaTime()
        try await stream.stopCapture()
        print(String(format: "stopCapture %.1f ms; sleep-end to stop request: ", (CACurrentMediaTime() - ts) * 1000))
        for _ in 0..<80 where !d.finished { try await Task.sleep(for: .milliseconds(100)) }
        print("calls (s after hop):", calls.map { String(format: "%.4f", $0 - d.hopTime) }.joined(separator: " "))
    } catch { print("error", error) }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
