import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Runs one scrolling capture on screen (spec 2.8, The session): the area frame, the panel and the
/// session, from the selection to the outcome. One run at a time, resolved through a
/// continuation, as `SelectionController` is.
final class ScrollCaptureController {
    private let engine: CaptureEngine
    private let settings: AppSettings
    private let permissionWindow = PermissionWindowController(.postEvent, copy: .autoScroll)
    private var session: ScrollCaptureSession?
    private var panel: ScrollCapturePanel?
    private var frameWindow: ScrollAreaFrameWindow?
    private var continuation: CheckedContinuation<ScrollCaptureOutcome, Never>?
    /// The area in AppKit global points and its screen's visible frame, for placing the panel.
    private var appKitArea: CGRect = .zero
    private var visibleFrame: CGRect = .zero

    init(engine: CaptureEngine, settings: AppSettings) {
        self.engine = engine
        self.settings = settings
    }

    /// A session is on screen. The Capture Scrolling shortcut then means Start or Done.
    var isRunning: Bool { session != nil }

    /// Shows the frame and the panel for `rect` (CoreGraphics global points, on `display`, as the
    /// selection returns it) and returns when the session ends. Nothing is written here: the
    /// caller saves the outcome's image. With `makesPanelKey` false (a URL command's rect) the
    /// panel is only ordered front: TidyShot is not active, and a key panel would take a Return
    /// typed in the frontmost app as Start, so Start needs a click. With `readyTimeout` (a URL
    /// command's rect) a session not started by then cancels itself.
    func run(rect: CGRect, display: SCDisplay, makesPanelKey: Bool = true,
             readyTimeout: Duration? = nil) async -> ScrollCaptureOutcome {
        guard session == nil else { return .cancelled }
        appKitArea = Geometry.appKitRect(fromCG: rect, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        visibleFrame = (CaptureEngine.screen(forDisplayID: display.displayID) ?? NSScreen.main ?? NSScreen.screens[0])
            .visibleFrame

        let frameWindow = ScrollAreaFrameWindow(area: appKitArea)
        frameWindow.orderFrontRegardless()

        // The source makes its filter at Start, when the panel and the frame are on screen, so
        // the application exclusion covers both.
        let source = ScrollFrameSource(rect: rect, display: display, engine: engine)
        // The panel can sit inside the area (ScrollPanelGeometry), and the pointer is on it after
        // Start; wheel events posted there would go to TidyShot's own panel. Over the panel
        // counts as outside the area, so the driver pauses until the pointer is over the content.
        var environment = AutoScrollEnvironment.live()
        let livePointer = environment.pointerLocation
        environment.pointerLocation = { [weak self] in
            if let panel = self?.panel, panel.frame.contains(NSEvent.mouseLocation) {
                return CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: 0)
            }
            return livePointer()
        }
        let session = ScrollCaptureSession(source: source, engine: ScrollStitchEngine(finder: OverlapFinder(scale: source.scale)),
                                           area: rect, scale: source.scale, colorSpace: source.colorSpace,
                                           autoScrollEnvironment: environment, prefersAutoScroll: settings.scrollingAutoScroll)
        session.onEnd = { [weak self] outcome in self?.close(with: outcome) }
        session.onAutoScrollChanged = { [settings] value in settings.scrollingAutoScroll = value }

        let panel = ScrollCapturePanel(session: session, onAllowAutoScroll: { [weak self] in self?.permissionWindow.show() })
        self.frameWindow = frameWindow
        self.session = session
        self.panel = panel
        layoutPanel()
        observePreview()
        // TidyShot is already active after the selection overlay: no activation here.
        if makesPanelKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        KeyboardShortcuts.enable(.cancelCapture)
        if let readyTimeout { session.cancelIfNotStarted(within: readyTimeout) }
        return await withCheckedContinuation { continuation = $0 }
    }

    /// The Capture Scrolling shortcut during a session: Start, then Done.
    func advance() {
        guard let session else { return }
        Task { await session.advance() }
    }

    /// Escape, from any app, while a session runs.
    func cancel() {
        guard let session else { return }
        Task { await session.cancel() }
    }

    private func close(with outcome: ScrollCaptureOutcome) {
        KeyboardShortcuts.disable(.cancelCapture)
        panel?.orderOut(nil)
        frameWindow?.orderOut(nil)
        panel = nil
        frameWindow = nil
        session = nil
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    /// Sizes the panel to the preview (220 to min(560, area height) points) and places it.
    private func layoutPanel() {
        guard let session, let panel else { return }
        let wanted = ScrollCaptureView.chromeHeight + ScrollCaptureView.previewHeight(for: session.preview)
        let size = CGSize(width: ScrollPanelGeometry.panelWidth,
                          height: ScrollPanelGeometry.height(wanted: wanted, areaHeight: appKitArea.height))
        let frame = ScrollPanelGeometry.frame(panelSize: size, area: appKitArea, visibleFrame: visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Lays the panel out again whenever the preview changes. Observation calls `onChange` once
    /// per registration, so it registers again, as `StatusMenuController.updateIcon` does.
    private func observePreview() {
        guard let session else { return }
        withObservationTracking {
            _ = session.preview
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.layoutPanel()
                self?.observePreview()
            }
        }
    }
}
