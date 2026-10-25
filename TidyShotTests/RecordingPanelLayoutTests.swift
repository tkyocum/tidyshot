import AppKit
import Testing
@testable import TidyShot

/// The recording bar's layout (design, Mute, Bar): each bar laid out with a time past an hour.
struct RecordingPanelLayoutTests {
    nonisolated static let bars: [RecordingPanelLayout.Bar] = [.plain, .mute, .gif]

    func frames(of bar: RecordingPanelLayout.Bar) -> [CGRect] {
        [RecordingPanelLayout.tagFrame(of: bar), RecordingPanelLayout.timeFrame(of: bar), RecordingPanelLayout.muteFrame(of: bar),
         RecordingPanelLayout.stopFrame(of: bar), RecordingPanelLayout.cancelFrame(of: bar)].compactMap { $0 }
    }

    @Test func theBarsAre172And208PointsWide() {
        #expect(RecordingPanelLayout.size(of: .plain) == CGSize(width: 172, height: 44))
        #expect(RecordingPanelLayout.size(of: .mute) == CGSize(width: 208, height: 44))
        #expect(RecordingPanelLayout.size(of: .gif) == CGSize(width: 208, height: 44))
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
    @Test(arguments: [RecordingPanelLayout.Bar.plain, .mute, .gif])
    func stopAndCancelEndTheBar(_ bar: RecordingPanelLayout.Bar) {
        let width = RecordingPanelLayout.size(of: bar).width
        let stop = RecordingPanelLayout.stopFrame(of: bar), cancel = RecordingPanelLayout.cancelFrame(of: bar)
        #expect(cancel.maxX == width - 8)
        #expect(stop.maxX == cancel.minX - 6)
        #expect(stop.size == CGSize(width: 28, height: 28))
        #expect(cancel.size == CGSize(width: 28, height: 28))
    }
}
