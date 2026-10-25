import AVFoundation

/// An audio input as `Microphone` lists it: the device's `uniqueID` and `localizedName`.
nonisolated struct MicrophoneDevice: Equatable, Sendable {
    var uniqueID: String
    var name: String
}

/// TidyShot's microphone access (`AVCaptureDevice.authorizationStatus(for: .audio)`).
nonisolated enum MicrophoneAccess: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

/// The audio inputs, the default input and the access, live on `AVCaptureDevice` and faked in
/// tests (plan Gap 6).
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
    /// Posted when an input is plugged in or unplugged. A SwiftUI `Picker` has no menu-will-open
    /// hook, so the list refreshes on these.
    static let changeNotifications = [AVCaptureDevice.wasConnectedNotification,
                                      AVCaptureDevice.wasDisconnectedNotification]

    func list() -> [MicrophoneDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map(Self.device)
    }

    func defaultDevice() -> MicrophoneDevice? {
        AVCaptureDevice.default(for: .audio).map(Self.device)
    }

    func access() -> MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    private static func device(_ device: AVCaptureDevice) -> MicrophoneDevice {
        MicrophoneDevice(uniqueID: device.uniqueID, name: device.localizedName)
    }
}
