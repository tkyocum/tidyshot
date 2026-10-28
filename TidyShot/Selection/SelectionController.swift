import AppKit
import ScreenCaptureKit

/// Shows one SelectionWindow per screen and resolves to a Selection, or nil when cancelled.
/// On success the overlay stays up until `dismiss()` so the capture can exclude it by window.
final class SelectionController {
    private let engine: CaptureEngine
    private let settings: AppSettings
    /// The Quick Access cards on screen, left out of every capture and snapshot taken here.
    private let cardWindowNumbers: () -> Set<CGWindowID>
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
    /// All-in-One's caller, waiting for a choice (nil: cancelled).
    private var allInOneContinuation: CheckedContinuation<AllInOneChoice?, Never>?
    /// All-in-One: the window whose frame the current rect came from, for the Window button.
    private var pickedWindow: SCWindow?
    private var isIdle: Bool { continuation == nil && allInOneContinuation == nil }

    init(engine: CaptureEngine, settings: AppSettings, cardWindowNumbers: @escaping () -> Set<CGWindowID> = { [] }) {
        self.engine = engine
        self.settings = settings
        self.cardWindowNumbers = cardWindowNumbers
    }

    /// `preselect` (CoreGraphics global points) is used only in `.recording` mode: a URL command's
    /// rect, shown as the preset that a click inside records.
    func select(mode: SelectionMode, content: SCShareableContent, freeze: CaptureOptions? = nil,
                preselect: CGRect? = nil) async -> Selection? {
        // All-in-One resolves through `selectAllInOne`.
        guard isIdle, mode != .allInOne, !NSScreen.screens.isEmpty else { return nil }
        await present(mode: mode, content: content, freeze: freeze, preselect: preselect, armed: true)
        return await withCheckedContinuation { continuation = $0 }
    }

    /// All-in-One (spec 2.9): the overlay opens on `preselect` (CoreGraphics global points) when it
    /// is on a display, otherwise as Capture Scrolling's; it stays adjustable until a toolbar
    /// button, Return or a double-click picks the choice. On a choice the overlay stays up until
    /// `dismiss()`; `freeze` works as in area mode. With `armed` false (a URL command) the
    /// preselected rect takes Return and the double-click only after the user touches the overlay.
    func selectAllInOne(content: SCShareableContent, freeze: CaptureOptions? = nil,
                        preselect: CGRect? = nil, armed: Bool = true) async -> AllInOneChoice? {
        guard isIdle, !NSScreen.screens.isEmpty else { return nil }
        await present(mode: .allInOne, content: content, freeze: freeze, preselect: preselect, armed: armed)
        return await withCheckedContinuation { allInOneContinuation = $0 }
    }

