// r3-clicks.swift: R3 click-highlight probes. Results go in .superpowers/sdd/r3/research-clicks.md.
// Build: xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/r3-clicks r3-clicks.swift
//
// Modes that do not record:
//   monitor [seconds]   prints every mouse down, up and drag the global monitor sees, with its
//                       Cocoa point, its CG point, the screen under it and the frontmost app.
//   ring [seconds]      the same, plus a click-through overlay on every screen that draws
//                       TidyShot-style rings: yellow for left, blue for right (and control-click),
//                       held while the button is down and moved with a drag.
//   tap [seconds]       a listen-only CGEventTap for the same mouse events. It can show an Input
//                       Monitoring prompt; only run it if Tim wants that answer.
// Modes that RECORD the screen (need Screen Recording; never run by an agent):
//   builtin <out.mp4> [seconds] [window <id>]  records the main display, or one window, with
//                       SCStreamConfiguration.showMouseClicks on; turns it off at half time and on
//                       again at three quarters through updateConfiguration.
//   record-ring <out.mp4> [seconds]            records the main display with the probe's own
//                       windows left out except the ring overlay (excludingApplications +
//                       exceptingWindows, as TidyShot lets the desktop covers through).
import AppKit
import ApplicationServices
import AVFoundation
import ScreenCaptureKit

setvbuf(stdout, nil, _IOLBF, 0)
let started = Date()
func log(_ text: String) { print(String(format: "%7.3f ", Date().timeIntervalSince(started)) + text) }

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "monitor"
let recording = mode == "builtin" || mode == "record-ring"
let seconds = Double(args.dropFirst(recording ? 2 : 1).first ?? "") ?? (recording ? 12 : 30)

func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
}

/// Cocoa screen point (origin at the primary screen's bottom-left) to CG global (top-left).
func cgPoint(_ point: NSPoint) -> CGPoint {
    CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
}

let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                        .rightMouseDown, .rightMouseUp, .rightMouseDragged]

func describe(_ event: NSEvent, from source: String) -> String {
    let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
    let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    let tapPoint = event.cgEvent?.location ?? .zero
    let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
    let delay = (ProcessInfo.processInfo.systemUptime - event.timestamp) * 1000
    return "\(source) \(event.type.rawValue) delay \(String(format: "%.1f", delay)) ms clicks \(event.clickCount) ctrl \(event.modifierFlags.contains(.control)) "
        + "cocoa \(point) cg \(cgPoint(point)) cgEvent \(tapPoint) display \(screen.map(displayID) ?? 0) front \(app)"
}

final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The ring a TidyShot design would draw: grows in 0.15 s, holds while the button is down,
/// follows a drag, then grows a little more and fades over 0.35 s.
final class Rings {
    static let diameter: CGFloat = 40
    static let grow: CFTimeInterval = 0.15
    static let fade: CFTimeInterval = 0.35
    private(set) var windows: [(screen: NSScreen, window: OverlayWindow)] = []
    private var held: [Bool: (layer: CALayer, born: CFTimeInterval)] = [:] // key: isRight

    init() {
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            window.orderFrontRegardless()
            windows.append((screen, window))
            log("overlay \(window.windowNumber) on display \(displayID(screen)) frame \(screen.frame) scale \(screen.backingScaleFactor)")
        }
    }

    func handle(_ event: NSEvent) {
        let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            let isRight = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
            guard let (screen, window) = windows.first(where: { NSMouseInRect(point, $0.screen.frame, false) }),
                  let host = window.contentView?.layer else { return }
            let layer = ring(isRight: isRight, scale: screen.backingScaleFactor)
            move(layer, to: point, on: screen)
            host.addSublayer(layer)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.5
            grow.toValue = 1
            grow.duration = Self.grow
            layer.add(grow, forKey: "grow")
            held[isRight] = (layer, CACurrentMediaTime())
        case .leftMouseDragged, .rightMouseDragged:
            let isRight = event.type == .rightMouseDragged || held[false] == nil
            guard let (layer, _) = held[isRight],
                  let screen = windows.first(where: { $0.window.contentView?.layer === layer.superlayer })?.screen else { return }
            move(layer, to: point, on: screen)
        case .leftMouseUp, .rightMouseUp:
            let isRight = event.type == .rightMouseUp || held[false] == nil
            guard let (layer, born) = held.removeValue(forKey: isRight) else { return }
            let delay = max(0, born + Self.grow - CACurrentMediaTime())
            let fade = CAAnimationGroup()
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1
            opacity.toValue = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1
            scale.toValue = 1.3
            fade.animations = [opacity, scale]
            fade.duration = Self.fade
            fade.beginTime = CACurrentMediaTime() + delay
            fade.fillMode = .both
            fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "fade")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.fade + 0.05) { layer.removeFromSuperlayer() }
        default:
            break
        }
    }

    private func move(_ layer: CALayer, to point: NSPoint, on screen: NSScreen) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = CGPoint(x: point.x - screen.frame.minX, y: point.y - screen.frame.minY)
        CATransaction.commit()
    }

    /// An opaque coloured stroke over a darker, wider one, so it reads on light and dark content
    /// and survives a 256-colour palette; a faint fill of the same colour.
    private func ring(isRight: Bool, scale: CGFloat) -> CALayer {
        let colour = isRight ? NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)
                             : NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
        let bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
        let path = CGPath(ellipseIn: bounds.insetBy(dx: 4, dy: 4), transform: nil)
        let container = CALayer()
        container.bounds = bounds
        container.contentsScale = scale
        for (width, stroke, fill) in [(6.0, NSColor.black.withAlphaComponent(0.6).cgColor, colour.withAlphaComponent(0.2).cgColor),
                                      (3.5, colour.cgColor, NSColor.clear.cgColor)] {
            let shape = CAShapeLayer()
            shape.frame = bounds
            shape.path = path
            shape.lineWidth = width
            shape.strokeColor = stroke
            shape.fillColor = fill
            shape.contentsScale = scale
            container.addSublayer(shape)
        }
        return container
    }
}

