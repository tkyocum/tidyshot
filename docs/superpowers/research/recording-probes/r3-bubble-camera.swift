// R3 probe: the webcam bubble. Opens the camera (needs camera access) and shows it in a round,
// borderless, non-activating panel that floats over other apps and fullscreen Spaces, can be
// dragged (the clamped drag TidyShot uses: mouseDown and mouseDragged move the window, kept inside its
// screen's visibleFrame), and steps Small/Medium/Large on double-click. Usage:
//   r3-bubble-camera [name-substring] [720|1080] [seconds]
// Prints: the chosen device and format; every activeFormat or frame-duration change (KVO);
// session runtime errors, interruptions, stops and device disconnects with timestamps; and every
// 5 s the frame rate, the frame age at arrival (host clock now minus the sample's presentation
// time, in ms: the capture-to-app part of the latency), and this process's CPU % from getrusage.
// Build with the same Info.plist section as r3-camera-list.swift.
import AppKit
import AVFoundation
setbuf(stdout, nil)

let args = CommandLine.arguments
let wanted = args.count > 1 ? args[1].lowercased() : ""
let preset: AVCaptureSession.Preset = (args.count > 2 && args[2] == "1080") ? .hd1920x1080 : .hd1280x720
let seconds = args.count > 3 ? Double(args[3]) ?? 60 : 60
let sizes: [CGFloat] = [120, 180, 260]   // Small, Medium, Large in points (guesses for the design)

final class BubbleView: NSView {
    var onDoubleClick: () -> Void = {}
    private var pointerStart = NSPoint.zero
    private var originStart = NSPoint.zero
    // The panel is never key and the app is not active, so the first click must count.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with e: NSEvent) {
        if e.clickCount == 2 { onDoubleClick(); return }
        guard let window else { return }
        pointerStart = NSEvent.mouseLocation
        originStart = window.frame.origin
    }
    override func mouseDragged(with e: NSEvent) {
        guard let window else { return }
        let p = NSEvent.mouseLocation
        var origin = NSPoint(x: originStart.x + p.x - pointerStart.x, y: originStart.y + p.y - pointerStart.y)
        // Keep the whole bubble inside the screen under the pointer, by its visibleFrame.
        if let area = (NSScreen.screens.first { $0.frame.contains(p) } ?? window.screen)?.visibleFrame {
            let size = window.frame.size
            origin.x = min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width))
            origin.y = min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height))
        }
        window.setFrameOrigin(origin)
    }
    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        layer?.sublayers?.forEach { $0.frame = bounds }
    }
}

final class Stats: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let lock = NSLock(); var frames = 0; var ageSum = 0.0; var ageMax = 0.0
    func captureOutput(_ o: AVCaptureOutput, didOutput b: CMSampleBuffer, from c: AVCaptureConnection) {
        let age = (CMClockGetTime(CMClockGetHostTimeClock()) - b.presentationTimeStamp).seconds * 1000
        lock.lock(); frames += 1; ageSum += age; ageMax = max(ageMax, age); lock.unlock()
    }
    func take() -> (Int, Double, Double) {
        lock.lock(); defer { frames = 0; ageSum = 0; ageMax = 0; lock.unlock() }
        return (frames, frames > 0 ? ageSum / Double(frames) : 0, ageMax)
    }
}

func cpuSeconds() -> Double {
    var u = rusage(); getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
}

@MainActor func start() {
    let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]
    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
    guard let device = devices.first(where: { wanted.isEmpty || $0.localizedName.lowercased().contains(wanted) })
            ?? AVCaptureDevice.systemPreferredCamera else { print("no camera"); exit(1) }
    print("device:", device.localizedName, device.deviceType.rawValue, "status", AVCaptureDevice.authorizationStatus(for: .video).rawValue)
    let session = AVCaptureSession()
    session.beginConfiguration()
    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { print("no input"); exit(1) }
    session.addInput(input)
    if session.canSetSessionPreset(preset) { session.sessionPreset = preset } else { print("preset not supported", preset.rawValue) }
    let stats = Stats()
    let out = AVCaptureVideoDataOutput()
    out.alwaysDiscardsLateVideoFrames = true
    out.setSampleBufferDelegate(stats, queue: DispatchQueue(label: "frames"))
    if session.canAddOutput(out) { session.addOutput(out) }
    session.commitConfiguration()

    let panel = NSPanel(contentRect: NSRect(x: 200, y: 200, width: sizes[1], height: sizes[1]),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
    panel.level = .floating   // the recording bar's level; try .statusBar and .screenSaver too
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.hidesOnDeactivate = false
    let view = BubbleView(frame: panel.contentRect(forFrameRect: panel.frame))
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    let preview = AVCaptureVideoPreviewLayer(session: session)
    preview.videoGravity = .resizeAspectFill
    if let c = preview.connection, c.isVideoMirroringSupported {
        c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = true
    }
    preview.contentsScale = panel.backingScaleFactor
    view.layer?.addSublayer(preview)
    var step = 1
    view.onDoubleClick = {
        step = (step + 1) % sizes.count
        var f = panel.frame; let c = NSPoint(x: f.midX, y: f.midY)
        f.size = NSSize(width: sizes[step], height: sizes[step]); f.origin = NSPoint(x: c.x - f.width / 2, y: c.y - f.height / 2)
        panel.setFrame(f, display: true, animate: true); print("size step", step, sizes[step])
    }
    panel.contentView = view
    panel.orderFrontRegardless()

    let nc = NotificationCenter.default
    for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification,
                 AVCaptureSession.interruptionEndedNotification, AVCaptureSession.didStopRunningNotification,
                 AVCaptureSession.didStartRunningNotification, AVCaptureDevice.wasDisconnectedNotification] {
        nc.addObserver(forName: name, object: nil, queue: .main) { n in
            print(Date(), name.rawValue, n.userInfo ?? [:], "running", session.isRunning)
        }
    }
    let k1 = device.observe(\.activeFormat, options: [.new]) { d, _ in print(Date(), "activeFormat ->", d.activeFormat.formatDescription) }
    let k2 = device.observe(\.activeVideoMinFrameDuration, options: [.new]) { d, _ in print(Date(), "minFrameDuration ->", d.activeVideoMinFrameDuration.seconds) }
    let k3 = device.observe(\.isSuspended, options: [.new]) { d, _ in print(Date(), "suspended ->", d.isSuspended) }
    let t0 = Date()
    DispatchQueue.global().async { session.startRunning(); print("startRunning took \(Int(Date().timeIntervalSince(t0) * 1000)) ms; active", device.activeFormat.formatDescription) }
    var lastCPU = cpuSeconds()
    Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
        let (n, avg, mx) = stats.take(); let cpu = cpuSeconds()
        print(String(format: "fps %.1f  frame age avg %.1f ms max %.1f ms  cpu %.1f%%", Double(n) / 5, avg, mx, (cpu - lastCPU) / 5 * 100))
        lastCPU = cpu; _ = (k1, k2, k3)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { session.stopRunning(); exit(0) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.async {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: start()
    case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { ok in DispatchQueue.main.async { if ok { start() } else { exit(2) } } }
    default: print("camera access denied or restricted"); exit(2)
    }
}
app.run()
