import CoreGraphics
import Testing
@testable import TidyShot

struct WallpaperMatcherTests {
    private let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let second = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
    private let wallpaperLayer = -2147483624

    private func window(_ id: CGWindowID, bundleID: String? = "com.apple.WindowManager", title: String? = "Wallpaper",
                        layer: Int? = nil, frame: CGRect) -> WallpaperCandidate {
        WallpaperCandidate(windowID: id, bundleID: bundleID, title: title, layer: layer ?? wallpaperLayer, frame: frame)
    }

    @Test func theTitledWindowMatches() {
        let candidates = [
            window(1, bundleID: "com.apple.finder", title: nil, layer: -2147483603, frame: main),
            window(2, title: nil, layer: wallpaperLayer - 1, frame: main),
            window(3, frame: main),
            window(4, bundleID: "com.apple.notificationcenterui", title: nil, layer: -2147483601, frame: main),
        ]
        #expect(WallpaperMatcher.match(candidates, displayFrame: main) == 3)
    }

    @Test func aSecondDisplayGetsItsOwnWallpaper() {
        let candidates = [window(10, frame: main), window(11, frame: second)]
        #expect(WallpaperMatcher.match(candidates, displayFrame: main) == 10)
        #expect(WallpaperMatcher.match(candidates, displayFrame: second) == 11)
    }

    @Test func withoutTheTitleTheLowestLayerWindowManagerWindowMatches() {
        let candidates = [
            window(20, title: nil, layer: -2147483602, frame: main),
            window(21, title: "", layer: wallpaperLayer, frame: main),
            window(22, bundleID: "com.apple.finder", title: nil, layer: wallpaperLayer - 5, frame: main),
            window(23, title: nil, layer: wallpaperLayer - 2, frame: second),
        ]
        #expect(WallpaperMatcher.match(candidates, displayFrame: main) == 21)
    }

    @Test func anotherDisplaysWallpaperIsIgnored() {
        let candidates = [window(30, frame: second)]
        #expect(WallpaperMatcher.match(candidates, displayFrame: main) == nil)
    }

    @Test func noMatch() {
        let candidates = [
            window(40, bundleID: "com.apple.finder", frame: main),
            window(41, bundleID: nil, frame: main),
            window(42, frame: main.insetBy(dx: 0, dy: 12)),
        ]
        #expect(WallpaperMatcher.match(candidates, displayFrame: main) == nil)
        #expect(WallpaperMatcher.match([], displayFrame: main) == nil)
    }
}
