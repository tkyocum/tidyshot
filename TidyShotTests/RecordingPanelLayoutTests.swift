import AppKit
import Testing
@testable import TidyShot

/// The recording bar's layout (design, Mute, Bar; R3 design, Bar): each bar laid out with a time
/// past an hour.
struct RecordingPanelLayoutTests {
    /// An area or fullscreen recording's bars: R2's with the two R3 buttons.
    nonisolated static let plainWithButtons = RecordingPanelLayout.Bar(showsTag: false, showsMute: false, showsOverlayButtons: true)
    nonisolated static let muteWithButtons = RecordingPanelLayout.Bar(showsTag: false, showsMute: true, showsOverlayButtons: true)
    nonisolated static let gifWithButtons = RecordingPanelLayout.Bar(showsTag: true, showsMute: false, showsOverlayButtons: true)
    nonisolated static let bars: [RecordingPanelLayout.Bar] = [.plain, .mute, .gif, plainWithButtons, muteWithButtons,
                                                               gifWithButtons]

    func frames(of bar: RecordingPanelLayout.Bar) -> [CGRect] {
        [RecordingPanelLayout.tagFrame(of: bar), RecordingPanelLayout.timeFrame(of: bar),
         RecordingPanelLayout.highlightsFrame(of: bar), RecordingPanelLayout.bubbleFrame(of: bar),
         RecordingPanelLayout.muteFrame(of: bar), RecordingPanelLayout.stopFrame(of: bar),
         RecordingPanelLayout.cancelFrame(of: bar)].compactMap { $0 }
    }

    @Test func theBarsAre172And208PointsWide() {
        #expect(RecordingPanelLayout.size(of: .plain) == CGSize(width: 172, height: 44))
        #expect(RecordingPanelLayout.size(of: .mute) == CGSize(width: 208, height: 44))
        #expect(RecordingPanelLayout.size(of: .gif) == CGSize(width: 208, height: 44))
    }

    /// The two R3 buttons add two slots of 36 pt.
    @Test func areaAndFullscreenBarsAre244And280PointsWide() {
        #expect(RecordingPanelLayout.size(of: Self.plainWithButtons) == CGSize(width: 244, height: 44))
        #expect(RecordingPanelLayout.size(of: Self.muteWithButtons) == CGSize(width: 280, height: 44))
        #expect(RecordingPanelLayout.size(of: Self.gifWithButtons) == CGSize(width: 280, height: 44))
    }

    /// R2's three bars are a window recording's, and an area or fullscreen bar is none of them.
    @Test func theOverlayButtonsAddToR2sBars() {
        #expect(RecordingPanelLayout.bar(showsMute: false, isGIF: false, showsOverlayButtons: true) == Self.plainWithButtons)
        #expect(RecordingPanelLayout.bar(showsMute: true, isGIF: false, showsOverlayButtons: true) == Self.muteWithButtons)
        #expect(RecordingPanelLayout.bar(showsMute: false, isGIF: true, showsOverlayButtons: true) == Self.gifWithButtons)
        #expect(RecordingPanelLayout.bar(showsMute: true, isGIF: true, showsOverlayButtons: true) == Self.gifWithButtons)
        for bar in [Self.plainWithButtons, Self.muteWithButtons, Self.gifWithButtons] {
            #expect(![RecordingPanelLayout.Bar.plain, .mute, .gif].contains(bar))
        }
        #expect(RecordingPanelLayout.Bar.plain == RecordingPanelLayout.Bar(showsTag: false, showsMute: false, showsOverlayButtons: false))
        #expect(RecordingPanelLayout.Bar.mute == RecordingPanelLayout.Bar(showsTag: false, showsMute: true, showsOverlayButtons: false))
        #expect(RecordingPanelLayout.Bar.gif == RecordingPanelLayout.Bar(showsTag: true, showsMute: false, showsOverlayButtons: false))
    }

    /// A window recording has neither R3 button.
    @Test(arguments: [RecordingPanelLayout.Bar.plain, .mute, .gif])
    func aWindowRecordingsBarHasNoR3Buttons(_ bar: RecordingPanelLayout.Bar) {
        #expect(RecordingPanelLayout.highlightsFrame(of: bar) == nil)
        #expect(RecordingPanelLayout.bubbleFrame(of: bar) == nil)
    }

