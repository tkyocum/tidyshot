// R3 probe: does an excepted window of an excluded app (TidyShot's own) show in a display stream,
// and does the exception follow the window when it moves, resizes, is ordered out and back in, or
// is created after the start? Records the screen (SCStream frames, no file). Needs Screen Recording.
// Usage: r3-bubble-filter [seconds]   Prints one line per check: what the pixel at each spot shows.
import AppKit
import ScreenCaptureKit
setbuf(stdout, nil)

func panel(_ rect: NSRect, _ color: NSColor) -> NSPanel {
    let p = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.backgroundColor = color; p.level = .floating; p.isOpaque = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.orderFrontRegardless(); return p
}

final class Sampler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var last: CVPixelBuffer?
    let lock = NSLock()
    func stream(_ s: SCStream, didOutputSampleBuffer b: CMSampleBuffer, of t: SCStreamOutputType) {
        guard t == .screen, let px = b.imageBuffer else { return }
        lock.lock(); last = px; lock.unlock()
    }
    func stream(_ s: SCStream, didStopWithError e: any Error) { print("stream stopped", e) }
    // BGRA at a point in display-local points (scale 1 stream).
    func colour(at p: CGPoint) -> String {
        lock.lock(); defer { lock.unlock() }
        guard let px = last else { return "no frame" }
        CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let x = Int(p.x), y = Int(p.y), row = CVPixelBufferGetBytesPerRow(px)
        guard x >= 0, y >= 0, x < CVPixelBufferGetWidth(px), y < CVPixelBufferGetHeight(px) else { return "off frame" }
        let b = CVPixelBufferGetBaseAddress(px)!.assumingMemoryBound(to: UInt8.self) + y * row + x * 4
        return "r\(b[2]) g\(b[1]) b\(b[0])"
    }
}

@MainActor func run() async throws {
    let screen = NSScreen.main!
    let h = screen.frame.height
    func topLeft(_ r: NSRect) -> CGPoint { CGPoint(x: r.midX, y: h - r.midY) }   // AppKit to display-local
    let bubble = panel(NSRect(x: 300, y: 300, width: 200, height: 200), .systemRed)     // excepted
    let decoy = panel(NSRect(x: 600, y: 300, width: 200, height: 200), .systemGreen)    // excluded
    try await Task.sleep(for: .milliseconds(300))
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    let own = content.applications.filter { $0.processID == getpid() }
    let display = content.displays.first { $0.displayID == (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID) }!
    let sc = content.windows.first { $0.windowID == CGWindowID(bubble.windowNumber) }
    print("own apps \(own.count), bubble in shareable content: \(sc != nil)")
    let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: sc.map { [$0] } ?? [])
    print("filter includedWindows \(filter.includedWindows.map(\.windowID)), bubble \(bubble.windowNumber), decoy \(decoy.windowNumber)")
    let cfg = SCStreamConfiguration()
    cfg.width = Int(display.width); cfg.height = Int(display.height)
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30); cfg.showsCursor = false
    let s = Sampler()
    let stream = SCStream(filter: filter, configuration: cfg, delegate: s)
    try stream.addStreamOutput(s, type: .screen, sampleHandlerQueue: .global())
    try await stream.startCapture()
    func check(_ label: String) async throws {
        try await Task.sleep(for: .milliseconds(500))
        print(label, "bubble spot:", s.colour(at: topLeft(bubble.frame)), "| decoy spot:", s.colour(at: topLeft(decoy.frame)))
    }
    try await check("start (expect bubble red, decoy not green)")
    bubble.setFrame(NSRect(x: 900, y: 500, width: 200, height: 200), display: true); try await check("moved")
    bubble.setFrame(NSRect(x: 900, y: 500, width: 320, height: 320), display: true); try await check("resized")
    bubble.orderOut(nil); try await check("ordered out")
    bubble.orderFrontRegardless(); try await check("ordered back in (same window number \(bubble.windowNumber))")
    let late = panel(NSRect(x: 300, y: 600, width: 150, height: 150), .systemBlue)
    try await Task.sleep(for: .milliseconds(500))
    print("late panel spot:", s.colour(at: topLeft(late.frame)), "(expect hidden before update)")
    let c2 = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    let ex = c2.windows.filter { [bubble.windowNumber, late.windowNumber].contains(Int($0.windowID)) }
    let t0 = Date()
    try await stream.updateContentFilter(SCContentFilter(display: display, excludingApplications: own, exceptingWindows: ex))
    print("updateContentFilter took \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
    try await Task.sleep(for: .milliseconds(500))
    print("late panel after update:", s.colour(at: topLeft(late.frame)))
    try await stream.stopCapture()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in do { try await run() } catch { print("error", error); exit(1) } }
app.run()
