import AppKit
import AVFoundation
import AVKit

/// One Trim window for one recording (design, Trim, Window): the system trim bar on an `AVPlayerView`
/// of the file, the save sheet and the `Trimming…` sheet. It writes nothing: `AppCoordinator+Trim.swift`
/// takes the range from `onRange`, asks with `askToSave` and runs the pass. The close button is
/// disabled while a sheet is up.
final class TrimWindowController: NSWindowController, NSWindowDelegate {
    let recordID: UUID
    /// The file the player shows and the pass trims.
    let fileURL: URL
    /// The trim bar's `Trim`: `reversePlaybackEndTime` and `forwardPlaybackEndTime`, where an invalid
    /// time is the file's start or end.
    var onRange: (CMTime, CMTime) -> Void = { _, _ in }
    /// The file could not be played, with why. The window stays open for the coordinator to close.
    var onFailure: (String) -> Void = { _ in }
    /// Called once, from `windowWillClose`, whatever closed the window.
    var onClose: () -> Void = {}

    private let player: AVPlayer
    private let playerView = AVPlayerView()
    private var statusObservation: NSKeyValueObservation?
    private var progressSheet: TrimProgressSheet?
    private var hasBegunTrimming = false
    private var isClosed = false

    /// How long, at most, the trim bar is waited for once the file is ready to play.
    private static let trimBarWait = Duration.seconds(5)
    private static let trimBarPoll = Duration.milliseconds(100)

    /// `pixelSize` is the recording's, for the window's first size.
    init(recordID: UUID, fileURL: URL, title: String, pixelSize: CGSize) {
        self.recordID = recordID
        self.fileURL = fileURL
        player = AVPlayer(url: fileURL)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let contentSize = Self.contentSize(pixelSize: pixelSize, scale: screen?.backingScaleFactor ?? 2,
                                           visibleSize: screen?.visibleFrame.size ?? CGSize(width: 1440, height: 900))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = title
        window.contentMinSize = Self.minimumContentSize
        playerView.controlsStyle = .inline
        playerView.player = player
        window.contentView = playerView
        super.init(window: window)
        window.delegate = self
        // Centred on the screen it was sized for, which `center()` would not be with several displays.
        if let screen {
            let size = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
            window.setFrame(Self.frame(size: size, centredIn: screen.visibleFrame), display: false)
        } else {
            window.center()
        }
        observeStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The file's length once the player has read it; invalid before.
    var duration: CMTime {
        player.currentItem?.duration ?? .invalid
    }

    /// The codebase's activation idiom: a plain `activate()` is refused when called from the
    /// non-activating overlay.
    func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            window?.orderFrontRegardless()
        }
    }

    // MARK: The trim bar

    /// The trim bar begins once the item is ready to play and the view can begin trimming.
    private func observeStatus() {
        statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { @Sendable [weak self] item, _ in
            let status = item.status
            Task { @MainActor in self?.itemStatusChanged(status) }
        }
    }

    private func itemStatusChanged(_ status: AVPlayerItem.Status) {
        guard !isClosed, !hasBegunTrimming else { return }
        switch status {
        case .readyToPlay:
            hasBegunTrimming = true
            Task { await beginTrimming() }
        case .failed:
            hasBegunTrimming = true
            NSLog("%@", "Trim: \(fileURL.lastPathComponent) could not be played: \(player.currentItem?.error?.localizedDescription ?? "unknown")")
            onFailure(RecordingTrimError.couldNotRead.localizedDescription)
        default:
            break
        }
    }

    /// `canBeginTrimming` can lag behind `readyToPlay` while the view lays out its controls, so it
    /// is asked again for a few seconds.
    private func beginTrimming() async {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.trimBarWait
        while !isClosed, !playerView.canBeginTrimming, clock.now < deadline {
            try? await Task.sleep(for: Self.trimBarPoll)
        }
        guard !isClosed else { return }
        guard playerView.canBeginTrimming else {
            NSLog("%@", "Trim: the trim bar could not begin for \(fileURL.lastPathComponent)")
            onFailure(RecordingTrimError.couldNotRead.localizedDescription)
            return
        }
        showTrimBar()
    }

    /// The completion handler, not the async form: a window closed under the bar may never hear back,
    /// and nothing then waits for it.
    private func showTrimBar() {
        playerView.beginTrimming { @Sendable [weak self] result in
            Task { @MainActor in self?.trimmingEnded(result) }
        }
    }

    /// `Trim` hands the range on; the bar's `Cancel` closes the window and changes nothing.
    private func trimmingEnded(_ result: AVPlayerViewTrimResult) {
        guard !isClosed else { return }
        switch result {
        case .okButton:
            player.pause()
            let item = player.currentItem
            onRange(item?.reversePlaybackEndTime ?? .invalid, item?.forwardPlaybackEndTime ?? .invalid)
        default:
            close()
        }
    }

    // MARK: The save sheet

    /// The save sheet (design, The sheet): an `NSAlert` sheet with `buttons` in order, the first
    /// taking Return and `Cancel`, last, taking Escape. A window that closes under it answers `Cancel`.
    func askToSave(message: String, informativeText: String,
                   buttons: [RecordingTrim.SheetButton]) async -> RecordingTrim.SheetButton {
        guard !isClosed, let window, window.attachedSheet == nil else { return .cancel }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        for button in buttons {
            let added = alert.addButton(withTitle: button.title)
            if button == .cancel {
                added.keyEquivalent = "\u{1b}"
            }
        }
        return Self.sheetButton(response: await alert.beginSheetModal(for: window), of: buttons)
    }

    /// The save sheet's button for its `response`: `alertFirstButtonReturn` is the first of `buttons`
    /// and each later return the next. Any other response, as `.cancel` when the window closes under
    /// the sheet, is `Cancel` (`RecordingTrim.sheetButton(at:of:)`).
    nonisolated static func sheetButton(response: NSApplication.ModalResponse,
                                        of buttons: [RecordingTrim.SheetButton]) -> RecordingTrim.SheetButton {
        RecordingTrim.sheetButton(at: response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue,
                                  of: buttons)
    }

    // MARK: The Trimming… sheet

    /// The `Trimming…` sheet for a re-encode: a determinate bar and `Stop`.
    func showProgress(onStop: @escaping () -> Void) {
        guard !isClosed, let window, progressSheet == nil else { return }
        let sheet = TrimProgressSheet(onStop: onStop)
        progressSheet = sheet
        window.beginSheet(sheet.panel)
    }

    /// Moves the bar on; it never goes back.
    func setProgress(_ fraction: Double) {
        progressSheet?.setProgress(fraction)
    }

    /// `Stop` is disabled once the put starts: the put cannot be stopped.
    func setStopEnabled(_ enabled: Bool) {
        progressSheet?.setStopEnabled(enabled)
    }

    func hideProgress() {
        guard let sheet = progressSheet else { return }
        progressSheet = nil
        window?.endSheet(sheet.panel)
    }

    // MARK: Closing

    /// Closes the window for any reason. A sheet still up is ended first, each once, the save sheet
    /// answering `Cancel`: `hideProgress` ends `Trimming…`, which can still be listed among the window's
    /// sheets while it animates away.
    override func close() {
        guard !isClosed else { return }
        let progress = progressSheet?.panel
        hideProgress()
        if let window {
            for sheet in window.sheets where sheet !== progress {
                window.endSheet(sheet, returnCode: .cancel)
            }
        }
        super.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.attachedSheet == nil
    }

    func windowWillBeginSheet(_ notification: Notification) {
        window?.standardWindowButton(.closeButton)?.isEnabled = false
    }

    func windowDidEndSheet(_ notification: Notification) {
        window?.standardWindowButton(.closeButton)?.isEnabled = window?.attachedSheet == nil
    }

    func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        statusObservation?.invalidate()
        statusObservation = nil
        // The file is let go before the coordinator removes the download and releases the folder's scope.
        player.pause()
        player.replaceCurrentItem(with: nil)
        playerView.player = nil
        onClose()
    }

    // MARK: Geometry

    nonisolated static let minimumContentSize = CGSize(width: 480, height: 300)
    /// The share of the screen's visible frame the window's first size may take.
    nonisolated static let maximumScreenShare: CGFloat = 0.8

    /// The window's first frame: `size` centred in `visibleFrame`, the visible frame of the screen it
    /// was sized for, on whole points.
    nonisolated static func frame(size: CGSize, centredIn visibleFrame: CGRect) -> CGRect {
        CGRect(x: (visibleFrame.midX - size.width / 2).rounded(), y: (visibleFrame.midY - size.height / 2).rounded(),
               width: size.width, height: size.height)
    }

    /// The window's first content size: the recording at its point size (`pixelSize` over the
    /// screen's `scale`), scaled down to fit `maximumScreenShare` of `visibleSize` with its aspect
    /// kept, and at least `minimumContentSize`. An unknown size gives the minimum.
    nonisolated static func contentSize(pixelSize: CGSize, scale: CGFloat, visibleSize: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0, scale > 0 else { return minimumContentSize }
        let points = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        let limit = CGSize(width: visibleSize.width * maximumScreenShare, height: visibleSize.height * maximumScreenShare)
        let fit = min(1, limit.width / points.width, limit.height / points.height)
        return CGSize(width: max(minimumContentSize.width, (points.width * fit).rounded()),
                      height: max(minimumContentSize.height, (points.height * fit).rounded()))
    }
}

