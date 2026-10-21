import Foundation
import Testing
@testable import TidyShot

struct CaptureOptionsTests {
    func settings(showsCursor: Bool, windowShadow: Bool = false) -> AppSettings {
        let name = "CaptureOptionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.showsCursor = showsCursor
        settings.windowShadow = windowShadow
        return settings
    }

    /// The overlay's crosshair is a real cursor, so no capture taken while the overlay is up may
    /// ask for the pointer, whatever the setting says.
    @Test func aCaptureDuringSelectionNeverShowsTheCursor() {
        #expect(CaptureOptions(settings: settings(showsCursor: true), duringSelection: true).showsCursor == false)
        #expect(CaptureOptions(settings: settings(showsCursor: false), duringSelection: true).showsCursor == false)
    }

    /// Fullscreen, previous-area, self-timer and URL captures (no overlay) and a frozen snapshot
    /// follow the setting.
    @Test func aCaptureWithoutTheOverlayFollowsTheSetting() {
        #expect(CaptureOptions(settings: settings(showsCursor: true), duringSelection: false).showsCursor)
        #expect(CaptureOptions(settings: settings(showsCursor: false), duringSelection: false).showsCursor == false)
    }

    /// The shadow option does not depend on the overlay.
    @Test func theWindowShadowFollowsTheSettingEitherWay() {
        for duringSelection in [true, false] {
            #expect(CaptureOptions(settings: settings(showsCursor: false, windowShadow: true), duringSelection: duringSelection).windowShadow)
            #expect(CaptureOptions(settings: settings(showsCursor: true, windowShadow: false), duringSelection: duringSelection).windowShadow == false)
        }
        #expect(CaptureOptions() == CaptureOptions(showsCursor: false, windowShadow: false))
    }
}
