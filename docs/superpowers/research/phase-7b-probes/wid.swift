import AppKit
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowLayer as String] as! Int) < -2147483000 { print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, w[kCGWindowOwnerName as String] ?? "-", w[kCGWindowName as String] ?? "-") }
