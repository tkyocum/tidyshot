import ScreenCaptureKit
import AppKit
let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
for w in content.windows where w.windowLayer < 0 {
    print(w.windowID, "layer", w.windowLayer, "app", w.owningApplication?.bundleIdentifier ?? "-", "title", w.title ?? "-", "frame", w.frame, "onScreen", w.isOnScreen)
}
print("desktop icon level", CGWindowLevelForKey(.desktopIconWindow), "desktop level", CGWindowLevelForKey(.desktopWindow))
for s in NSScreen.screens { print("screen", s.frame, NSWorkspace.shared.desktopImageURL(for: s) ?? "nil", NSWorkspace.shared.desktopImageOptions(for: s) ?? [:]) }
