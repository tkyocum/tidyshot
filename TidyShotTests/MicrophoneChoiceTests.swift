import Foundation
import Testing
@testable import TidyShot

/// The `Microphone` setting and its resolution at the start (design, Microphone, Setting,
/// Permission and At the start), over a device list and an access the tests choose.
struct MicrophoneChoiceTests {
    let builtIn = MicrophoneDevice(uniqueID: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
    let rode = MicrophoneDevice(uniqueID: "AppleUSBAudioEngine:RODE:AI-1:1", name: "RODE AI-1")
    let brio = MicrophoneDevice(uniqueID: "AppleUSBAudioEngine:Logitech:Brio 500:2", name: "Brio 500")

    var devices: [MicrophoneDevice] { [builtIn, rode] }
    /// The RODE AI-1, stored and then unplugged.
    var missingRode: MicrophoneChoice.Stored { .device(id: rode.uniqueID, name: "RODE AI-1") }

    // MARK: Stored values

    @Test func storedValuesParseFromTheTwoSettings() {
        #expect(MicrophoneChoice.Stored(value: "", name: "") == .off)
        #expect(MicrophoneChoice.Stored(value: "", name: "RODE AI-1") == .off)
        #expect(MicrophoneChoice.Stored(value: "default", name: "") == .systemDefault)
        #expect(MicrophoneChoice.Stored(value: rode.uniqueID, name: "RODE AI-1") == .device(id: rode.uniqueID, name: "RODE AI-1"))
        #expect(MicrophoneChoice.Stored(value: rode.uniqueID, name: "") == .device(id: rode.uniqueID, name: ""))
    }

    // MARK: Resolve

    @Test(arguments: [MicrophoneAccess.authorized, .denied, .restricted, .notDetermined])
    func offRecordsNoMicrophoneAndPostsNothing(_ access: MicrophoneAccess) {
        let resolution = MicrophoneChoice.resolve(stored: .off, devices: devices, defaultDevice: builtIn, access: access)
        #expect(resolution == MicrophoneChoice.Resolution(device: nil, note: nil))
    }

    @Test func systemDefaultRecordsTheDefaultInput() {
        let resolution = MicrophoneChoice.resolve(stored: .systemDefault, devices: devices, defaultDevice: builtIn,
                                                  access: .authorized)
        #expect(resolution == MicrophoneChoice.Resolution(device: builtIn, note: nil))
    }

    @Test func aPresentDeviceRecordsThatDevice() {
        let resolution = MicrophoneChoice.resolve(stored: .device(id: rode.uniqueID, name: "RODE AI-1"), devices: devices,
                                                  defaultDevice: builtIn, access: .authorized)
        #expect(resolution == MicrophoneChoice.Resolution(device: rode, note: nil))
    }

    @Test func aMissingDeviceRecordsTheDefaultInputAndSaysSo() {
        let resolution = MicrophoneChoice.resolve(stored: missingRode, devices: [builtIn], defaultDevice: builtIn,
                                                  access: .authorized)
        #expect(resolution.device == builtIn)
        #expect(resolution.note == RecordingNotice(title: "Recorded with MacBook Pro Microphone",
                                                   body: "RODE AI-1 is not connected."))
        #expect(MicrophoneChoice.entries(stored: missingRode, devices: [builtIn]).last
                == MicrophoneChoice.Entry(tag: rode.uniqueID, title: "RODE AI-1 (not connected)"))
    }

    @Test func aMissingDeviceWithNoStoredNameIsAnUnknownMicrophone() {
        let stored = MicrophoneChoice.Stored.device(id: rode.uniqueID, name: "")
        let resolution = MicrophoneChoice.resolve(stored: stored, devices: [builtIn], defaultDevice: builtIn,
                                                  access: .authorized)
        #expect(resolution.device == builtIn)
        #expect(resolution.note == RecordingNotice(title: "Recorded with MacBook Pro Microphone",
                                                   body: "Unknown microphone is not connected."))
        #expect(MicrophoneChoice.entries(stored: stored, devices: [builtIn]).last
                == MicrophoneChoice.Entry(tag: rode.uniqueID, title: "Unknown microphone (not connected)"))
    }

    @Test func theStoredDefaultInputCountsAsPresentWhenTheListLeavesItOut() {
        let resolution = MicrophoneChoice.resolve(stored: .device(id: builtIn.uniqueID, name: "MacBook Pro Microphone"),
                                                  devices: [rode], defaultDevice: builtIn, access: .authorized)
        #expect(resolution == MicrophoneChoice.Resolution(device: builtIn, note: nil))
    }

    @Test func systemDefaultWithNoInputRecordsNoMicrophone() {
        let resolution = MicrophoneChoice.resolve(stored: .systemDefault, devices: [], defaultDevice: nil,
                                                  access: .authorized)
        #expect(resolution == MicrophoneChoice.Resolution(
            device: nil, note: RecordingNotice(title: "Recorded without the microphone", body: "No microphone is connected.")))
    }

    @Test func aMissingDeviceWithNoInputRecordsNoMicrophoneAndNamesIt() {
        let resolution = MicrophoneChoice.resolve(stored: missingRode, devices: [], defaultDevice: nil, access: .authorized)
        #expect(resolution == MicrophoneChoice.Resolution(
            device: nil, note: RecordingNotice(title: "Recorded without the microphone", body: "RODE AI-1 is not connected.")))
    }

    @Test func authorizedPassesTheDevice() {
        let resolution = MicrophoneChoice.resolve(stored: .device(id: brio.uniqueID, name: "Brio 500"),
                                                  devices: [builtIn, brio], defaultDevice: builtIn, access: .authorized)
        #expect(resolution.device?.uniqueID == brio.uniqueID)
        #expect(resolution.note == nil)
    }

    /// The start path asks, then reads the access again, so a granted prompt reaches `resolve`
    /// as `.authorized`.
    @Test func notDeterminedThenGrantedPassesTheDevice() async {
        let microphones = FakeMicrophoneDevices(devices: devices, defaultInput: builtIn, access: .notDetermined, grants: true)
        let stored = MicrophoneChoice.Stored.device(id: rode.uniqueID, name: "RODE AI-1")
        #expect(MicrophoneChoice.asksForAccess(stored, format: .mp4, access: microphones.access()))
        _ = await microphones.requestAccess()
        let resolution = MicrophoneChoice.resolve(stored: stored, devices: microphones.list(),
                                                  defaultDevice: microphones.defaultDevice(), access: microphones.access())
        #expect(resolution == MicrophoneChoice.Resolution(device: rode, note: nil))
    }

    @Test func aRefusedPromptPassesNoDeviceAndGivesTheAccessNote() async {
        let microphones = FakeMicrophoneDevices(devices: devices, defaultInput: builtIn, access: .notDetermined, grants: false)
        let stored = MicrophoneChoice.Stored.device(id: rode.uniqueID, name: "RODE AI-1")
        _ = await microphones.requestAccess()
        let resolution = MicrophoneChoice.resolve(stored: stored, devices: microphones.list(),
                                                  defaultDevice: microphones.defaultDevice(), access: microphones.access())
        #expect(resolution == MicrophoneChoice.Resolution(device: nil, note: accessNote))
    }

    /// The setting is kept: `resolve` gives a device and a note, never a new stored value.
    @Test(arguments: [MicrophoneAccess.denied, .restricted, .notDetermined])
    func accessNotAuthorizedPassesNoDeviceAndGivesTheAccessNote(_ access: MicrophoneAccess) {
        for stored in [MicrophoneChoice.Stored.systemDefault, .device(id: rode.uniqueID, name: "RODE AI-1"), missingRode] {
            let resolution = MicrophoneChoice.resolve(stored: stored, devices: devices, defaultDevice: builtIn, access: access)
            #expect(resolution == MicrophoneChoice.Resolution(device: nil, note: accessNote))
        }
        // Not authorized and no input: the access note, not the missing input's.
        let resolution = MicrophoneChoice.resolve(stored: missingRode, devices: [], defaultDevice: nil, access: access)
        #expect(resolution.note == accessNote)
    }

    var accessNote: RecordingNotice {
        RecordingNotice(title: "Recorded without the microphone", body: "Microphone access is off for TidyShot.")
    }

    // MARK: A GIF start

    @Test func aGIFStartTreatsAnyStoredMicrophoneAsOff() {
        for stored in [MicrophoneChoice.Stored.device(id: rode.uniqueID, name: "RODE AI-1"), missingRode, .systemDefault, .off] {
            #expect(MicrophoneChoice.forRecording(stored, format: .gif) == .off)
        }
    }

    @Test func anMP4StartKeepsTheStoredChoice() {
        for stored in [MicrophoneChoice.Stored.device(id: rode.uniqueID, name: "RODE AI-1"), .systemDefault, .off] {
            #expect(MicrophoneChoice.forRecording(stored, format: .mp4) == stored)
        }
    }

    @Test(arguments: [MicrophoneAccess.denied, .authorized])
    func aGIFStartWithAMissingDeviceRecordsNoMicrophoneAndPostsNothing(_ access: MicrophoneAccess) {
        let stored = MicrophoneChoice.forRecording(missingRode, format: .gif)
        #expect(MicrophoneChoice.resolve(stored: stored, devices: [builtIn], defaultDevice: builtIn, access: access)
                == MicrophoneChoice.Resolution(device: nil, note: nil))
        // No input at all.
        #expect(MicrophoneChoice.resolve(stored: stored, devices: [], defaultDevice: nil, access: access)
                == MicrophoneChoice.Resolution(device: nil, note: nil))
    }

    @Test func aGIFStartWithAPresentDeviceOrDefaultRecordsNoMicrophone() {
        for stored in [MicrophoneChoice.Stored.device(id: rode.uniqueID, name: "RODE AI-1"), .systemDefault] {
            for access in [MicrophoneAccess.denied, .authorized] {
                #expect(MicrophoneChoice.resolve(stored: MicrophoneChoice.forRecording(stored, format: .gif),
                                                 devices: devices, defaultDevice: builtIn, access: access)
                        == MicrophoneChoice.Resolution(device: nil, note: nil))
            }
        }
    }

    @Test func onlyAnMP4WithAMicrophoneSetAsksWhileAccessIsNotDetermined() {
        let rodeSet = MicrophoneChoice.Stored.device(id: rode.uniqueID, name: "RODE AI-1")
        #expect(!MicrophoneChoice.asksForAccess(rodeSet, format: .gif, access: .notDetermined))
        #expect(!MicrophoneChoice.asksForAccess(.systemDefault, format: .gif, access: .notDetermined))
        #expect(!MicrophoneChoice.asksForAccess(.off, format: .mp4, access: .notDetermined))
        #expect(MicrophoneChoice.asksForAccess(rodeSet, format: .mp4, access: .notDetermined))
        #expect(MicrophoneChoice.asksForAccess(missingRode, format: .mp4, access: .notDetermined))
        #expect(MicrophoneChoice.asksForAccess(.systemDefault, format: .mp4, access: .notDetermined))
        for access in [MicrophoneAccess.authorized, .denied, .restricted] {
            #expect(!MicrophoneChoice.asksForAccess(rodeSet, format: .mp4, access: access))
        }
    }

    // MARK: The pop-up

    @Test func theEntriesAreOffSystemDefaultThenEachInput() {
        let expected = [
            MicrophoneChoice.Entry(tag: "", title: "Off"),
            MicrophoneChoice.Entry(tag: "default", title: "System Default"),
            MicrophoneChoice.Entry(tag: builtIn.uniqueID, title: "MacBook Pro Microphone"),
            MicrophoneChoice.Entry(tag: rode.uniqueID, title: "RODE AI-1"),
        ]
        #expect(MicrophoneChoice.entries(stored: .off, devices: devices) == expected)
        #expect(MicrophoneChoice.entries(stored: .systemDefault, devices: devices) == expected)
        // A present stored device is listed once, under its own name.
        #expect(MicrophoneChoice.entries(stored: .device(id: rode.uniqueID, name: "Old name"), devices: devices) == expected)
    }

    @Test func aMissingStoredDeviceStaysTheSelectionAfterTheInputs() {
        let entries = MicrophoneChoice.entries(stored: missingRode, devices: [builtIn])
        #expect(entries == [
            MicrophoneChoice.Entry(tag: "", title: "Off"),
            MicrophoneChoice.Entry(tag: "default", title: "System Default"),
            MicrophoneChoice.Entry(tag: builtIn.uniqueID, title: "MacBook Pro Microphone"),
            MicrophoneChoice.Entry(tag: rode.uniqueID, title: "RODE AI-1 (not connected)"),
        ])
        // Plugging it in again restores it.
        #expect(MicrophoneChoice.entries(stored: missingRode, devices: devices).last
                == MicrophoneChoice.Entry(tag: rode.uniqueID, title: "RODE AI-1"))
    }

    @Test func theAccessNoteShowsOnlyWithAMicrophoneSetAndAccessDeniedOrRestricted() {
        for access in [MicrophoneAccess.authorized, .denied, .restricted, .notDetermined] {
            #expect(!MicrophoneChoice.showsAccessNote(stored: .off, access: access))
            let blocked = access == .denied || access == .restricted
            #expect(MicrophoneChoice.showsAccessNote(stored: .systemDefault, access: access) == blocked)
            #expect(MicrophoneChoice.showsAccessNote(stored: missingRode, access: access) == blocked)
        }
        #expect(MicrophoneChoice.accessOffText == "Microphone access is off for TidyShot.")
        #expect(MicrophoneChoice.privacySettingsURL.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }
}
