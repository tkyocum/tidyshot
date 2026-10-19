import AppKit
import Observation

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
/// Later tasks add capture methods here.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    func start() {
        NSLog("TidyShot started")
    }
}