    /// Left to right: the tag, the time, highlights, bubble, mute, Stop, Cancel, each a spacing
    /// apart, the buttons a button's size.
    @Test(arguments: [plainWithButtons, muteWithButtons, gifWithButtons])
    func theButtonsRunFromTheTimeToCancel(_ bar: RecordingPanelLayout.Bar) throws {
        let highlights = try #require(RecordingPanelLayout.highlightsFrame(of: bar))
        let bubble = try #require(RecordingPanelLayout.bubbleFrame(of: bar))
        let time = RecordingPanelLayout.timeFrame(of: bar)
        let next = RecordingPanelLayout.muteFrame(of: bar) ?? RecordingPanelLayout.stopFrame(of: bar)
        if let tag = RecordingPanelLayout.tagFrame(of: bar) {
            #expect(tag.maxX + 6 == time.minX)
        }
        #expect(time.maxX + 6 == highlights.minX)
        #expect(highlights.maxX + 6 == bubble.minX)
        #expect(bubble.maxX + 6 == next.minX)
        if let mute = RecordingPanelLayout.muteFrame(of: bar) {
            #expect(mute.maxX + 6 == RecordingPanelLayout.stopFrame(of: bar).minX)
        }
        #expect(highlights.size == CGSize(width: 28, height: 28))
        #expect(bubble.size == CGSize(width: 28, height: 28))
    }

    /// The tag and the mute button read the bar's fields, with or without the R3 buttons.
    @Test func theTagAndTheMuteButtonFollowTheirFields() {
        #expect(RecordingPanelLayout.tagFrame(of: .gif) != nil)
        #expect(RecordingPanelLayout.tagFrame(of: Self.gifWithButtons) != nil)
        #expect(RecordingPanelLayout.muteFrame(of: .mute) != nil)
        #expect(RecordingPanelLayout.muteFrame(of: Self.muteWithButtons) != nil)
        for bar in [RecordingPanelLayout.Bar.plain, .mute, Self.plainWithButtons, Self.muteWithButtons] {
            #expect(RecordingPanelLayout.tagFrame(of: bar) == nil)
        }
        for bar in [RecordingPanelLayout.Bar.plain, .gif, Self.plainWithButtons, Self.gifWithButtons] {
            #expect(RecordingPanelLayout.muteFrame(of: bar) == nil)
        }
    }

    /// Only a bar with the tag is a GIF recording's, so an area or fullscreen GIF keeps its 30 s
    /// soft limit.
    @Test(arguments: bars)
    func theFormatFollowsTheTag(_ bar: RecordingPanelLayout.Bar) {
        let model = RecordingPanelModel()
        model.bar = bar
        #expect(model.format == (bar == .gif || bar == Self.gifWithButtons ? .gif : .mp4))
    }

    @Test func anAreaGIFTurnsOrangeAtThirtySeconds() {
        let model = RecordingPanelModel()
        model.bar = Self.gifWithButtons
        #expect(RecordingClock.isPastSoftLimit(30, format: model.format))
    }

    /// The symbol shows the state; the tool tip says what a press does, or why the button is off.
    @Test func theHighlightsButtonShowsItsStateAndSaysWhatAPressDoes() {
        let model = RecordingPanelModel()
        model.highlights = BarToggle(isOn: false, isEnabled: true, disabledToolTip: nil)
        #expect(model.highlightsSymbol == "cursorarrow")
        #expect(model.highlightsToolTip == "Highlight clicks")
        #expect(model.highlightsAccessibilityLabel == "Highlight clicks")
        model.highlights = BarToggle(isOn: true, isEnabled: true, disabledToolTip: nil)
        #expect(model.highlightsSymbol == "cursorarrow.rays")
        #expect(model.highlightsToolTip == "Stop highlighting clicks")
        #expect(model.highlightsAccessibilityLabel == "Stop highlighting clicks")
        model.highlights = BarToggle(isOn: false, isEnabled: false, disabledToolTip: BubbleButtonState.notAvailableText)
        #expect(model.highlightsSymbol == "cursorarrow")
        #expect(model.highlightsToolTip == "Not available for this recording")
        #expect(model.highlightsAccessibilityLabel == "Highlight clicks")
    }

    @Test func theBubbleButtonShowsItsStateAndSaysWhatAPressDoes() {
        let model = RecordingPanelModel()
        model.bubble = BarToggle(isOn: false, isEnabled: true, disabledToolTip: nil)
        #expect(model.bubbleSymbol == "video.slash.fill")
        #expect(model.bubbleToolTip == "Show the webcam bubble")
        #expect(model.bubbleAccessibilityLabel == "Show webcam bubble")
        model.bubble = BarToggle(isOn: true, isEnabled: true, disabledToolTip: nil)
        #expect(model.bubbleSymbol == "video.fill")
        #expect(model.bubbleToolTip == "Hide the webcam bubble")
        #expect(model.bubbleAccessibilityLabel == "Hide webcam bubble")
        model.bubble = BarToggle(isOn: false, isEnabled: false, disabledToolTip: CameraChoice.noCameraText)
        #expect(model.bubbleSymbol == "video.slash.fill")
        #expect(model.bubbleToolTip == CameraChoice.noCameraText)
        #expect(model.bubbleAccessibilityLabel == "Show webcam bubble")
    }

