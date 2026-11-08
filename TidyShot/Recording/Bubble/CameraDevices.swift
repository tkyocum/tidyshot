import AVFoundation

/// The cameras, the preferred camera and the access, live on `AVCaptureDevice` and faked in tests.
/// The types are `CaptureDeviceInfo` and `CaptureAccess`, shared with the microphone
/// (CaptureDevices.swift).
protocol CameraDevices: AnyObject {
    func list() -> [CameraDevice]
    /// Nil when there is no camera at all.
    func preferred() -> CameraDevice?
    func access() -> CameraAccess
    /// Shows the system prompt when the access is `notDetermined`. True when it is granted.
    func requestAccess() async -> Bool
}

/// The cameras from the discovery session C1 listed (design, Webcam bubble, Settings; G3).
final class LiveCameraDevices: CameraDevices {
    /// The built-in camera, USB cameras and Continuity Camera. Desk View (`.deskViewCamera`) is
    /// left out, as a downward view is not a face.
    static let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]

    static let changeNotifications = AVCaptureDevice.changeNotifications

    func list() -> [CameraDevice] {
        discovered().map(CaptureDeviceInfo.init)
    }

    /// `systemPreferredCamera` when it is one of the listed types, else the first listed camera,
    /// else nil (plan Gap 12). C1 read `systemPreferredCamera` as nil at first while cameras
    /// were listed.
    func preferred() -> CameraDevice? {
        if let system = AVCaptureDevice.systemPreferredCamera, Self.deviceTypes.contains(system.deviceType) {
            return CaptureDeviceInfo(system)
        }
        return discovered().first.map(CaptureDeviceInfo.init)
    }

    func access() -> CameraAccess {
        CaptureAccess(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    private func discovered() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: Self.deviceTypes, mediaType: .video, position: .unspecified).devices
    }
}
