import AppKit
import ScreenCaptureKit
import AVFoundation
setbuf(stdout, nil)
final class PageView: NSView {
    var frameNo = 0
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.97, alpha: 1).setFill(); bounds.fill()
        let scroll = frameNo * 6
        for row in 0..<60 {
            let y = Int(bounds.height) - 100 - row * 35 + scroll % 2100
            guard y > -40 && y < Int(bounds.height) - 80 else { continue }
            NSColor(calibratedHue: CGFloat((row * 37) % 100) / 100, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
            NSRect(x: 60, y: y, width: 90, height: 24).fill()
            let text = "Row \(row): The quick brown fox jumps over the lazy dog while TidyShot records the screen \(row * 17)"
            (text as NSString).draw(at: NSPoint(x: 170, y: y + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
        }
        NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 0, y: bounds.height - 70, width: bounds.width, height: 70).fill()
        NSColor.systemBlue.setFill(); NSRect(x: 30 + CGFloat((frameNo * 5) % 1100), y: bounds.height - 50, width: 60, height: 30).fill()
    }
}
final class Delegate: NSObject, SCRecordingOutputDelegate {
    func recordingOutput(_ r: SCRecordingOutput, didFailWithError error: any Error) { print("failed", error) }
}
@MainActor func run() async {
    let window = NSWindow(contentRect: NSRect(x: 300, y: 200, width: 1280, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
    let view = PageView(frame: window.contentLayoutRect); window.contentView = view; window.title = "TidyShot recording probe"
    window.orderFrontRegardless()
    let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in MainActor.assumeIsolated { view.frameNo += 1; view.needsDisplay = true } }
    do {
        try await Task.sleep(for: .milliseconds(500))
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let sc = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { print("no window"); exit(1) }
        let config = SCStreamConfiguration()
        config.width = Int(sc.frame.width * 2); config.height = Int(sc.frame.height * 2)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = false
        let rc = SCRecordingOutputConfiguration()
        let url = URL(fileURLWithPath: CommandLine.arguments[1]); try? FileManager.default.removeItem(at: url)
        rc.outputURL = url; rc.outputFileType = .mp4; rc.videoCodecType = .h264
        let d = Delegate()
        let out = SCRecordingOutput(configuration: rc, delegate: d)
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: sc), configuration: config, delegate: nil)
        try stream.addRecordingOutput(out)
        try await stream.startCapture()
        try await Task.sleep(for: .seconds(10))
        try await stream.stopCapture()
        try await Task.sleep(for: .milliseconds(800))
        print("recorded", out.recordedDuration.seconds, "s", try FileManager.default.attributesOfItem(atPath: url.path)[.size]!, "bytes", config.width, "x", config.height)
        _ = d; timer.invalidate()
    } catch { print("error", error) }
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in await run() }
app.run()