    /// A GIF recording never has a mute button.
    @Test func theBarFollowsTheMuteButtonAndTheFormat() {
        #expect(RecordingPanelLayout.bar(showsMute: false, isGIF: false) == .plain)
        #expect(RecordingPanelLayout.bar(showsMute: true, isGIF: false) == .mute)
        #expect(RecordingPanelLayout.bar(showsMute: false, isGIF: true) == .gif)
        #expect(RecordingPanelLayout.bar(showsMute: true, isGIF: true) == .gif)
    }

    @Test(arguments: bars)
    func noFrameLeavesTheBar(_ bar: RecordingPanelLayout.Bar) {
        let bounds = CGRect(origin: .zero, size: RecordingPanelLayout.size(of: bar))
        for frame in frames(of: bar) {
            #expect(bounds.contains(frame), "\(frame) leaves \(bounds)")
        }
    }

    @Test(arguments: bars)
    func noTwoFramesOverlap(_ bar: RecordingPanelLayout.Bar) {
        let all = frames(of: bar)
        for (index, frame) in all.enumerated() {
            for other in all[(index + 1)...] {
                #expect(!frame.intersects(other), "\(frame) overlaps \(other)")
            }
        }
    }

    @Test(arguments: bars)
    func aTimePastAnHourFitsTheTimeFrame(_ bar: RecordingPanelLayout.Bar) {
        let width = ("9:59:59" as NSString).size(withAttributes: [.font: RecordingPanelLayout.timeFont]).width
        #expect(width <= RecordingPanelLayout.timeFrame(of: bar).width)
        #expect(RecordingClock.format(35_999) == "9:59:59")
    }

    /// The tag sits before the time, in the mute button's width; only the GIF bar has it, and only
    /// the mute bar has the mute button.
    @Test func theGIFTagTakesTheMuteButtonsPlaceBeforeTheTime() throws {
        let tag = try #require(RecordingPanelLayout.tagFrame(of: .gif))
        let time = RecordingPanelLayout.timeFrame(of: .gif)
        #expect(tag.maxX <= time.minX)
        #expect(tag.width == RecordingPanelLayout.stopFrame(of: .gif).width)
        #expect(RecordingPanelLayout.muteFrame(of: .gif) == nil)
        #expect(RecordingPanelLayout.tagFrame(of: .plain) == nil)
        #expect(RecordingPanelLayout.muteFrame(of: .plain) == nil)
        #expect(RecordingPanelLayout.tagFrame(of: .mute) == nil)
        let label = ("GIF" as NSString).size(withAttributes: [.font: RecordingPanelLayout.tagFont]).width
        #expect(label + 2 * RecordingPanelLayout.tagPadding <= tag.width)
    }

    /// The mute button sits between the time and Stop, a button's size.
    @Test func theMuteButtonSitsBetweenTheTimeAndStop() throws {
        let mute = try #require(RecordingPanelLayout.muteFrame(of: .mute))
        #expect(RecordingPanelLayout.timeFrame(of: .mute).maxX <= mute.minX)
        #expect(mute.maxX == RecordingPanelLayout.stopFrame(of: .mute).minX - 6)
        #expect(mute.size == CGSize(width: 28, height: 28))
    }

    /// The symbol shows the state; the tool tip and the accessibility label say what a press does.
    @Test func theMuteButtonShowsItsStateAndSaysWhatAPressDoes() {
        let model = RecordingPanelModel()
        #expect(model.muteSymbol == "speaker.wave.2.fill")
        #expect(model.muteToolTip == "Mute the sound")
        #expect(model.muteAccessibilityLabel == "Mute")
        model.isMuted = true
        #expect(model.muteSymbol == "speaker.slash.fill")
        #expect(model.muteToolTip == "Unmute the sound")
        #expect(model.muteAccessibilityLabel == "Unmute")
    }

    /// TidyShot is inactive while it records, and AppKit shows an inactive app's tool tips only
    /// when the window allows it (design, Mute, Tool tips).
    @Test func thePanelShowsToolTipsWhileTidyShotIsInactive() {
        let panel = RecordingPanel(model: RecordingPanelModel())
        #expect(panel.allowsToolTipsWhenApplicationIsInactive)
        #expect(!panel.hidesOnDeactivate)
    }

    /// Stop and Cancel keep R1's places at the bar's right end.
    @Test(arguments: bars)
    func stopAndCancelEndTheBar(_ bar: RecordingPanelLayout.Bar) {
        let width = RecordingPanelLayout.size(of: bar).width
        let stop = RecordingPanelLayout.stopFrame(of: bar), cancel = RecordingPanelLayout.cancelFrame(of: bar)
        #expect(cancel.maxX == width - 8)
        #expect(stop.maxX == cancel.minX - 6)
        #expect(stop.size == CGSize(width: 28, height: 28))
        #expect(cancel.size == CGSize(width: 28, height: 28))
    }
}
