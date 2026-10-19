import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, and output together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()

    private(set) var isCapturing = false
    private(set) var lastCaptureURL: URL?

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }

    func start() {
        notifier.setUp()
        registerShortcuts()
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .captureFullscreen) { [weak self] in
            Task { await self?.captureFullscreen() }
        }
    }

    func captureFullscreen() async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            await save(result, appName: frontApp)
        }
    }

    func revealLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    /// Runs the engine. On failure posts a notification and returns nil.
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = []) async -> CaptureResult? {
        do {
            return try await engine.capture(target, options: CaptureOptions(showsCursor: settings.showsCursor), excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return nil
        }
    }

    /// Encode, copy to clipboard, save, play sound, notify. The clipboard copy happens before the
    /// folder is resolved so a cancelled folder chooser never loses the image.
    func save(_ result: CaptureResult, appName: String?) async {
        do {
            let png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
            if settings.copyImageToClipboard {
                Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
            }
            guard let folder = await saveLocation.ensureFolder() else {
                notifier.notifyError("Not saved: no folder was chosen.")
                return
            }
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: settings.nextCounter())
            let url = try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
            if settings.playSound {
                SoundPlayer.playShutter()
            }
            lastCaptureURL = url
            if settings.showNotification {
                notifier.notifySaved(fileURL: url)
            }
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
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