/// The `Trimming…` sheet: the title, a determinate bar and `Stop` (Escape).
private final class TrimProgressSheet: NSObject {
    let panel: NSPanel
    private let bar = NSProgressIndicator()
    private let stopButton: NSButton
    private let onStop: () -> Void

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
        let size = CGSize(width: 360, height: 112)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled],
                        backing: .buffered, defer: true)
        stopButton = NSButton(title: "Stop", target: nil, action: nil)
        super.init()
        let title = NSTextField(labelWithString: "Trimming…")
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        title.frame = NSRect(x: 20, y: 76, width: size.width - 40, height: 18)
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.doubleValue = 0
        bar.frame = NSRect(x: 20, y: 50, width: size.width - 40, height: 20)
        stopButton.target = self
        stopButton.action = #selector(stop)
        stopButton.keyEquivalent = "\u{1b}"
        stopButton.bezelStyle = .push
        stopButton.sizeToFit()
        let buttonWidth = max(stopButton.frame.width, 80)
        stopButton.frame = NSRect(x: size.width - 20 - buttonWidth, y: 12, width: buttonWidth, height: stopButton.frame.height)
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        for view in [title, bar, stopButton] as [NSView] {
            content.addSubview(view)
        }
        panel.contentView = content
    }

    func setProgress(_ fraction: Double) {
        let value = min(1, max(0, fraction))
        if value > bar.doubleValue {
            bar.doubleValue = value
        }
    }

    func setStopEnabled(_ enabled: Bool) {
        stopButton.isEnabled = enabled
    }

    @objc private func stop() {
        // Once: the pass ends the sheet when it stops.
        stopButton.isEnabled = false
        onStop()
    }
}
