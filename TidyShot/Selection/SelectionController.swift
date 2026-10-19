import AppKit
import ScreenCaptureKit

/// Shows one SelectionWindow per screen and resolves to a Selection, or nil when cancelled.
/// On success the overlay stays up until `dismiss()` so the capture can exclude it by window.
final class SelectionController {
    private let engine: CaptureEngine
    private var windows: [SelectionWindow] = []
    private var views: [SelectionView] = []
    private var continuation: CheckedContinuation<Selection?, Never>?
    private var displays: [SCDisplay] = []
    private var picker: WindowPicker?
    private var hoveredWindow: SCWindow?

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    func select(mode: SelectionMode, content: SCShareableContent) async -> Selection? {
        guard continuation == nil, !NSScreen.screens.isEmpty else { return nil }
        displays = content.displays
        picker = WindowPicker(content: content)

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            // Callbacks hop to the next run-loop turn so the view is never torn down inside its own event handler.
            view.onComplete = { [weak self] appKitRect in Task { self?.finishArea(appKitRect) } }
            view.onCancel = { [weak self] in Task { self?.finish(nil) } }
            view.onMouseMoved = { [weak self] globalPoint in self?.updateHover(at: globalPoint) }
            // Capture the hovered window now; a mouseMoved could change it before the Task runs.
            view.onPickWindow = { [weak self] in
                let picked = self?.hoveredWindow
                Task { self?.finish(picked.map(Selection.window)) }
            }
            window.contentView = view
            window.makeFirstResponder(view)
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
            views.append(view)
        }

        // Called from a global hotkey while another app is active; cooperative activation can refuse
        // a plain activate(), and without activation the overlay never becomes key and Escape is lost.
        // activate(ignoringOtherApps:) is marked for future deprecation in the SDK; it compiles without a warning today.
        NSApplication.shared.activate(ignoringOtherApps: true)
        windows.first { $0.frame.contains(NSEvent.mouseLocation) }?.makeKey()
        updateHover(at: NSEvent.mouseLocation)

        return await withCheckedContinuation { continuation = $0 }
    }

    /// Our overlay windows as ScreenCaptureKit sees them, for `excludingWindows`. Matches by window
    /// number so other TidyShot windows are unaffected. Retries briefly because ScreenCaptureKit can
    /// lag the window server. Returns whatever was found after the last attempt.
    func overlayWindows() async -> [SCWindow] {
        let wanted = Set(windows.map { CGWindowID($0.windowNumber) })
        var found: [SCWindow] = []
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let fresh = try? await engine.shareableContent() else { continue }
            found = fresh.windows.filter { wanted.contains($0.windowID) }
            if found.count >= wanted.count { break }
        }
        if found.count < wanted.count {
            NSLog("Overlay exclusion incomplete: found \(found.count) of \(wanted.count) overlay windows")
        }
        return found
    }

    /// Removes the overlay. Safe to call more than once.
    func dismiss() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows = []
        views = []
        displays = []
        picker = nil
        hoveredWindow = nil
    }

    /// `globalPoint` is in AppKit global coordinates.
    private func updateHover(at globalPoint: CGPoint) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = Geometry.cgPoint(fromAppKit: globalPoint, primaryHeight: primaryHeight)
        hoveredWindow = picker?.window(at: cgPoint)

        let appKitFrame = hoveredWindow.map { Geometry.appKitRect(fromCG: $0.frame, primaryHeight: primaryHeight) }
        for (window, view) in zip(windows, views) {
            guard let appKitFrame, window.frame.intersects(appKitFrame) else {
                view.highlightedRect = nil
                continue
            }
            let inWindow = window.convertFromScreen(appKitFrame)
            view.highlightedRect = view.convert(inWindow, from: nil).intersection(view.bounds)
        }
    }

    private func finishArea(_ appKitRect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgRect = Geometry.cgRect(fromAppKit: appKitRect, primaryHeight: primaryHeight)
        let centre = CGPoint(x: cgRect.midX, y: cgRect.midY)
        guard let display = displays.first(where: { $0.frame.contains(centre) }) ?? displays.first else {
            finish(nil)
            return
        }
        let clipped = cgRect.intersection(display.frame)
        guard !clipped.isEmpty else {
            finish(nil)
            return
        }
        finish(.area(rect: clipped, display: display))
    }

    /// Resumes the waiting caller. Cancel dismisses the overlay at once; success leaves it up.
    private func finish(_ selection: Selection?) {
        guard let continuation else { return }
        self.continuation = nil
        if selection == nil {
            dismiss()
        }
        continuation.resume(returning: selection)
    }
}
