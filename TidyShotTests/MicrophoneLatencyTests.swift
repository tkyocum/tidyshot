import CoreAudio
import Foundation
import Testing
@testable import TidyShot

/// The mute lag (design, Microphone, Lag): `max(0.3, 2 × reported + 0.05)` s, at least 0.6 s for a
/// Bluetooth input or unreadable properties, and 0.3 s with no microphone.
struct MicrophoneLatencyTests {
    @Test func noMicrophoneIsThreeTenths() {
        #expect(MicrophoneLatency.noMicrophone == 0.3)
    }

    /// A USB input reports about 0.02 s, well under the floor.
    @Test func aLowLatencyInputGetsTheFloor() {
        #expect(MicrophoneLatency.lag(reported: 0.02, transport: .other) == 0.3)
        #expect(MicrophoneLatency.lag(reported: 0, transport: .other) == 0.3)
    }

    /// The iPhone input reports 6,000 frames, 0.125 s at 48 kHz, against its measured 0.13 s.
    @Test func sixThousandFramesAt48kHzIsThreeTenths() {
        let lag = MicrophoneLatency.lag(reported: 6_000 / 48_000, transport: .other)
        #expect(abs(lag - 0.30) < 1e-9)
    }

    @Test func aHighLatencyInputGetsTwiceItsLatencyAndAMargin() {
        #expect(abs(MicrophoneLatency.lag(reported: 0.3, transport: .other) - 0.65) < 1e-9)
        #expect(abs(MicrophoneLatency.lag(reported: 0.2, transport: .other) - 0.45) < 1e-9)
    }

    @Test func aBluetoothInputGetsAtLeastSixTenths() {
        #expect(MicrophoneLatency.lag(reported: 0.02, transport: .bluetooth) == 0.6)
        #expect(MicrophoneLatency.lag(reported: 0.125, transport: .bluetooth) == 0.6)
        #expect(abs(MicrophoneLatency.lag(reported: 0.3, transport: .bluetooth) - 0.65) < 1e-9)
    }

    /// Doubt goes to the longer lag: no latency, or no transport, counts as unread.
    @Test func unreadablePropertiesGetAtLeastSixTenths() {
        #expect(MicrophoneLatency.lag(reported: nil, transport: .other) == 0.6)
        #expect(MicrophoneLatency.lag(reported: nil, transport: .bluetooth) == 0.6)
        #expect(MicrophoneLatency.lag(reported: nil, transport: nil) == 0.6)
        #expect(MicrophoneLatency.lag(reported: 0.02, transport: nil) == 0.6)
        #expect(abs(MicrophoneLatency.lag(reported: 0.3, transport: nil) - 0.65) < 1e-9)
    }

    @Test func anUnknownDeviceReadsAsNothing() {
        let read = MicrophoneLatency.read(deviceUID: "TidyShotTests:no such input")
        #expect(read.reported == nil)
        #expect(read.transport == nil)
    }

    /// The test host is the sandboxed app, so this also shows the sandbox lets it read an input's
    /// latency. Every input has a buffer, so its reported latency is above 0.
    @Test(.enabled(if: defaultInputUID() != nil, "no audio input"))
    func theDefaultInputReadsALatencyAndATransport() throws {
        let uid = try #require(defaultInputUID())
        let read = MicrophoneLatency.read(deviceUID: uid)
        let reported = try #require(read.reported)
        #expect(reported > 0 && reported < 1)
        #expect(read.transport != nil)
    }
}

/// The default input's CoreAudio UID, which is its `AVCaptureDevice.uniqueID`; nil with no input.
nonisolated private func defaultInputUID() -> String? {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
          device != kAudioObjectUnknown else { return nil }
    address.mSelector = kAudioDevicePropertyDeviceUID
    var uid: Unmanaged<CFString>?
    size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
    return uid.takeRetainedValue() as String
}
