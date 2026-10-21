import Foundation
import Testing
@testable import TidyShot

struct AppSettingsTests {
    func freshDefaults() -> UserDefaults {
        let name = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func phase2DefaultsAreUploadWithURLOnly() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.afterCaptureAction == .upload)
        #expect(settings.alsoCopyImageWhenUploading == false)
        #expect(settings.showOverlay)
        #expect(settings.overlayCorner == .bottomRight)
        #expect(settings.overlayAutoCloseSeconds == 5)
        #expect(settings.historyRetentionDays == 30)
        #expect(settings.s3Config == nil)
        // Phase 4: a red stroke, black redactions, 4 pt lines, an 8 pt blur and 10 pt pixel blocks.
        #expect(settings.editorStrokeColor == EditorPalette.defaultStroke)
        #expect(settings.editorRedactColor == EditorPalette.defaultRedact)
        #expect(settings.editorLineWidthPoints == 4)
        #expect(settings.editorBlurRadiusPoints == 8)
        #expect(settings.editorPixelBlockPoints == 10)
        #expect(settings.editorDefaults == EditorDefaults.standard)
    }

    @Test func s3ConfigRoundTripsThroughDefaults() {
        let defaults = freshDefaults()
        let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                         usePathStyle: true, sendPublicReadACL: true,
                                         publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "p/{random:8}")
        let first = AppSettings(defaults: defaults)
        first.s3Config = config
        first.afterCaptureAction = .save
        first.overlayCorner = .topLeft

        let second = AppSettings(defaults: defaults)
        #expect(second.s3Config == config)
        #expect(second.afterCaptureAction == .save)
        #expect(second.overlayCorner == .topLeft)

        second.s3Config = nil
        #expect(AppSettings(defaults: defaults).s3Config == nil)
    }

    @Test func lastAreaRectIsNilUntilAnAreaIsCaptured() {
        #expect(AppSettings(defaults: freshDefaults()).lastAreaRect == nil)
    }

    @Test func lastAreaRectRoundTripsThroughASecondInstanceAndClears() {
        let defaults = freshDefaults()
        let rect = StoredRect(CGRect(x: -300, y: 120.5, width: 640, height: 480))
        let first = AppSettings(defaults: defaults)
        first.lastAreaRect = rect
        #expect(AppSettings(defaults: defaults).lastAreaRect == rect)
        #expect(defaults.data(forKey: "lastAreaRect") != nil)

        first.lastAreaRect = nil
        #expect(AppSettings(defaults: defaults).lastAreaRect == nil)
        #expect(defaults.object(forKey: "lastAreaRect") == nil)
    }

    @Test func anUnreadableLastAreaRectReadsAsNil() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "lastAreaRect")
        #expect(AppSettings(defaults: defaults).lastAreaRect == nil)
    }

    /// `{app}` was removed in Phase 3.1. Templates saved before that lose it on load, and the
    /// rewritten values are stored, so the next launch reads them as they are.
    @Test func storedTemplatesLoseTheRemovedAppToken() throws {
        let defaults = freshDefaults()
        defaults.set("{app} {datetime}", forKey: "fileNameTemplate")
        let old = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                      publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "shots/{app}/{random:8}")
        defaults.set(try JSONEncoder().encode(old), forKey: "s3DestinationConfig")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.fileNameTemplate == "{datetime}")
        #expect(settings.s3Config?.keyTemplate == "shots/{random:8}")
        #expect(defaults.string(forKey: "fileNameTemplate") == "{datetime}")
        let stored = try #require(defaults.data(forKey: "s3DestinationConfig"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("{app}"))
    }

    /// The five editor values persist under the keys spec 2.6 names, and a second instance (the
    /// next launch) reads them back.
    @Test func editorDefaultsRoundTripThroughSecondInstance() {
        let defaults = freshDefaults()
        let chosen = EditorDefaults(strokeColor: RGBA(red: 0, green: 0.5, blue: 1, alpha: 1),
                                    redactColor: RGBA(red: 1, green: 1, blue: 1, alpha: 1),
                                    lineWidthPoints: 12, blurRadiusPoints: 20, blockPoints: 6)
        let first = AppSettings(defaults: defaults)
        first.editorDefaults = chosen
        #expect(first.editorDefaults == chosen)
        #expect(defaults.double(forKey: "editorLineWidthPoints") == 12)
        #expect(defaults.double(forKey: "editorBlurRadiusPoints") == 20)
        #expect(defaults.double(forKey: "editorPixelBlockPoints") == 6)

        let second = AppSettings(defaults: defaults)
        #expect(second.editorDefaults == chosen)

        // One value set on its own is stored too.
        second.editorBlurRadiusPoints = 4
        #expect(AppSettings(defaults: defaults).editorDefaults.blurRadiusPoints == 4)
    }

    /// Colours are stored as JSON `Data` that decodes as `RGBA`. Nothing is written until a colour
    /// is set, and a value that does not decode falls back to the default.
    @Test func rgbaStoredAsJSON() throws {
        let defaults = freshDefaults()
        let teal = RGBA(red: 0.2, green: 0.7, blue: 0.7, alpha: 1)
        let settings = AppSettings(defaults: defaults)
        settings.editorStrokeColor = teal
        let stored = try #require(defaults.data(forKey: "editorStrokeColor"))
        #expect(try JSONDecoder().decode(RGBA.self, from: stored) == teal)
        #expect(defaults.data(forKey: "editorRedactColor") == nil)

        defaults.set(Data("not json".utf8), forKey: "editorRedactColor")
        #expect(AppSettings(defaults: defaults).editorRedactColor == EditorPalette.defaultRedact)
    }

    /// The Scroll automatically checkbox is on by default and persists (spec 2.8).
    @Test func scrollingAutoScrollDefaultsOnAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.scrollingAutoScroll)
        first.scrollingAutoScroll = false
        #expect(defaults.object(forKey: "scrollingAutoScroll") as? Bool == false)
        #expect(!AppSettings(defaults: defaults).scrollingAutoScroll)
    }

    /// Include window shadow is off by default, which keeps today's output, and persists (spec 2.9).
    @Test func windowShadowDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.windowShadow)
        first.windowShadow = true
        #expect(defaults.object(forKey: "windowShadow") as? Bool == true)
        #expect(AppSettings(defaults: defaults).windowShadow)
    }

    /// Freeze screen while selecting is off by default and persists (spec 2.9).
    @Test func freezeScreenDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.freezeScreen)
        first.freezeScreen = true
        #expect(defaults.object(forKey: "freezeScreen") as? Bool == true)
        #expect(AppSettings(defaults: defaults).freezeScreen)
    }

    /// Phase 6a: the stack shows up to five cards on the display of the capture (spec 2.9).
    @Test func overlayStackSettingsDefaultAndPersist() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.overlayDisplay == .capture)
        #expect(first.overlayMaxCards == 5)
        first.overlayDisplay = .main
        first.overlayMaxCards = 3
        #expect(defaults.string(forKey: "overlayDisplay") == "main")
        #expect(defaults.integer(forKey: "overlayMaxCards") == 3)
        let second = AppSettings(defaults: defaults)
        #expect(second.overlayDisplay == .main)
        #expect(second.overlayMaxCards == 3)
    }

    /// A stored value outside the Stepper's 1 to 8, or an unknown display choice, reads as the
    /// nearest valid one.
    @Test func overlayStackSettingsOutOfRangeReadAsValid() {
        let defaults = freshDefaults()
        defaults.set("elsewhere", forKey: "overlayDisplay")
        defaults.set(0, forKey: "overlayMaxCards")
        let low = AppSettings(defaults: defaults)
        #expect(low.overlayDisplay == .capture)
        #expect(low.overlayMaxCards == 1)
        defaults.set(20, forKey: "overlayMaxCards")
        #expect(AppSettings(defaults: defaults).overlayMaxCards == 8)
    }

    /// Close after dragging out is on by default and persists (spec 2.9).
    @Test func overlayCloseAfterDragDefaultsOnAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.overlayCloseAfterDrag)
        first.overlayCloseAfterDrag = false
        #expect(defaults.object(forKey: "overlayCloseAfterDrag") as? Bool == false)
        #expect(!AppSettings(defaults: defaults).overlayCloseAfterDrag)
    }

    /// All-in-One's aspect lock is off by default and persists (spec 2.9).
    @Test func allInOneAspectLockDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.allInOneAspectLock)
        first.allInOneAspectLock = true
        #expect(defaults.object(forKey: "allInOneAspectLock") as? Bool == true)
        #expect(AppSettings(defaults: defaults).allInOneAspectLock)
    }

    /// Optimize images with Clop is off by default and persists (spec 2.7).
    @Test func optimiseWithClopDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.optimiseWithClop)
        first.optimiseWithClop = true
        #expect(defaults.object(forKey: "optimiseWithClop") as? Bool == true)
        #expect(AppSettings(defaults: defaults).optimiseWithClop)
    }

    /// Hide desktop icons while capturing, and Hide Desktop Icons until turned off, are both off by
    /// default and persist (spec 2.10).
    @Test func desktopIconSettingsDefaultOffAndPersist() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.hideDesktopIconsWhileCapturing)
        #expect(!first.desktopIconsHidden)
        first.hideDesktopIconsWhileCapturing = true
        first.desktopIconsHidden = true
        #expect(defaults.object(forKey: "hideDesktopIconsWhileCapturing") as? Bool == true)
        #expect(defaults.object(forKey: "desktopIconsHidden") as? Bool == true)
        let second = AppSettings(defaults: defaults)
        #expect(second.hideDesktopIconsWhileCapturing)
        #expect(second.desktopIconsHidden)
        second.desktopIconsHidden = false
        #expect(!AppSettings(defaults: defaults).desktopIconsHidden)
        #expect(AppSettings(defaults: defaults).hideDesktopIconsWhileCapturing)
    }

    /// Phase 6b: Self-timer counts 5 seconds unless the Capture tab says 3 or 10 (spec 2.9).
    @Test func selfTimerSecondsDefaultsToFiveAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.selfTimerSeconds == 5)
        #expect(AppSettings.selfTimerChoices == [3, 5, 10])
        first.selfTimerSeconds = 10
        #expect(defaults.integer(forKey: "selfTimerSeconds") == 10)
        #expect(AppSettings(defaults: defaults).selfTimerSeconds == 10)
    }

    /// A stored value the picker does not offer reads as the default.
    @Test func selfTimerSecondsOutsideTheChoicesReadAsFive() {
        let defaults = freshDefaults()
        for stored in [0, 1, 4, 7, 60, -3] {
            defaults.set(stored, forKey: "selfTimerSeconds")
            #expect(AppSettings(defaults: defaults).selfTimerSeconds == 5)
        }
        defaults.set(3, forKey: "selfTimerSeconds")
        #expect(AppSettings(defaults: defaults).selfTimerSeconds == 3)
    }

    /// Phase 7c: Add background to window captures is off, and the style is the default one.
    @Test func windowBackgroundDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.windowBackground)
        first.windowBackground = true
        #expect(defaults.object(forKey: "windowBackground") as? Bool == true)
        #expect(AppSettings(defaults: defaults).windowBackground)
    }

    @Test func backgroundStyleIsStoredAsJSONAndRoundTrips() throws {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.backgroundStyle == BackgroundStyle())
        let style = BackgroundStyle(fill: .solid(RGBA(hex: 0x336699)), padding: 80, cornerRadius: 4,
                                    shadow: false, aspect: .sixteenNine)
        first.backgroundStyle = style
        let data = try #require(defaults.data(forKey: "backgroundStyle"))
        #expect(try JSONDecoder().decode(BackgroundStyle.self, from: data) == style)
        #expect(AppSettings(defaults: defaults).backgroundStyle == style)
    }

    /// JSON that does not decode, or names a fill or aspect this build does not know (written by a
    /// newer build), reads as the default style.
    @Test func anUnreadableBackgroundStyleReadsAsTheDefault() {
        let defaults = freshDefaults()
        for json in ["not json", #"{"aspect":"twentyOneNine"}"#, #"{"fill":{"video":{}}}"#] {
            defaults.set(Data(json.utf8), forKey: "backgroundStyle")
            #expect(AppSettings(defaults: defaults).backgroundStyle == BackgroundStyle())
        }
    }

    @Test func urlCommandsAreOnAndSilentCapturesOffByDefault() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.urlCommandsEnabled)
        #expect(!settings.urlCommandsAllowSilent)
    }

    @Test func urlCommandSettingsRoundTripThroughASecondInstance() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.urlCommandsEnabled = false
        first.urlCommandsAllowSilent = true
        let second = AppSettings(defaults: defaults)
        #expect(!second.urlCommandsEnabled)
        #expect(second.urlCommandsAllowSilent)
        #expect(defaults.object(forKey: "urlCommandsEnabled") as? Bool == false)
        #expect(defaults.object(forKey: "urlCommandsAllowSilent") as? Bool == true)
    }
}
