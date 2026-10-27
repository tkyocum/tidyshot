import AVFoundation

/// A camera as `Camera` lists it: the device's `uniqueID` and `localizedName`.
nonisolated struct CameraDevice: Equatable, Sendable {
    var uniqueID: String
    var name: String
}

/// TidyShot's camera access (`AVCaptureDevice.authorizationStatus(for: .video)`).
nonisolated enum CameraAccess: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

/// The cameras, the preferred camera and the access, live on `AVCaptureDevice` and faked in tests.
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

    /// Posted when a camera is plugged in or unplugged. The pop-up's list refreshes on these.
    static let changeNotifications = [AVCaptureDevice.wasConnectedNotification,
                                      AVCaptureDevice.wasDisconnectedNotification]

    func list() -> [CameraDevice] {
        discovered().map(Self.device)
    }

    /// `systemPreferredCamera` when it is one of the listed types, else the first listed camera,
    /// else nil (plan Gap 12). C1 read `systemPreferredCamera` as nil at first while cameras
    /// were listed.
    func preferred() -> CameraDevice? {
        if let system = AVCaptureDevice.systemPreferredCamera, Self.deviceTypes.contains(system.deviceType) {
            return Self.device(system)
        }
        return discovered().first.map(Self.device)
    }

    func access() -> CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    private func discovered() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: Self.deviceTypes, mediaType: .video, position: .unspecified).devices
    }

    private static func device(_ device: AVCaptureDevice) -> CameraDevice {
        CameraDevice(uniqueID: device.uniqueID, name: device.localizedName)
    }
}