    /// Shows one overlay window per screen in `mode`, with the freeze snapshots taken first and
    /// the loupe snapshots started after.
    private func present(mode: SelectionMode, content: SCShareableContent, freeze: CaptureOptions?,
                         preselect: CGRect?, armed: Bool) async {
        displays = content.displays
        self.mode = mode
        // Window picking is offered in every mode but area; area mode shows just the crosshair.
        picker = mode == .area ? nil : WindowPicker(content: content)

        // Freeze (area and All-in-One): every display is captured before any overlay window
        // appears, so the snapshot holds neither the dimming nor the crosshair. Window and
        // scrolling mode stay live (spec 2.9). A display that fails is simply absent and stays live.
        frozenSnapshots = [:]
        if mode == .area || mode == .allInOne, let freeze {
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
            view.onCancel = { [weak self] in Task { self?.cancel() } }
            if mode == .allInOne { configureAllInOne(view) }
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
        if mode == .allInOne, let preselect { placePreselected(preselect, armed: armed) }
        if mode == .recording, let preselect { placePreset(preselect) }
        updateHover(at: NSEvent.mouseLocation)
        if mode != .window {
            snapshotTask = Task { await takeSnapshots() }
        }
    }

    // MARK: All-in-One

    private func configureAllInOne(_ view: SelectionView) {
        view.isAspectLocked = settings.allInOneAspectLock
        // The Timer button's tooltip, `Capture this area after <n> seconds`, read when the overlay opens.
        view.timerSeconds = settings.selfTimerSeconds
        view.onAdjustRectSet = { [weak self, weak view] fromWindow in
            guard let self, let view else { return }
            allInOneRectSet(on: view, fromWindow: fromWindow)
        }
        view.onEmptyClick = { [weak self] in Task { self?.allInOneEmptyClick() } }
        view.onAllInOneAction = { [weak self] action, appKitRect in
            Task { self?.finishAllInOne(action, appKitRect: appKitRect) }
        }
        // One lock for every display's view, so it survives the selection moving to another display.
        view.onAspectLockChanged = { [weak self] locked in
            guard let self else { return }
            settings.allInOneAspectLock = locked
            for other in views { other.isAspectLocked = locked }
        }
    }

    /// The preselected rect on the screen holding its centre, as that view's adjustable rect.
    /// Not `armed` (a URL command), Return and the double-click wait for a press or a toolbar
    /// control (spec 2.9). Nothing when it is on no screen: the overlay opens with no rect.
    private func placePreselected(_ cgRect: CGRect, armed: Bool) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitRect = Geometry.appKitRect(fromCG: cgRect, primaryHeight: primaryHeight)
        guard let rect = SelectionAdjust.restored(appKitRect, displayFrames: windows.map(\.frame)),
              let index = windows.firstIndex(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
        else { return }
        let frame = windows[index].frame
        // A URL command's overlay takes the key from whatever app the user is typing in, so a
        // Return there must not capture before the user has touched the overlay.
        views[index].beginAdjusting(rect.offsetBy(dx: -frame.minX, dy: -frame.minY), fromWindow: false, armed: armed)
        windows[index].makeKey()
    }

    /// Record Screen's preset (a URL command's rect) on the view whose screen holds its centre,
    /// in that view's coordinates. Nothing when it is on no screen: the selection opens as the shortcut's.
    private func placePreset(_ cgRect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitRect = Geometry.appKitRect(fromCG: cgRect, primaryHeight: primaryHeight)
        let centre = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
        guard let index = windows.firstIndex(where: { $0.frame.contains(centre) }) else { return }
        let frame = windows[index].frame
        views[index].presetRect = appKitRect.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    /// A new rect on `view`: the other displays drop theirs, the window it came from is
    /// remembered (or forgotten), and its window becomes key so Return and the arrows reach it.
    private func allInOneRectSet(on view: SelectionView, fromWindow: Bool) {
        pickedWindow = fromWindow ? hoveredWindow : nil
        for other in views where other !== view {
            other.clearAdjustRect()
        }
        if let index = views.firstIndex(where: { $0 === view }) {
            windows[index].makeKey()
        }
    }

    /// A click that selected nothing: cancels while no display holds a rect, otherwise gives the
    /// key back to the display that does.
    private func allInOneEmptyClick() {
        if let index = views.firstIndex(where: { $0.adjustRect != nil }) {
            windows[index].makeKey()
        } else {
            cancel()
        }
    }

    /// A toolbar button, Return or a double-click. The rect is clipped to the display under its
    /// centre, as an area selection is.
    private func finishAllInOne(_ action: AllInOneAction, appKitRect: CGRect) {
        if action == .window {
            if let pickedWindow { resumeAllInOne(.window(pickedWindow)) }
            return
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard case let (rect, display)? = clippedToDisplay(Geometry.cgRect(fromAppKit: appKitRect, primaryHeight: primaryHeight)) else {
            resumeAllInOne(nil)
            return
        }
        switch action {
        case .capture: resumeAllInOne(.area(rect: rect, display: display))
        case .fullscreen: resumeAllInOne(.fullscreen(display))
        case .scrolling: resumeAllInOne(.scrolling(rect: rect, display: display))
        case .timer: resumeAllInOne(.timer(rect: rect, display: display))
        case .window, .cancel: resumeAllInOne(nil)
        }
    }

    /// Resumes All-in-One's caller. Cancel dismisses the overlay at once; a choice leaves it up.
    private func resumeAllInOne(_ choice: AllInOneChoice?) {
        guard let allInOneContinuation else { return }
        snapshotTask?.cancel()
        snapshotTask = nil
        self.allInOneContinuation = nil
        if choice == nil {
            dismiss()
        }
        allInOneContinuation.resume(returning: choice)
    }

    /// Escape, Cancel, or an empty click: whichever caller waits gets nil.
    private func cancel() {
        if allInOneContinuation != nil {
            resumeAllInOne(nil)
        } else {
            finish(nil)
        }
    }

    /// `cgRect` clipped to the display under its centre, or the first display; nil when nothing
    /// of it is on that display.
    private func clippedToDisplay(_ cgRect: CGRect) -> (CGRect, SCDisplay)? {
        let centre = CGPoint(x: cgRect.midX, y: cgRect.midY)
        guard let display = displays.first(where: { $0.frame.contains(centre) }) ?? displays.first else { return nil }
        let clipped = cgRect.intersection(display.frame)
        return clipped.isEmpty ? nil : (clipped, display)
    }

    /// One `engine.capture(.display(_:))` per display with whatever `overlayWindows()` excludes:
    /// the Quick Access cards, as no selection window exists yet. Failures are dropped. Sequential: a
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

    /// Our overlay windows and the Quick Access cards as ScreenCaptureKit sees them, for
    /// `excludingWindows`, through `OverlayWindowLookup` (by window number, with a short retry).
    /// A complete result is cached until `dismiss()`; it is reused while it covers every window
    /// wanted now, because a card can close (auto-close) or appear (Task 4's restore) meanwhile.
    func overlayWindows() async -> [SCWindow] {
        let wanted = Set(windows.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
            .union(cardWindowNumbers())
        if let cachedOverlayWindows, Set(cachedOverlayWindows.map(\.windowID)).isSuperset(of: wanted) {
            return cachedOverlayWindows
        }
        guard !wanted.isEmpty else { return [] }
        let found = await OverlayWindowLookup.windows(numbers: wanted, engine: engine)
        if found.count >= wanted.count { cachedOverlayWindows = found }
        return found
    }

    /// One screenshot per display with our overlay excluded, delivered to the view on that display.
    private func takeSnapshots() async {
        let pending = displays.filter { frozenSnapshots[$0.displayID] == nil }
        guard !pending.isEmpty else { return }
        let overlays = await overlayWindows()
        let selectionNumbers = Set(windows.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
        // A snapshot taken without every overlay excluded would show the dimming in the loupe; skip instead.
        guard selectionNumbers.isSubset(of: Set(overlays.map(\.windowID))) else { return }
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
        pickedWindow = nil
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

    /// A picked window: itself in window mode (and, as in window mode, in self-timer and recording mode); in
    /// scrolling mode its frame, as an area of the display under its centre. Nil cancels.
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
        guard case let (rect, display)? = clippedToDisplay(cgRect) else {
            finish(nil)
            return
        }
        finish(.area(rect: rect, display: display))
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
