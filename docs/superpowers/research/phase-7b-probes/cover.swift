import ScreenCaptureKit
import AppKit

@MainActor func run() async throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let display = content.displays.first!
    let scale = NSScreen.screens.first!.backingScaleFactor
    let wall = content.windows.first { $0.owningApplication?.bundleIdentifier == "com.apple.WindowManager" && $0.title == "Wallpaper" && $0.frame == display.frame }!
    let wcfg = SCStreamConfiguration(); wcfg.width = Int(wall.frame.width * scale); wcfg.height = Int(wall.frame.height * scale); wcfg.showsCursor = false; wcfg.ignoreShadowsSingleWindow = true
    var t = Date()
    let wallImage = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: wall), configuration: wcfg)
    print("wallpaper capture \(Int(Date().timeIntervalSince(t) * 1000)) ms", wallImage.width, wallImage.height)

    let dcfg = SCStreamConfiguration(); dcfg.width = Int(display.frame.width * scale); dcfg.height = Int(display.frame.height * scale); dcfg.showsCursor = false
    // Only desktop-level windows, so the user's apps do not hide anything.
    func desktopShot(_ extra: [SCWindow] = []) async throws -> CGImage {
        let c = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let desk = c.windows.filter { $0.windowLayer < 0 && $0.frame.intersects(display.frame) }
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: desk), configuration: dcfg)
    }
    let before = try await desktopShot()

    let screen = NSScreen.screens.first!
    let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 3)
    win.ignoresMouseEvents = true
    win.isOpaque = true
    win.hasShadow = false
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    let view = NSView(frame: screen.frame); view.wantsLayer = true
    view.layer!.contents = wallImage; view.layer!.contentsGravity = .resize
    win.contentView = view
    t = Date()
    win.orderFrontRegardless()
    CATransaction.flush()
    var shots: [(Int, CGImage)] = []
    for delay in [0, 16, 33, 50, 100] {
        let target = t.addingTimeInterval(Double(delay) / 1000)
        if target > Date() { try await Task.sleep(for: .milliseconds(Int(target.timeIntervalSinceNow * 1000))) }
        shots.append((delay, try await desktopShot()))
    }
    print("cover window number", win.windowNumber)
    win.orderOut(nil)
    func region(_ img: CGImage, _ r: CGRect) -> Double {   // mean abs diff vs wallpaper in region (points)
        let rr = CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale)
        let a = img.cropping(to: rr)!, b = wallImage.cropping(to: rr)!
        func px(_ i: CGImage) -> [UInt8] { let ctx = CGContext(data: nil, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: i.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!; ctx.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height)); return Array(UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: i.width * i.height * 4)) }
        let pa = px(a), pb = px(b); var s = 0.0; for i in 0..<pa.count { s += abs(Double(pa[i]) - Double(pb[i])) }; return s / Double(pa.count)
    }
    let widget = CGRect(x: 2192, y: 1072, width: 360, height: 360), whole = CGRect(x: 0, y: 0, width: 2560, height: 1440), top = CGRect(x: 0, y: 0, width: 2560, height: 122)
    print("before: widgets diff", region(before, widget), "whole", region(before, whole), "top", region(before, top))
    for (d, s) in shots { print("cover +\(d)ms: widgets diff", region(s, widget), "whole", region(s, whole), "top", region(s, top)) }
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "before.png") as CFURL, "public.png" as CFString, 1, nil)!; CGImageDestinationAddImage(dest, before, nil); CGImageDestinationFinalize(dest)
}
Task { @MainActor in
    do { try await run() } catch { print("error", error) }
    exit(0)
}
RunLoop.main.run()
