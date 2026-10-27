import Foundation
import Testing
@testable import TidyShot

/// `AppSettings.recordingOptions` is a snapshot of the Recording settings (design, Settings summary).
struct RecordingOptionsTests {
    func freshDefaults() -> UserDefaults {
        let name = "RecordingOptionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theR3FieldsDefaultToOffAndMedium() {
        let options = RecordingOptions(framesPerSecond: 30, retina: true, systemAudio: false, showsCursor: true)
        #expect(!options.clickHighlights)
        #expect(!options.webcamBubble)
        #expect(options.bubbleSize == .medium)
        #expect(options.cameraID == nil)
        #expect(options.cameraName == nil)
    }

    @Test func theSnapshotCarriesBothTogglesAndTheSizeButNoCamera() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.recordingClickHighlights = true
        settings.recordingWebcamBubble = true
        settings.recordingBubbleSize = .small
        settings.recordingCamera = "0x8020000005ac8514"
        settings.recordingCameraName = "Brio 500"
        let options = settings.recordingOptions
        #expect(options.clickHighlights)
        #expect(options.webcamBubble)
        #expect(options.bubbleSize == .small)
        #expect(options.cameraID == nil)
        #expect(options.cameraName == nil)
    }

    @Test func aLaterSettingsChangeLeavesTheSnapshotAsItWas() {
        let settings = AppSettings(defaults: freshDefaults())
        settings.recordingWebcamBubble = true
        settings.recordingBubbleSize = .large
        let snapshot = settings.recordingOptions

        settings.recordingClickHighlights = true
        settings.recordingWebcamBubble = false
        settings.recordingBubbleSize = .small
        settings.recordingFrameRate = 60

        #expect(!snapshot.clickHighlights)
        #expect(snapshot.webcamBubble)
        #expect(snapshot.bubbleSize == .large)
        #expect(snapshot.framesPerSecond == 30)
        #expect(settings.recordingOptions != snapshot)
    }

    @Test func anOptionsValueKeepsTheCameraSetOnIt() {
        var options = RecordingOptions(framesPerSecond: 30, retina: true, systemAudio: false, showsCursor: true)
        options.webcamBubble = true
        options.cameraID = "0x8020000005ac8514"
        options.cameraName = "Brio 500"
        #expect(options.cameraID == "0x8020000005ac8514")
        #expect(options.cameraName == "Brio 500")
        let copy = options
        options.cameraID = nil
        #expect(copy.cameraID == "0x8020000005ac8514")
    }

    @Test func theConfigurationIgnoresTheR3Fields() {
        let plain = RecordingOptions(framesPerSecond: 30, retina: true, systemAudio: false, showsCursor: true)
        var extras = plain
        extras.clickHighlights = true
        extras.webcamBubble = true
        extras.bubbleSize = .large
        extras.cameraID = "id"
        extras.cameraName = "name"
        let source = RecordingSource.display(RecordingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2))
        #expect(RecordingConfiguration.make(source, options: extras) == RecordingConfiguration.make(source, options: plain))
    }
}
