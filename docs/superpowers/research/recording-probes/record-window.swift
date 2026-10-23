import AppKit
import ScreenCaptureKit
import AVFoundation
setbuf(stdout, nil)
// Usage: record-window <output> [seconds] [audio] [window <id>]
// Records its own scrolling window (resizable, minimisable, closable) or another app's window by
// id, for `seconds` (default 10), with system audio when `audio` is given. Prints every stream and
// output callback, and once a second recordedDuration and whether the window is listed and on screen.
func now() -> String { String(format: "%.3f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000)) }
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
final class Delegate: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    weak var output: SCRecordingOutput?
    var finished = false
    /// The finish or the fail callback arrived.
    var ended = false
    var stopped = false
    func log(_ what: String) { print(now(), what, "recordedDuration", output?.recordedDuration.seconds ?? 0) }
    func recordingOutputDidStartRecording(_ r: SCRecordingOutput) { log("recordingOutputDidStartRecording") }
    func recordingOutputDidFinishRecording(_ r: SCRecordingOutput) { finished = true; ended = true; log("recordingOutputDidFinishRecording") }
    func recordingOutput(_ r: SCRecordingOutput, didFailWithError error: any Error) { ended = true; log("recordingOutput didFailWithError \(error)") }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { stopped = true; log("stream didStopWithError \(error)") }
    func streamDidBecomeActive(_ stream: SCStream) { log("streamDidBecomeActive") }
    func streamDidBecomeInactive(_ stream: SCStream) { log("streamDidBecomeInactive") }
    func outputVideoEffectDidStart(for stream: SCStream) { log("outputVideoEffectDidStart") }
    func outputVideoEffectDidStop(for stream: SCStream) { log("outputVideoEffectDidStop") }
}
/// Whether the window server still lists the window, and its kCGWindowIsOnscreen.
func windowState(_ id: CGWindowID) -> String {
    let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]] ?? []
    guard let window = info.first(where: { ($0[kCGWindowNumber as String] as? Int).map(CGWindowID.init) == id }) else { return "listed=false" }
    return "listed=true onscreen=\(window[kCGWindowIsOnscreen as String] as? Bool ?? false)"
}
/// The backing scale of the display under the window's centre.
func scale(for frame: CGRect) -> CGFloat {
    var display: CGDirectDisplayID = 0; var count: UInt32 = 0
    CGGetDisplaysWithPoint(CGPoint(x: frame.midX, y: frame.midY), 1, &display, &count)
    let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display }
    return screen?.backingScaleFactor ?? 2
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
@MainActor func run(url: URL, seconds: Int, audio: Bool, windowID: CGWindowID?) async {
    var timer: Timer?
    var ownWindow: NSWindow?
    if windowID == nil {
        let window = NSWindow(contentRect: NSRect(x: 300, y: 200, width: 1280, height: 800),
                              styleMask: [.titled, .resizable, .miniaturizable, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = PageView(frame: window.contentLayoutRect); window.contentView = view; window.title = "TidyShot recording probe"
        window.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in MainActor.assumeIsolated { view.frameNo += 1; view.needsDisplay = true } }
        ownWindow = window
    }
    do {
        try await Task.sleep(for: .milliseconds(500))
        let id = windowID ?? CGWindowID(ownWindow!.windowNumber)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let sc = content.windows.first(where: { $0.windowID == id }) else { print("no window", id); exit(1) }
        let config = SCStreamConfiguration()
        let pointScale = scale(for: sc.frame)
        config.width = Int(sc.frame.width * pointScale) / 2 * 2; config.height = Int(sc.frame.height * pointScale) / 2 * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = true
        config.preservesAspectRatio = true
        config.capturesAudio = audio
        config.excludesCurrentProcessAudio = true
        let rc = SCRecordingOutputConfiguration()
        try? FileManager.default.removeItem(at: url)
        rc.outputURL = url; rc.outputFileType = .mp4; rc.videoCodecType = .h264
        let d = Delegate()
        let out = SCRecordingOutput(configuration: rc, delegate: d)
        d.output = out
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: sc), configuration: config, delegate: d)
        try stream.addRecordingOutput(out)
        print(now(), "window", id, "owner", sc.owningApplication?.applicationName ?? "?", "size", config.width, "x", config.height, "audio", audio, "seconds", seconds)
        try await stream.startCapture()
        print(now(), "startCapture returned")
        for _ in 0..<seconds {
            try await Task.sleep(for: .seconds(1))
            print(now(), "tick recordedDuration", out.recordedDuration.seconds, windowState(id))
            if d.stopped { break }
        }
        if !d.stopped {
            print(now(), "calling stopCapture")
            do { try await stream.stopCapture() } catch { print(now(), "stopCapture threw", error) }
        }
        for _ in 0..<150 where !d.ended { try await Task.sleep(for: .milliseconds(100)) }
        print(now(), "finished =", d.finished, ":", await describe(url))
    } catch { print(now(), "error", error) }
    timer?.invalidate()
    exit(0)
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
var arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else { print("usage: record-window <output> [seconds] [audio] [window <id>]"); exit(2) }
let url = URL(fileURLWithPath: arguments.removeFirst())
var seconds = 10, audio = false, windowID: CGWindowID?
while !arguments.isEmpty {
    let word = arguments.removeFirst()
    if word == "audio" { audio = true }
    else if word == "window", let id = arguments.first.flatMap({ UInt32($0) }) { arguments.removeFirst(); windowID = id }
    else if let value = Int(word) { seconds = value }
    else { print("unknown argument", word); exit(2) }
}
Task { @MainActor in await run(url: url, seconds: seconds, audio: audio, windowID: windowID) }
app.run()
