import AVFoundation

/// A microphone or a camera as the pop-ups list it: the device's `uniqueID` and `localizedName`.
nonisolated struct CaptureDeviceInfo: Equatable, Sendable {
    var uniqueID: String
    var name: String

    init(uniqueID: String, name: String) {
        self.uniqueID = uniqueID
        self.name = name
    }

    init(_ device: AVCaptureDevice) {
        self.init(uniqueID: device.uniqueID, name: device.localizedName)
    }
}

typealias MicrophoneDevice = CaptureDeviceInfo
typealias CameraDevice = CaptureDeviceInfo

/// TidyShot's access to a kind of capture device (`AVCaptureDevice.authorizationStatus(for:)`).
nonisolated enum CaptureAccess: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .denied
        }
    }
}

typealias MicrophoneAccess = CaptureAccess
typealias CameraAccess = CaptureAccess

extension AVCaptureDevice {
    /// Posted when a device is plugged in or unplugged. A SwiftUI `Picker` has no menu-will-open
    /// hook, so the device lists refresh on these.
    static let changeNotifications = [wasConnectedNotification, wasDisconnectedNotification]
}
