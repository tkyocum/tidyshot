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
    private var mode: SelectionMode = .area
    private var picker: WindowPicker?
    private var hoveredWindow: SCWindow?
    private var snapshotTask: Task<Void, Never>?
    private var cachedOverlayWindows: [SCWindow]?
    /// Freeze screen: one snapshot per display, taken before any overlay window existed. Cleared by `dismiss()`.
    private var frozenSnapshots: [CGDirectDisplayID: FrozenSnapshot] = [:]

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    func select(mode: SelectionMode, content: SCShareableContent, freeze: CaptureOptions? = nil) async -> Selection? {
        guard continuation == nil, !NSScreen.screens.isEmpty else { return nil }
        displays = content.displays
        self.mode = mode
        // Window picking is offered in window and scrolling mode; area mode shows just the crosshair.
        picker = mode == .area ? nil : WindowPicker(content: content)

        // Freeze (area mode only): every display is captured before any overlay window appears,
        // so the snapshot holds neither the dimming nor the crosshair. Window and scrolling mode
        // ignore it (spec 2.9). A display that fails is simply absent and stays live.
        frozenSnapshots = [:]
        if mode == .area, let freeze {
            frozenSnapshots = await captureFrozenSnapshots(options: freeze)
        }

        for screen in NSScreen.screens {
            let window = SelectionWindow(screen: screen)
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = mode
            if let frozen = frozenSnapshots[window.displayID] {
                view.snapshotScale = frozen.scale
                view.snapshot = frozen.image
                view.isFrozen = true
            }
            // Callbacks hop to the next run-loop turn so the view is never torn down inside its own event handler.
            view.onComplete = { [weak self] appKitRect in Task { self?.finishArea(appKitRect) } }
            view.onCancel = { [weak self] in Task { self?.finish(nil) } }
            view.onMouseMoved = { [weak self] globalPoint in self?.updateHover(at: globalPoint) }
            // Capture the hovered window now; a mouseMoved could change it before the Task runs.
            view.onPickWindow = { [weak self] in
                let picked = self?.hoveredWindow
                Task { self?.finishPick(picked) }
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
        if mode != .window {
            snapshotTask = Task { await takeSnapshots() }
        }

        return await withCheckedContinuation { continuation = $0 }
    }

    /// One `engine.capture(.display(_:))` per display with whatever `overlayWindows()` excludes
    /// (nothing yet; Task 3 adds the Quick Access cards). Failures are dropped. Sequential: a
    /// task group of main-actor children is rejected by the Swift 6 compiler here, because
    /// `SCDisplay` and `SCWindow` are not Sendable.
    private func captureFrozenSnapshots(options: CaptureOptions) async -> [CGDirectDisplayID: FrozenSnapshot] {
        let excluded = await overlayWindows()
        var found: [CGDirectDisplayID: FrozenSnapshot] = [:]
        for display in displays {
            guard let result = try? await engine.capture(.display(display), options: options,
                                                         excludingWindows: excluded) else { continue }
            found[display.displayID] = FrozenSnapshot(displayID: display.displayID, image: result.image,
                                                      scale: result.scale)
        }
        return found
    }

    /// The snapshot taken for `displayID` before the overlay appeared, valid until `dismiss()`.
    /// Nil when freeze was off, the mode does not freeze, or that display's snapshot failed.
    func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot? {
        frozenSnapshots[displayID]
    }

    /// Our overlay windows as ScreenCaptureKit sees them, for `excludingWindows`, through
    /// `OverlayWindowLookup` (by window number, so other TidyShot windows are unaffected, with a
    /// short retry). A complete result is cached until `dismiss()`, so the capture after selection
    /// does not look up again.
    func overlayWindows() async -> [SCWindow] {
        let wanted = Set(windows.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
        if let cachedOverlayWindows, cachedOverlayWindows.count >= wanted.count { return cachedOverlayWindows }
        guard !wanted.isEmpty else { return [] }
        let found = await OverlayWindowLookup.windows(numbers: wanted, engine: engine)
        if !wanted.isEmpty, found.count >= wanted.count { cachedOverlayWindows = found }
        return found
    }

    /// One screenshot per display with our overlay excluded, delivered to the view on that display.
    private func takeSnapshots() async {
        let pending = displays.filter { frozenSnapshots[$0.displayID] == nil }
        guard !pending.isEmpty else { return }
        let overlays = await overlayWindows()
        // A snapshot taken without every overlay excluded would show the dimming in the loupe; skip instead.
        guard overlays.count >= windows.count else { return }
        for display in pending {
            guard !Task.isCancelled else { return }
            guard let index = windows.firstIndex(where: { $0.displayID == display.displayID }) else { continue }
            guard let result = try? await engine.capture(.display(display),
                                                         options: CaptureOptions(showsCursor: false),
                                                         excludingWindows: overlays) else { continue }
            guard !Task.isCancelled, index < views.count else { return }
            views[index].snapshotScale = result.scale
            views[index].snapshot = result.image
        }
    }

    /// Removes the overlay. Safe to call more than once.
    func dismiss() {
        snapshotTask?.cancel()
        snapshotTask = nil
        cachedOverlayWindows = nil
        frozenSnapshots = [:]
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

    /// `globalPoint` is in AppKit global coordinates. No-op in area mode.
    private func updateHover(at globalPoint: CGPoint) {
        guard mode != .area else { return }
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

    /// A picked window: itself in window mode; in scrolling mode its frame, as an area of the
    /// display under its centre. Nil cancels.
    private func finishPick(_ window: SCWindow?) {
        guard let window else {
            finish(nil)
            return
        }
        if mode == .scrolling {
            finishArea(cgRect: window.frame)
        } else {
            finish(.window(window))
        }
    }

    private func finishArea(_ appKitRect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        finishArea(cgRect: Geometry.cgRect(fromAppKit: appKitRect, primaryHeight: primaryHeight))
    }

    /// `cgRect` (CoreGraphics global points) clipped to the display under its centre, or the
    /// first display. Cancels when nothing of it is on that display.
    private func finishArea(cgRect: CGRect) {
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
        snapshotTask?.cancel()
        snapshotTask = nil
        self.continuation = nil
        if selection == nil {
            dismiss()
        }
        continuation.resume(returning: selection)
    }
}
