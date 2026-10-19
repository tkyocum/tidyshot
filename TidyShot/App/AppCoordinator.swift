import AppKit
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    private let permissionWindow = PermissionWindowController()
    private(set) var isCapturing = false

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    func captureFullscreen() async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            debugOpen(result)
        }
    }

    /// Runs the engine and logs failures. Returns nil on failure.
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = []) async -> CaptureResult? {
        do {
            return try await engine.capture(target, options: CaptureOptions(showsCursor: false), excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Debug output: encode, write to the temp directory, open in the default viewer.
    private func debugOpen(_ result: CaptureResult) {
        do {
            let png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TidyShot-debug-\(Int(Date().timeIntervalSince1970))")
                .appendingPathExtension("png")
            try png.write(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("Debug write failed: \(error.localizedDescription)")
        }
    }

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            permissionWindow.show()
            return nil
        }
    }

    private func withCaptureLock(_ body: () async -> Void) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        await body()
    }

    /// The SCDisplay under an AppKit-global point, falling back to the first display.
    static func display(under appKitPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = Geometry.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
        return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
    }
}
