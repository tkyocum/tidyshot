import AppKit
import ScreenCaptureKit

// Image capture flows: the entry points behind the status menu, the shortcuts and the URL commands, ending in save(_:intent:). Their state is declared in AppCoordinator.swift.
extension AppCoordinator {
    func captureFullscreen(intent: CaptureIntent = .standard) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            guard let display = captureSource.displayUnderPointer(in: content.displays) else { return }
            guard let result = await capture(.display(display), excludingWindows: await cardWindows()) else { return }
            await save(result, intent: intent)
        }
    }

    func captureArea(intent: CaptureIntent = .standard) async {
        await runSelection(mode: .area, intent: intent)
    }

    /// A URL command's overlay opens disarmed (spec 2.9): one click picks a window, so the
    /// second click of a double-click must not pick it for the sender.
    func captureWindow(intent: CaptureIntent = .standard, fromURLCommand: Bool = false) async {
        await runSelection(mode: .window, intent: intent, armed: !fromURLCommand)
    }

    /// All-in-One (spec 2.9): one adjustable selection whose toolbar picks the capture. Opens on
    /// `preselect` (CoreGraphics global points; a URL command's rect, Task 5) or else the last
    /// area, when it is on a connected display. Capture and Window are taken while the overlay is
    /// up, with the overlay and the cards excluded, so the pointer is never in them; Fullscreen
    /// dismisses the overlay first and follows Show cursor, as Capture Fullscreen does. Each ends
    /// in `save(_:intent:)`.
    func captureAllInOne(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil,
                         fromURLCommand: Bool = false) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            // Freeze applies to Capture; the snapshots follow the cursor setting, as in area mode.
            let freeze = settings.freezeScreen ? CaptureOptions(settings: settings, duringSelection: false) : nil
            // A URL command's start rect (its own or the previous area) opens disarmed: the
            // overlay takes the key, and a Return typed meanwhile must not capture it for the sender.
            guard let choice = await selector.selectAllInOne(content: content, freeze: freeze,
                                                             preselect: preselect?.rect ?? settings.lastAreaRect?.cgRect,
                                                             armed: !fromURLCommand)
            else { return }

            let result: CaptureResult?
            switch choice {
            case .area(let rect, let display):
                result = await areaResult(rect: rect, display: display)
            case .window(let window):
                result = await capture(.window(window), duringSelection: true)
            case .fullscreen(let display):
                // As Capture Fullscreen: the overlay goes first and the pointer follows Show cursor.
                // Its windows stay excluded in case the window server has not dropped them yet; the
                // arrow replaces the crosshair the overlay set, which is not the user's pointer.
                let overlays = await selector.overlayWindows()
                selector.dismiss()
                NSCursor.arrow.set()
                result = await capture(.display(display), excludingWindows: overlays)
            case .scrolling(let rect, let display):
                // As Capture Scrolling: the covers would stay up for the whole session.
                covers.hide(for: .capture)
                await runScrolling(rect: rect, display: display, intent: intent)
                return
            case .timer(let rect, let display):
                // Every All-in-One area kind stores the previous area (spec 2.9). `runSelfTimer`
                // dismisses the overlay; the countdown ends in its own `save(_:intent:)`.
                settings.lastAreaRect = StoredRect(rect)
                await runSelfTimer(.area(rect: rect, display: display), intent: intent)
                return
            }
            selector.dismiss()
            if let result {
                await save(result, intent: intent)
            }
        }
    }

    /// Capture Scrolling: select an area or a window's frame, run the scrolling session, and save
    /// the stitched image like any capture. During a session the shortcut is Start, then Done. A URL
    /// command's rect (`preselect`) skips the selection: the session opens on it and waits for a
    /// click on Start. A URL command never reaches this during a session: the handler drops it
    /// while a capture runs. Without a rect, a URL command's overlay opens disarmed, as Capture
    /// Window's does.
    func captureScrolling(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil,
                          fromURLCommand: Bool = false) async {
        // During a session the shortcut is Start, then Done (the lock is held meanwhile).
        if scrollCapture.isRunning {
            scrollCapture.advance()
            return
        }
        await withCaptureLock(coversDesktop: false) {
            guard let content = await loadContent() else { return }
            if let preselect {
                guard let display = content.displays.first(where: { $0.displayID == preselect.displayID }) else {
                    log("Capture Scrolling: display \(preselect.displayID) is gone")
                    return
                }
                // The app is not activated and the panel is not made key: Start and Done are default
                // actions, so a Return typed in the frontmost app must not start a capture of the
                // sender's rect. Start needs a click (or the hotkey). Unstarted for
                // `ScrollCaptureSession.readyTimeout`, the session cancels itself, so a planted one
                // does not hold the capture lock and the global Escape.
                // `runScrolling` refuses a rect under 100 pt; its `dismiss()` is a no-op here.
                await runScrolling(rect: preselect.rect, display: display, intent: intent, preselected: true)
                return
            }
            guard let selection = await selector.select(mode: .scrolling, content: content, freeze: nil, preselect: nil,
                                                        armed: !fromURLCommand) else { return }
            guard case .area(let rect, let display) = selection else {
                selector.dismiss()
                return
            }
            await runScrolling(rect: rect, display: display, intent: intent)
        }
    }

    /// A scrolling capture of an area chosen in the overlay, which is still up: refuses one under
    /// 100 pt with the Phase 5 message, stores the previous area, dismisses the overlay, runs the
    /// session and saves the stitched image like any capture. A URL command's rect (`preselected`)
    /// opens the panel without making it key, cancels itself when not started within
    /// `ScrollCaptureSession.readyTimeout`, and is stored as the previous area only when the
    /// stitched image is saved, so a cancelled session leaves Previous Area as it was.
    private func runScrolling(rect: CGRect, display: CaptureDisplay, intent: CaptureIntent,
                              preselected: Bool = false) async {
        guard rect.height >= CGFloat(ScrollCaptureLimits.minimumAreaHeightPoints) else {
            selector.dismiss()
            notifier.notifyError("Select an area at least 100 points tall.", title: "Scrolling capture")
            return
        }
        if !preselected {
            settings.lastAreaRect = StoredRect(rect)
        }
        selector.dismiss()
        // The session films the ScreenCaptureKit display; a display a test built has none and ends here.
        guard let liveDisplay = display.live else { return }
        let outcome = await scrollCapture.run(rect: rect, display: liveDisplay, makesPanelKey: !preselected,
                                              readyTimeout: preselected ? ScrollCaptureSession.readyTimeout : nil)
        if let notice = outcome.failureNotice {
            notifier.notifyError(notice.body, title: notice.title)
        }
        if let image = outcome.imageToSave {
            if preselected {
                settings.lastAreaRect = StoredRect(rect)
            }
            await save(CaptureResult(image: image.image, scale: image.scale,
                                     target: .area(rect: rect, display: display)), intent: intent)
        }
    }

    /// Capture Previous Area: the last area capture's rect again, live, with no selection overlay.
    /// `PreviousArea.resolve` clips the stored rect to the display under its centre. The cards are
    /// excluded and the pointer follows Show cursor, as for a fullscreen capture. It does not
    /// write `lastAreaRect`: a clipped rect would shrink the memory.
    func capturePreviousArea(intent: CaptureIntent = .standard) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            let displays = content.displays.map { PreviousArea.Display(id: $0.displayID, frame: $0.frame) }
            switch PreviousArea.resolve(rect: settings.lastAreaRect?.cgRect, displays: displays) {
            case .none:
                notifier.notifyError("Capture an area first.", title: "No previous area")
            case .offScreen:
                notifier.notifyError("The previous area is not on a connected display.", title: "No previous area")
            case .area(let rect, let displayID):
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let cards = await cardWindows()
                guard let result = await capture(.area(rect: rect, display: display), excludingWindows: cards) else { return }
                await save(result, intent: intent)
            }
        }
    }

    /// A URL command's `capture-area` with x, y, width and height (the gate has allowed it): that
    /// rect at once, live, with no selection overlay, as Capture Previous Area captures (the cards
    /// excluded, the pointer from Show cursor). It is stored as the previous area.
    func captureArea(at area: ScreenRect, intent: CaptureIntent) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
                log("URL capture-area: display \(area.displayID) is gone")
                return
            }
            let cards = await cardWindows()
            guard let result = await capture(.area(rect: area.rect, display: display), excludingWindows: cards) else { return }
            // Only a rect that was captured becomes the previous area.
            settings.lastAreaRect = StoredRect(area.rect)
            await save(result, intent: intent)
        }
    }

    /// Self-Timer: select an area or click a window, then count down and capture it live. The
    /// lock is held for the selection, the countdown and the capture. A URL command's overlay
    /// opens disarmed, as Capture Window's does.
    func captureSelfTimer(intent: CaptureIntent = .standard, fromURLCommand: Bool = false) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: .selfTimer, content: content, freeze: nil, preselect: nil,
                                                        armed: !fromURLCommand) else { return }
            switch selection {
            case .area(let rect, let display):
                settings.lastAreaRect = StoredRect(rect)
                await runSelfTimer(.area(rect: rect, display: display), intent: intent)
            case .window(let window):
                await runSelfTimer(.window(window), intent: intent)
            }
        }
    }

    /// Show the overlay, capture with the overlay excluded (or cut the frozen snapshot), dismiss, then save.
    private func runSelection(mode: SelectionMode, intent: CaptureIntent, armed: Bool = true) async {
        await withCaptureLock(coversDesktop: true) {
            guard let content = await loadContent() else { return }
            // Freeze applies to area mode only. The snapshots follow the cursor setting: they are
            // taken before the overlay, so the pointer in them is the real one.
            let freeze = mode == .area && settings.freezeScreen
                ? CaptureOptions(settings: settings, duringSelection: false) : nil
            guard let selection = await selector.select(mode: mode, content: content, freeze: freeze, preselect: nil,
                                                        armed: armed) else { return }

            let result: CaptureResult?
            switch selection {
            case .area(let rect, let display):
                result = await areaResult(rect: rect, display: display)
            case .window(let window):
                result = await capture(.window(window), duringSelection: true)
            }
            selector.dismiss()

            if let result {
                await save(result, intent: intent)
            }
        }
    }

    /// Capture Text (spec 2.10): Capture Area's overlay, with Freeze screen as there, and the image
    /// Capture Area would have taken. The lock is held for the selection and the capture only, so
    /// recognition (about 24 s the first time after a restart) never blocks another capture. It
    /// does not write `lastAreaRect`: the previous area is for image captures.
    func captureText() async {
        var captured: CaptureResult?
        await withCaptureLock(coversDesktop: false) {
            guard let content = await loadContent() else { return }
            let freeze = settings.freezeScreen ? CaptureOptions(settings: settings, duringSelection: false) : nil
            guard let selection = await selector.select(mode: .area, content: content, freeze: freeze, preselect: nil,
                                                        armed: true) else { return }
            switch selection {
            case .area(let rect, let display):
                captured = await selectedAreaResult(rect: rect, display: display)
            case .window(let window):
                // Area mode never returns a window; a click without a drag cancels.
                captured = await capture(.window(window), duringSelection: true)
            }
            selector.dismiss()
        }
        if let captured {
            await copyText(in: captured.image)
        }
    }

    /// A URL command's `capture-text` with a rect (the gate has allowed it): that rect at once,
    /// live, with the cards excluded and no pointer. It does not write `lastAreaRect`.
    func captureText(at area: ScreenRect) async {
        var captured: CaptureResult?
        await withCaptureLock(coversDesktop: false) {
            guard let content = await loadContent() else { return }
            guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
                log("URL capture-text: display \(area.displayID) is gone")
                return
            }
            let cards = await cardWindows()
            captured = await capture(.area(rect: area.rect, display: display), excludingWindows: cards,
                                     duringSelection: true)
        }
        if let captured {
            await copyText(in: captured.image)
        }
    }

    /// Reads the text or codes in `image` off the main actor, then puts the result on the
    /// clipboard with the capture sound and a notification, as Play sound and Show notification
    /// say. Nothing found and a Vision error are always posted, and leave the clipboard alone.
    /// No file, record, card or upload; `clipboardOwner` stays, since the change count moved.
    private func copyText(in image: CGImage) async {
        let scan: TextScan
        do {
            scan = try await TextRecognizer().recognize(image)
        } catch {
            log("Text recognition failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Text not recognized")
            return
        }
        let outcome = TextCaptureOutcome.decide(scan)
        guard let text = outcome.clipboard else {
            notifier.notifyError(outcome.body, title: outcome.title)
            return
        }
        clipboard.setString(text)
        if settings.playSound {
            environment.playShutter()
        }
        if settings.showNotification {
            notifier.notify(title: outcome.title, body: outcome.body, openURL: outcome.openURL)
        }
    }

    /// The countdown and the capture behind Self-Timer and All-in-One's Timer button. Call it with
    /// the capture lock held. The selection overlay goes first, then TidyShot gives up activation
    /// so the user's app is frontmost while the badge counts: its menus open and its keys work.
    /// A countdown that is cancelled leaves nothing behind.
    private func runSelfTimer(_ target: CaptureTarget, intent: CaptureIntent) async {
        selector.dismiss()
        NSApplication.shared.deactivate()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let screenFrame = CaptureEngine.screen(forDisplayID: target.displayID)?.frame ?? NSScreen.main?.frame else { return }
        let stage = SelfTimerScreenStage(subject: Geometry.appKitRect(fromCG: target.cgFrame, primaryHeight: primaryHeight),
                                         screenFrame: screenFrame)
        _ = await selfTimer.run(seconds: settings.selfTimerSeconds, stage: stage) { [self] in
            await captureAfterCountdown(target, intent: intent)
        }
    }

    /// The live capture once the panels are gone. The shareable content is read again, and the
    /// display or window is found in it by id: a window may have moved or closed during the
    /// countdown, and an `SCWindow` from before would size the image from its old frame. The
    /// pointer follows Show cursor and the cards are left out, as for a fullscreen capture.
    private func captureAfterCountdown(_ target: CaptureTarget, intent: CaptureIntent) async {
        guard let content = await loadContent() else { return }
        let fresh: CaptureTarget
        switch target {
        case .display(let display):
            guard let current = content.displays.first(where: { $0.displayID == display.displayID }) else {
                notifier.notifyError("The display is no longer connected.", title: "Self-timer")
                return
            }
            fresh = .display(current)
        case .area(let rect, let display):
            guard let current = content.displays.first(where: { $0.displayID == display.displayID }) else {
                notifier.notifyError("The display is no longer connected.", title: "Self-timer")
                return
            }
            fresh = .area(rect: rect, display: current)
        case .window(let window):
            guard let current = content.windows.first(where: { $0.windowID == window.windowID }) else {
                notifier.notifyError("The window is no longer on screen.", title: "Self-timer")
                return
            }
            fresh = .window(current)
        }
        guard let result = await capture(fresh, excludingWindows: await cardWindows()) else { return }
        await save(result, intent: intent)
    }

    /// An area chosen in the overlay, which is still up: stores it as the previous area, then cuts
    /// it from the frozen snapshot or captures it live with the overlay and the cards excluded.
    private func areaResult(rect: CGRect, display: CaptureDisplay) async -> CaptureResult? {
        settings.lastAreaRect = StoredRect(rect)
        return await selectedAreaResult(rect: rect, display: display)
    }

    /// An area chosen in the overlay, which is still up, cut from the frozen snapshot or captured
    /// live with the overlay and the cards excluded. Stores nothing.
    private func selectedAreaResult(rect: CGRect, display: CaptureDisplay) async -> CaptureResult? {
        if let frozen = frozenResult(for: rect, display: display) {
            return frozen
        }
        let overlays = await selector.overlayWindows()
        return await capture(.area(rect: rect, display: display), excludingWindows: overlays, duringSelection: true)
    }

    /// The selection cut from the display's frozen snapshot, or nil when there is none (freeze off,
    /// or that display's snapshot failed) or the crop failed; the caller then captures live.
    private func frozenResult(for rect: CGRect, display: CaptureDisplay) -> CaptureResult? {
        guard let frozen = selector.frozenCapture(for: display.displayID) else { return nil }
        guard let image = FreezeCrop.cropped(frozen.image, selection: rect, displayFrame: display.frame,
                                             scale: frozen.scale) else {
            log("Freeze crop failed for \(rect) on display \(display.displayID); capturing live")
            return nil
        }
        return CaptureResult(image: image, scale: frozen.scale, target: .area(rect: rect, display: display))
    }

    func revealLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    /// Runs the engine. On failure posts a notification and returns nil. `duringSelection` is
    /// true for the live captures taken while the selection overlay is still up; the pointer is
    /// then never captured (`CaptureOptions.init(settings:duringSelection:)`).
    func capture(_ target: CaptureTarget, excludingWindows: [CaptureWindow] = [],
                 duringSelection: Bool = false) async -> CaptureResult? {
        do {
            let options = CaptureOptions(settings: settings, duringSelection: duringSelection)
            return try await captureSource.capture(target, options: options, excludingWindows: excludingWindows)
        } catch {
            log("Capture failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return nil
        }
    }

    /// The Quick Access cards as ScreenCaptureKit sees them, for a capture taken without the
    /// selection overlay; no lookup when no card shows.
    private func cardWindows() async -> [CaptureWindow] {
        let numbers = overlay.windowNumbers
        guard !numbers.isEmpty else { return [] }
        return await captureSource.windows(numbers: numbers)
    }
}
