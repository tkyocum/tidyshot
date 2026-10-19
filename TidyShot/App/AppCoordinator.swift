import AppKit
import Observation

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    private let permissionWindow = PermissionWindowController()

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }
}
