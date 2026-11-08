import AVFoundation

/// The audio inputs, the default input and the access, live on `AVCaptureDevice` and faked in
/// tests (plan Gap 6). The types are `CaptureDeviceInfo` and `CaptureAccess`, shared with the
/// camera (CaptureDevices.swift).
protocol MicrophoneDevices: AnyObject {
    func list() -> [MicrophoneDevice]
    /// Nil when there is no input at all.
    func defaultDevice() -> MicrophoneDevice?
    func access() -> MicrophoneAccess
    /// Shows the system prompt when the access is `notDetermined`. True when it is granted.
    func requestAccess() async -> Bool
}

/// The inputs from the discovery session the probes used (design, Probes, Microphone, Inputs).
final class LiveMicrophoneDevices: MicrophoneDevices {
    static let changeNotifications = AVCaptureDevice.changeNotifications

    func list() -> [MicrophoneDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map(CaptureDeviceInfo.init)
    }

    func defaultDevice() -> MicrophoneDevice? {
        AVCaptureDevice.default(for: .audio).map(CaptureDeviceInfo.init)
    }

    func access() -> MicrophoneAccess {
        CaptureAccess(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
