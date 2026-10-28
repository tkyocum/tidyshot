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
        // 4c: a rectangle spotlight and a 32 pt counter.
        #expect(settings.editorSpotlightEllipse == false)
        #expect(settings.editorCounterDiameterPoints == 32)
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

    /// The seven editor values persist under the keys specs 2.6 and 2.12 name, and a second
    /// instance (the next launch) reads them back.
    @Test func editorDefaultsRoundTripThroughSecondInstance() {
        let defaults = freshDefaults()
        let chosen = EditorDefaults(strokeColor: RGBA(red: 0, green: 0.5, blue: 1, alpha: 1),
                                    redactColor: RGBA(red: 1, green: 1, blue: 1, alpha: 1),
                                    lineWidthPoints: 12, blurRadiusPoints: 20, blockPoints: 6,
                                    spotlightEllipse: true, counterDiameterPoints: 44)
        let first = AppSettings(defaults: defaults)
        first.editorDefaults = chosen
        #expect(first.editorDefaults == chosen)
        #expect(defaults.double(forKey: "editorLineWidthPoints") == 12)
        #expect(defaults.double(forKey: "editorBlurRadiusPoints") == 20)
        #expect(defaults.double(forKey: "editorPixelBlockPoints") == 6)
        #expect(defaults.bool(forKey: "editorSpotlightEllipse") == true)
        #expect(defaults.double(forKey: "editorCounterDiameterPoints") == 44)

        let second = AppSettings(defaults: defaults)
        #expect(second.editorDefaults == chosen)

        // One value set on its own is stored too.
        second.editorBlurRadiusPoints = 4
        #expect(AppSettings(defaults: defaults).editorDefaults.blurRadiusPoints == 4)
    }

    /// A fresh store reads a rectangle spotlight and a 32 pt counter. 32 is registered, because
    /// `double(forKey:)` reads 0 for a missing key.
    @Test func spotlightAndCounterDefaultsAreRegistered() {
        let defaults = freshDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.editorSpotlightEllipse == false)
        #expect(settings.editorCounterDiameterPoints == 32)
        #expect(defaults.bool(forKey: "editorSpotlightEllipse") == false)
        #expect(defaults.double(forKey: "editorCounterDiameterPoints") == 32)

        settings.editorSpotlightEllipse = true
        settings.editorCounterDiameterPoints = 24
        let next = AppSettings(defaults: defaults)
        #expect(next.editorSpotlightEllipse)
        #expect(next.editorCounterDiameterPoints == 24)
    }

    /// Only Small, Medium and Large are counter sizes; anything else stored reads as 32.
    @Test func aStoredCounterSizeOutsideTheStopsReadsAs32() {
        let defaults = freshDefaults()
        for stored in [40.0, 0, -24, 1000] {
            defaults.set(stored, forKey: "editorCounterDiameterPoints")
            #expect(AppSettings(defaults: defaults).editorCounterDiameterPoints == 32)
        }
        defaults.set(44.0, forKey: "editorCounterDiameterPoints")
        #expect(AppSettings(defaults: defaults).editorCounterDiameterPoints == 44)
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

    /// Recording R1: 30 fps, Retina, no system audio, the cursor shown, the count-in on, and the
    /// recording file name template.
    @Test func recordingSettingsDefaultAsTheDesignSays() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.recordingFrameRate == 30)
        #expect(settings.recordingRetina)
        #expect(!settings.recordingSystemAudio)
        #expect(settings.recordingShowsCursor)
        #expect(settings.recordingCountdown)
        #expect(settings.recordingFileNameTemplate == "Recording {date} at {time}")
        #expect(AppSettings.recordingFrameRates == [30, 60])
        #expect(settings.recordingOptions
                == RecordingOptions(framesPerSecond: 30, retina: true, systemAudio: false, showsCursor: true))
    }

    @Test func recordingSettingsPersistUnderTheirKeys() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.recordingFrameRate = 60
        first.recordingRetina = false
        first.recordingSystemAudio = true
        first.recordingShowsCursor = false
        first.recordingCountdown = false
        first.recordingFileNameTemplate = "Clip {counter}"
        #expect(defaults.integer(forKey: "recordingFrameRate") == 60)
        #expect(defaults.object(forKey: "recordingRetina") as? Bool == false)
        #expect(defaults.object(forKey: "recordingSystemAudio") as? Bool == true)
        #expect(defaults.object(forKey: "recordingShowsCursor") as? Bool == false)
        #expect(defaults.object(forKey: "recordingCountdown") as? Bool == false)
        #expect(defaults.string(forKey: "recordingFileNameTemplate") == "Clip {counter}")

        let second = AppSettings(defaults: defaults)
        #expect(second.recordingFrameRate == 60)
        #expect(!second.recordingRetina)
        #expect(second.recordingSystemAudio)
        #expect(!second.recordingShowsCursor)
        #expect(!second.recordingCountdown)
        #expect(second.recordingFileNameTemplate == "Clip {counter}")
        #expect(second.recordingOptions
                == RecordingOptions(framesPerSecond: 60, retina: false, systemAudio: true, showsCursor: false))
    }

    /// A recording reads the format and the GIF settings with the rest, at its start.
    @Test func recordingOptionsCarryTheFormatAndTheGIFSettings() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.recordingOptions.format == .mp4)
        #expect(settings.recordingOptions.gif == GIFSettings(fps: 15, maxSide: 1280))
        settings.recordingFormat = .gif
        settings.gifFrameRate = 20
        settings.gifMaxSide = 0
        #expect(settings.recordingOptions.format == .gif)
        #expect(settings.recordingOptions.gif == GIFSettings(fps: 20, maxSide: 0))
    }

    /// A stored frame rate the picker does not offer reads as 30.
    @Test func aStoredFrameRateOtherThan30Or60ReadsAs30() {
        let defaults = freshDefaults()
        for stored in [45, 0, 24, 120, -30] {
            defaults.set(stored, forKey: "recordingFrameRate")
            #expect(AppSettings(defaults: defaults).recordingFrameRate == 30)
        }
        defaults.set(60, forKey: "recordingFrameRate")
        #expect(AppSettings(defaults: defaults).recordingFrameRate == 60)
    }

    /// Recording R2: MP4, a 15 fps GIF capped at 1280 px, and no microphone.
    @Test func r2RecordingSettingsDefaultAsTheDesignSays() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.recordingFormat == .mp4)
        #expect(settings.gifFrameRate == 15)
        #expect(settings.gifMaxSide == 1280)
        #expect(settings.recordingMicrophone == "")
        #expect(settings.recordingMicrophoneName == "")
        #expect(AppSettings.gifFrameRates == [10, 15, 20])
        #expect(AppSettings.gifMaxSides == [800, 1280, 0])
        #expect(settings.gifSettings == GIFSettings(fps: 15, maxSide: 1280))
    }

    @Test func r2RecordingSettingsPersistUnderTheirKeys() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.recordingFormat = .gif
        first.gifFrameRate = 20
        first.gifMaxSide = 0
        first.recordingMicrophone = "AppleUSBAudioEngine:RODE:AI-1:1"
        first.recordingMicrophoneName = "RODE AI-1"
        #expect(defaults.string(forKey: "recordingFormat") == "gif")
        #expect(defaults.object(forKey: "gifFrameRate") as? Int == 20)
        #expect(defaults.object(forKey: "gifMaxSide") as? Int == 0)
        #expect(defaults.string(forKey: "recordingMicrophone") == "AppleUSBAudioEngine:RODE:AI-1:1")
        #expect(defaults.string(forKey: "recordingMicrophoneName") == "RODE AI-1")

        let second = AppSettings(defaults: defaults)
        #expect(second.recordingFormat == .gif)
        #expect(second.gifFrameRate == 20)
        #expect(second.gifMaxSide == 0)
        #expect(second.recordingMicrophone == "AppleUSBAudioEngine:RODE:AI-1:1")
        #expect(second.recordingMicrophoneName == "RODE AI-1")
        #expect(second.gifSettings == GIFSettings(fps: 20, maxSide: 0))

        second.recordingFormat = .mp4
        second.gifFrameRate = 10
        second.gifMaxSide = 800
        second.recordingMicrophone = "default"
        second.recordingMicrophoneName = ""
        let third = AppSettings(defaults: defaults)
        #expect(third.recordingFormat == .mp4)
        #expect(third.gifSettings == GIFSettings(fps: 10, maxSide: 800))
        #expect(third.recordingMicrophone == "default")
        #expect(third.recordingMicrophoneName == "")
    }

    /// A stored value the pickers do not offer reads as the default. `Full size` is 0, so a value
    /// that is not a number must not read as it.
    @Test func r2StoredValuesOutsideTheChoicesReadAsTheDefaults() {
        let defaults = freshDefaults()
        defaults.set(12, forKey: "gifFrameRate")
        defaults.set(640, forKey: "gifMaxSide")
        defaults.set("webm", forKey: "recordingFormat")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.gifFrameRate == 15)
        #expect(settings.gifMaxSide == 1280)
        #expect(settings.recordingFormat == .mp4)

        for stored in [0, -15, 30] {
            defaults.set(stored, forKey: "gifFrameRate")
            #expect(AppSettings(defaults: defaults).gifFrameRate == 15)
        }
        for stored: Any in [-1, 4096, "Full size", true] {
            defaults.set(stored, forKey: "gifMaxSide")
            #expect(AppSettings(defaults: defaults).gifMaxSide == 1280)
        }
        defaults.set("GIF", forKey: "recordingFormat")
        #expect(AppSettings(defaults: defaults).recordingFormat == .mp4)
    }

    /// Recording R3: both features off, the default camera, a Medium bubble 16 pt from the corner.
    @Test func r3RecordingSettingsDefaultAsTheDesignSays() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(!settings.recordingClickHighlights)
        #expect(!settings.recordingWebcamBubble)
        #expect(settings.recordingCamera == "default")
        #expect(settings.recordingCameraName == "")
        #expect(settings.recordingBubbleSize == .medium)
        #expect(settings.recordingBubbleInsetRight == 16)
        #expect(settings.recordingBubbleInsetBottom == 16)
        #expect(settings.bubbleInsets == BubbleInsets.standard)
    }

    @Test func r3RecordingSettingsPersistUnderTheirKeys() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.recordingClickHighlights = true
        first.recordingWebcamBubble = true
        first.recordingCamera = "0x8020000005ac8514"
        first.recordingCameraName = "Brio 500"
        first.recordingBubbleSize = .large
        first.recordingBubbleInsetRight = 40
        first.recordingBubbleInsetBottom = 72.5
        #expect(defaults.bool(forKey: "recordingClickHighlights"))
        #expect(defaults.bool(forKey: "recordingWebcamBubble"))
        #expect(defaults.string(forKey: "recordingCamera") == "0x8020000005ac8514")
        #expect(defaults.string(forKey: "recordingCameraName") == "Brio 500")
        #expect(defaults.string(forKey: "recordingBubbleSize") == "large")
        #expect(defaults.object(forKey: "recordingBubbleInsetRight") as? Double == 40)
        #expect(defaults.object(forKey: "recordingBubbleInsetBottom") as? Double == 72.5)

        let second = AppSettings(defaults: defaults)
        #expect(second.recordingClickHighlights)
        #expect(second.recordingWebcamBubble)
        #expect(second.recordingCamera == "0x8020000005ac8514")
        #expect(second.recordingCameraName == "Brio 500")
        #expect(second.recordingBubbleSize == .large)
        #expect(second.bubbleInsets == BubbleInsets(right: 40, bottom: 72.5))
    }

    @Test func aStoredBubbleSizeOutsideTheThreeReadsAsMedium() {
        let defaults = freshDefaults()
        for stored in ["huge", "", "Large"] {
            defaults.set(stored, forKey: "recordingBubbleSize")
            #expect(AppSettings(defaults: defaults).recordingBubbleSize == .medium)
        }
        defaults.set("small", forKey: "recordingBubbleSize")
        #expect(AppSettings(defaults: defaults).recordingBubbleSize == .small)
    }

    @Test func aNegativeOrUnreadableBubbleInsetReadsAs16() {
        let defaults = freshDefaults()
        defaults.set(-4, forKey: "recordingBubbleInsetRight")
        defaults.set(Double.nan, forKey: "recordingBubbleInsetBottom")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.recordingBubbleInsetRight == 16)
        #expect(settings.recordingBubbleInsetBottom == 16)
        #expect(settings.bubbleInsets == BubbleInsets.standard)

        // A string, as `defaults write -string` stores it, is not a number, so it must not read
        // as 0, as `double(forKey:)` would.
        defaults.set("nope", forKey: "recordingBubbleInsetRight")
        defaults.set("24", forKey: "recordingBubbleInsetBottom")
        #expect(AppSettings(defaults: defaults).bubbleInsets == BubbleInsets.standard)

        defaults.set(0, forKey: "recordingBubbleInsetRight")
        defaults.set(Float(24.5), forKey: "recordingBubbleInsetBottom")
        #expect(AppSettings(defaults: defaults).bubbleInsets == BubbleInsets(right: 0, bottom: 24.5))
    }

    /// `Full size` keeps R1's 4096 px cap.
    @Test func fullSizeGIFsKeepTheRecordingCap() {
        #expect(GIFSettings(fps: 15, maxSide: 0).effectiveMaxSide == RecordingConfiguration.maximumSide)
        #expect(GIFSettings(fps: 15, maxSide: 0).effectiveMaxSide == 4096)
        #expect(GIFSettings(fps: 15, maxSide: 1280).effectiveMaxSide == 1280)
        #expect(GIFSettings(fps: 10, maxSide: 800).effectiveMaxSide == 800)
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

    /// General's Ask before deleting (spec 2.13): on by default, stored under `confirmBeforeDeleting`.
    @Test func confirmBeforeDeletingDefaultsToTrueAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.confirmBeforeDeleting)

        first.confirmBeforeDeleting = false
        #expect(defaults.object(forKey: "confirmBeforeDeleting") as? Bool == false)
        #expect(!AppSettings(defaults: defaults).confirmBeforeDeleting)

        first.confirmBeforeDeleting = true
        #expect(AppSettings(defaults: defaults).confirmBeforeDeleting)
    }
}
