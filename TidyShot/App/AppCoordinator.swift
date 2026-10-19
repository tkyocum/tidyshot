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
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)

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
        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in
            Task { await self?.captureArea() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in
            Task { await self?.captureWindow() }
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

    func captureArea() async {
        await runSelection(mode: .area)
    }

    func captureWindow() async {
        await runSelection(mode: .window)
    }

    /// Show the overlay, capture with the overlay excluded, dismiss, then save.
    private func runSelection(mode: SelectionMode) async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: mode, content: content) else { return }

            let result: CaptureResult?
            let appName: String?
            switch selection {
            case .area(let rect, let display):
                let overlays = await selector.overlayWindows()
                result = await capture(.area(rect: rect, display: display), excludingWindows: overlays)
                appName = frontApp
            case .window(let window):
                result = await capture(.window(window))
                appName = window.owningApplication?.applicationName
            }
            selector.dismiss()

            if let result {
                await save(result, appName: appName)
            }
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
    /// folder is resolved, and is used as a fallback whenever the file cannot be written (cancelled
    /// folder chooser or write failure), so a capture is never dropped.
    func save(_ result: CaptureResult, appName: String?) async {
        let png: Data
        do {
            png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return
        }
        var copiedToClipboard = settings.copyImageToClipboard
        if copiedToClipboard {
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
        }
        do {
            guard let folder = await saveLocation.ensureFolder() else {
                if !copiedToClipboard {
                    Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
                    copiedToClipboard = true
                }
                notifier.notifyError("Not saved: no folder was chosen. The image is on the clipboard.")
                return
            }
            let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: counter)
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
            if !copiedToClipboard {
                Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
                copiedToClipboard = true
            }
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.")
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
