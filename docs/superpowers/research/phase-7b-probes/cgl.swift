import AppKit
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list {
    let layer = w[kCGWindowLayer as String] as! Int
    if layer < 0 || layer > 1000 { print(layer, w[kCGWindowOwnerName as String] ?? "-", w[kCGWindowName as String] ?? "-", w[kCGWindowBounds as String] ?? "-") }
}
print("desktop icon level", CGWindowLevelForKey(.desktopIconWindow), "desktop level", CGWindowLevelForKey(.desktopWindow), "backstop", CGWindowLevelForKey(.backstopMenu))
for s in NSScreen.screens { print("screen", s.frame, s.backingScaleFactor, NSWorkspace.shared.desktopImageURL(for: s) ?? "nil", NSWorkspace.shared.desktopImageOptions(for: s) ?? [:]) }