final class Recorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    private var stream: SCStream?
    private var finished = false

    @MainActor func run(to url: URL, builtin: Bool, windowID: CGWindowID?, rings: Rings?) async throws {
        try? FileManager.default.removeItem(at: url)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            log("no main display"); exit(1)
        }
        let filter: SCContentFilter
        if let windowID {
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                log("window \(windowID) not found"); exit(1)
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            let pid = ProcessInfo.processInfo.processIdentifier
            let own = content.applications.filter { $0.processID == pid }
            let numbers = Set((rings?.windows ?? []).map { CGWindowID($0.window.windowNumber) })
            let excepted = content.windows.filter { numbers.contains($0.windowID) }
            log("own applications \(own.count); overlay windows in shareable content \(excepted.count) of \(numbers.count)")
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: excepted)
        }
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        var width = Int(filter.contentRect.width * scale), height = Int(filter.contentRect.height * scale)
        let longer = max(width, height)
        if longer > 4096 { width = width * 4096 / longer; height = height * 4096 / longer }
        config.width = width - width % 2
        config.height = height - height % 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.showMouseClicks = builtin
        let format = config.pixelFormat
        let fourCC = String(bytes: [24, 16, 8, 0].map { UInt8((format >> $0) & 0xFF) }, encoding: .ascii) ?? "?"
        log("stream \(config.width)×\(config.height), pixelFormat \(fourCC), showMouseClicks \(config.showMouseClicks)")

        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .h264
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream
        try await stream.startCapture()
        log("started; click, right-click, control-click and drag now")

        if builtin {
            try await Task.sleep(for: .seconds(seconds * 0.5))
            config.showMouseClicks = false
            do { try await stream.updateConfiguration(config); log("showMouseClicks off") }
            catch { log("updateConfiguration off failed: \(error.localizedDescription)") }
            try await Task.sleep(for: .seconds(seconds * 0.25))
            config.showMouseClicks = true
            do { try await stream.updateConfiguration(config); log("showMouseClicks on") }
            catch { log("updateConfiguration on failed: \(error.localizedDescription)") }
            try await Task.sleep(for: .seconds(seconds * 0.25))
        } else {
            try await Task.sleep(for: .seconds(seconds))
        }
        try await stream.stopCapture()
        log("stopCapture returned")
        for _ in 0..<150 where !finished { try await Task.sleep(for: .milliseconds(100)) }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let size = try await tracks.first?.load(.naturalSize) ?? .zero
        log("file \(url.path): \(String(format: "%.2f", duration.seconds)) s, \(size)")
        exit(0)
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) { log("recordingOutputDidStartRecording") }
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { log("recordingOutputDidFinishRecording"); finished = true }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        log("recordingOutput failed: \(error.localizedDescription)"); finished = true
    }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { log("stream stopped: \(error.localizedDescription)") }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
log("AXIsProcessTrusted \(AXIsProcessTrusted()), CGPreflightListenEventAccess \(CGPreflightListenEventAccess())")
for screen in NSScreen.screens {
    log("screen \(displayID(screen)) cocoa \(screen.frame) cg \(CGDisplayBounds(displayID(screen))) scale \(screen.backingScaleFactor)")
}

var rings: Rings?
var monitors: [Any] = []
var tapPort: CFMachPort?
let recorder = Recorder()

switch mode {
case "monitor", "ring", "record-ring":
    if mode != "monitor" { rings = Rings() }
    if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { event in
        log(describe(event, from: "global"))
        rings?.handle(event)
    }) { monitors.append(global) } else { log("addGlobalMonitorForEvents returned nil") }
case "tap":
    let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    tapPort = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                eventsOfInterest: mask, callback: { _, type, event, _ in
        log("tap \(type.rawValue) cg \(event.location)")
        return Unmanaged.passUnretained(event)
    }, userInfo: nil)
    if let tapPort {
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tapPort, 0), .commonModes)
        CGEvent.tapEnable(tap: tapPort, enable: true)
        log("listen-only tap created")
    } else {
        log("CGEvent.tapCreate returned nil")
    }
case "builtin":
    break
default:
    log("unknown mode \(mode)"); exit(2)
}

if recording {
    guard args.count > 1 else { log("needs an output path"); exit(2) }
    let url = URL(fileURLWithPath: args[1])
    let windowID = args.firstIndex(of: "window").flatMap { args.indices.contains($0 + 1) ? CGWindowID(args[$0 + 1]) : nil }
    Task { @MainActor in
        do { try await recorder.run(to: url, builtin: mode == "builtin", windowID: windowID, rings: rings) }
        catch { log("failed: \(error.localizedDescription)"); exit(1) }
    }
} else {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { log("done"); exit(0) }
}
app.run()
