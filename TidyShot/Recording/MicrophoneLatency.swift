import CoreAudio
import Foundation

/// How far a recording's sound sits behind its clock, which the mute ladder adds after each muted
/// stretch (design, Microphone, Lag). The microphone lands later in the file by the input's own
/// latency, which ScreenCaptureKit does not compensate and which depends on the device; system
/// audio sits within 0.02 s.
nonisolated enum MicrophoneLatency {
    /// How the input is connected. Bluetooth inputs get the longer lag.
    enum Transport: Equatable, Sendable {
        case bluetooth
        case other
    }

    /// The lag with no microphone.
    static let noMicrophone: TimeInterval = 0.3
    /// The least lag for a Bluetooth input, or one whose properties cannot be read.
    private static let bluetoothOrUnread: TimeInterval = 0.6

    /// `max(0.3, 2 × reported + 0.05)` s, and at least 0.6 s for a Bluetooth input or when the
    /// properties could not be read (a nil `reported` or `transport`): doubt goes to the longer lag.
    static func lag(reported: TimeInterval?, transport: Transport?) -> TimeInterval {
        let lag = max(noMicrophone, 2 * (reported ?? 0) + 0.05)
        return reported != nil && transport == .other ? lag : max(lag, bluetoothOrUnread)
    }

    /// The input with CoreAudio UID `deviceUID` (`AVCaptureDevice.uniqueID`): its reported latency
    /// in seconds, the input scope's device latency, safety offset and buffer frame size plus the
    /// first input stream's latency over the nominal sample rate, and its transport. Each is nil
    /// when any read it needs fails, both when the device is not found.
    static func read(deviceUID: String) -> (reported: TimeInterval?, transport: Transport?) {
        guard let device = device(uid: deviceUID) else { return (nil, nil) }
        let transport = property(kAudioDevicePropertyTransportType, of: device, as: UInt32.self).map {
            $0 == kAudioDeviceTransportTypeBluetooth || $0 == kAudioDeviceTransportTypeBluetoothLE ? Transport.bluetooth : .other
        }
        return (reportedLatency(of: device), transport)
    }

    private static func reportedLatency(of device: AudioObjectID) -> TimeInterval? {
        let input = kAudioObjectPropertyScopeInput
        guard let latency = property(kAudioDevicePropertyLatency, of: device, scope: input, as: UInt32.self),
              let safetyOffset = property(kAudioDevicePropertySafetyOffset, of: device, scope: input, as: UInt32.self),
              let bufferFrames = property(kAudioDevicePropertyBufferFrameSize, of: device, scope: input, as: UInt32.self),
              let stream = firstInputStream(of: device),
              let streamLatency = property(kAudioStreamPropertyLatency, of: stream, as: UInt32.self),
              let sampleRate = property(kAudioDevicePropertyNominalSampleRate, of: device, as: Float64.self),
              sampleRate > 0 else { return nil }
        let frames = Double(latency) + Double(safetyOffset) + Double(bufferFrames) + Double(streamLatency)
        return frames / sampleRate
    }

    /// `kAudioHardwarePropertyTranslateUIDToDevice`: nil when no device has the UID.
    private static func device(uid: String) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var qualifier = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) { qualifier in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), qualifier, &size, &device)
        }
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func firstInputStream(of device: AudioObjectID) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioObjectID>.size) else { return nil }
        var streams = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown),
                                      count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr,
              let first = streams.first, first != kAudioObjectUnknown else { return nil }
        return first
    }

    /// One fixed-size property, or nil when the read fails.
    private static func property<Value>(_ selector: AudioObjectPropertySelector, of object: AudioObjectID,
                                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                        as type: Value.Type) -> Value? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<Value>.size)
        let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr,
              size == UInt32(MemoryLayout<Value>.size) else { return nil }
        return value.pointee
    }
}
