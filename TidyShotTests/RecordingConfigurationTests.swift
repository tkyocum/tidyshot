import CoreGraphics
import CoreMedia
import Testing
@testable import TidyShot

struct RecordingConfigurationTests {
    let laptop = RecordingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982), scale: 2)
    /// A second display to the right of the first, at 1x, so display-local points differ from global ones.
    let external = RecordingDisplay(id: 2, frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), scale: 1)

    func options(fps: Int = 30, retina: Bool = true, audio: Bool = false, cursor: Bool = true) -> RecordingOptions {
        RecordingOptions(framesPerSecond: fps, retina: retina, systemAudio: audio, showsCursor: cursor)
    }

    @Test func retinaAreaRecordsAtTheDisplayScale() {
        let config = RecordingConfiguration.make(.area(CGRect(x: 100, y: 50, width: 800, height: 500), on: laptop),
                                                 options: options())
        #expect(config.filter == .area(displayID: 1, sourceRect: CGRect(x: 100, y: 50, width: 800, height: 500)))
        #expect(config.pixelWidth == 1600)
        #expect(config.pixelHeight == 1000)
    }

    @Test func standardAreaRecordsAtOnePixelPerPoint() {
        let config = RecordingConfiguration.make(.area(CGRect(x: 100, y: 50, width: 800, height: 500), on: laptop),
                                                 options: options(retina: false))
        #expect(config.pixelWidth == 800)
        #expect(config.pixelHeight == 500)
        #expect(config.filter == .area(displayID: 1, sourceRect: CGRect(x: 100, y: 50, width: 800, height: 500)))
    }

    /// 801×501 pt at 1x rounds down to 800×500 px, so the source shrinks by a point, centred,
    /// and the video is not letterboxed. The source rect is local to the second display.
    @Test func oddPointSizeAtStandardShrinksTheSourceRect() {
        let config = RecordingConfiguration.make(.area(CGRect(x: 1612, y: 200, width: 801, height: 501), on: external),
                                                 options: options(retina: false))
        #expect(config.pixelWidth == 800)
        #expect(config.pixelHeight == 500)
        #expect(config.filter == .area(displayID: 2, sourceRect: CGRect(x: 100.5, y: 200.5, width: 800, height: 500)))
    }

    @Test func areaLargerThanItsDisplayIsClampedToIt() {
        let config = RecordingConfiguration.make(.area(CGRect(x: -100, y: 900, width: 800, height: 500), on: laptop),
                                                 options: options())
        #expect(config.filter == .area(displayID: 1, sourceRect: CGRect(x: 0, y: 900, width: 700, height: 82)))
        #expect(config.pixelWidth == 1400)
        #expect(config.pixelHeight == 164)

        let whole = RecordingConfiguration.make(.area(CGRect(x: -50, y: -50, width: 4000, height: 4000), on: laptop),
                                                options: options(retina: false))
        #expect(whole.filter == .area(displayID: 1, sourceRect: CGRect(x: 0, y: 0, width: 1512, height: 982)))
        #expect(whole.pixelWidth == 1512)
        #expect(whole.pixelHeight == 982)
    }

    /// 1152×2560 pt at 2x is 2304×5120 px, capped to 1842×4096. Flooring 1843.2 to an even 1842
    /// changes the aspect, so the source loses 0.75 pt of width, centred.
    @Test func cappedAreaShrinksTheSourceRectByTheFlooredPixels() {
        let portrait = RecordingDisplay(id: 3, frame: CGRect(x: 0, y: 0, width: 1152, height: 2560), scale: 2)
        let config = RecordingConfiguration.make(.area(portrait.frame, on: portrait), options: options())
        #expect(config.pixelWidth == 1842)
        #expect(config.pixelHeight == 4096)
        #expect(config.filter == .area(displayID: 3, sourceRect: CGRect(x: 0.375, y: 0, width: 1151.25, height: 2560)))
    }

    @Test func displayRecordsTheWholeDisplay() {
        let fiveK = RecordingDisplay(id: 5, frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), scale: 2)
        let retina = RecordingConfiguration.make(.display(fiveK), options: options())
        #expect(retina.filter == .display(displayID: 5))
        #expect(retina.pixelWidth == 4096)
        #expect(retina.pixelHeight == 2304)

        let standard = RecordingConfiguration.make(.display(fiveK), options: options(retina: false))
        #expect(standard.pixelWidth == 2560)
        #expect(standard.pixelHeight == 1440)
        #expect(!standard.ignoresShadowsSingleWindow)
    }

    /// Sized from the frame, never the shadow-inclusive content rect, and scaled to fit if it resizes.
    @Test func windowIsSizedFromItsFrameTimesTheScale() {
        let source = RecordingSource.window(id: 42, frame: CGRect(x: 300, y: 200, width: 1280, height: 800), scale: 2)
        let config = RecordingConfiguration.make(source, options: options())
        #expect(config.filter == .window(windowID: 42))
        #expect(config.pixelWidth == 2560)
        #expect(config.pixelHeight == 1600)
        #expect(config.ignoresShadowsSingleWindow)
        #expect(config.scalesToFit)
        #expect(config.preservesAspectRatio)

        let standard = RecordingConfiguration.make(source, options: options(retina: false))
        #expect(standard.pixelWidth == 1280)
        #expect(standard.pixelHeight == 800)
    }

    @Test(arguments: [
        (CGSize(width: 2560, height: 1440), CGFloat(2), 4096, 2304),
        (CGSize(width: 2056, height: 1329), CGFloat(2), 4096, 2646),
        (CGSize(width: 1152, height: 2560), CGFloat(2), 1842, 4096),
        (CGSize(width: 2048, height: 2048), CGFloat(2), 4096, 4096),
        (CGSize(width: 1728, height: 1117), CGFloat(2), 3456, 2234),
        (CGSize(width: 2560, height: 1440), CGFloat(1), 2560, 1440),
    ])
    func outputSizeCapsTheLongerSideAt4096(points: CGSize, scale: CGFloat, width: Int, height: Int) {
        let size = RecordingConfiguration.outputSize(points: points, scale: scale)
        #expect(size.width == width)
        #expect(size.height == height)
    }

    @Test func outputSizeRoundsEachSideDownToEven() {
        let size = RecordingConfiguration.outputSize(points: CGSize(width: 801, height: 501), scale: 1)
        #expect(size.width == 800)
        #expect(size.height == 500)
    }

    @Test func frameRateSetsTheMinimumFrameInterval() {
        let area = RecordingSource.area(CGRect(x: 0, y: 0, width: 400, height: 300), on: laptop)
        let thirty = RecordingConfiguration.make(area, options: options(fps: 30))
        #expect(thirty.framesPerSecond == 30)
        #expect(thirty.minimumFrameInterval == CMTime(value: 1, timescale: 30))

        let sixty = RecordingConfiguration.make(area, options: options(fps: 60))
        #expect(sixty.framesPerSecond == 60)
        #expect(sixty.minimumFrameInterval == CMTime(value: 1, timescale: 60))
    }

    @Test func cursorAndAudioFollowTheSettings() {
        let area = RecordingSource.area(CGRect(x: 0, y: 0, width: 400, height: 300), on: laptop)
        let defaults = RecordingConfiguration.make(area, options: options())
        #expect(defaults.showsCursor)
        #expect(!defaults.capturesAudio)
        #expect(defaults.excludesCurrentProcessAudio)

        let changed = RecordingConfiguration.make(area, options: options(audio: true, cursor: false))
        #expect(!changed.showsCursor)
        #expect(changed.capturesAudio)
        #expect(changed.excludesCurrentProcessAudio)
    }

    /// A GIF records an MP4 at 30 fps with no sound, whatever the options say; its size follows
    /// `Resolution` as an MP4's does.
    @Test func aGIFRecordingNeverCapturesAudioAndRecordsAt30FPS() {
        let area = RecordingSource.area(CGRect(x: 100, y: 50, width: 800, height: 500), on: laptop)
        var gif = options(fps: 60, audio: true)
        gif.format = .gif
        let config = RecordingConfiguration.make(area, options: gif)
        #expect(RecordingConfiguration.gifFramesPerSecond == 30)
        #expect(config.framesPerSecond == 30)
        #expect(config.minimumFrameInterval == CMTime(value: 1, timescale: 30))
        #expect(!config.capturesAudio)
        #expect(config.pixelWidth == 1600)
        #expect(config.pixelHeight == 1000)

        var standard = gif
        standard.retina = false
        #expect(RecordingConfiguration.make(area, options: standard).pixelWidth == 800)

        let mp4 = RecordingConfiguration.make(area, options: options(fps: 60, audio: true))
        #expect(mp4.framesPerSecond == 60)
        #expect(mp4.capturesAudio)
    }

    @Test func optionsDefaultToMP4AndTheGIFDefaults() {
        let plain = options()
        #expect(plain.format == .mp4)
        #expect(plain.gif == GIFSettings(fps: 15, maxSide: 1280))
    }

    @Test func areaMinimumIs32PointsEachWay() {
        #expect(RecordingConfiguration.minimumAreaSide == 32)
        #expect(RecordingConfiguration.isLargeEnough(CGRect(x: 10, y: 10, width: 32, height: 32)))
        #expect(!RecordingConfiguration.isLargeEnough(CGRect(x: 10, y: 10, width: 31.5, height: 400)))
        #expect(!RecordingConfiguration.isLargeEnough(CGRect(x: 10, y: 10, width: 400, height: 31)))
    }
}
