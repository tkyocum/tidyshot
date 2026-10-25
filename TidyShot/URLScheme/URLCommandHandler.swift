import Foundation

/// What URL commands run: the app's existing capture functions. `AppCoordinator` conforms; the
/// tests use a recorder.
protocol URLCommandTarget: AnyObject {
    /// True while a capture would be refused: another runs, or the microphone prompt is open.
    var capturesRefused: Bool { get }
    func captureArea(intent: CaptureIntent) async
    func captureArea(at area: ScreenRect, intent: CaptureIntent) async
    func captureWindow(intent: CaptureIntent) async
    func captureFullscreen(intent: CaptureIntent) async
    func capturePreviousArea(intent: CaptureIntent) async
    func captureAllInOne(intent: CaptureIntent, preselect: ScreenRect?, fromURLCommand: Bool) async
    func captureSelfTimer(intent: CaptureIntent) async
    func captureScrolling(intent: CaptureIntent, preselect: ScreenRect?) async
    func restoreClosedOverlay() async
    func captureText() async
    func captureText(at area: ScreenRect) async
    func setDesktopIconsHidden(_ hidden: Bool) async
    func toggleDesktopIconsHidden() async
}

/// A notification the URL scheme posts. The subtitle names the sending app when it is known.
nonisolated struct URLCommandNotice: Equatable, Sendable {
    var title: String
    var subtitle: String?
    var body: String
}

/// Runs `tidyshot://` URLs (spec 2.9, URL scheme and URL security). It holds URLs until the app has
/// started, then for each: parse, gate, drop a capture command while a capture runs, place a rect,
/// and call the target's capture function with the command's `CaptureIntent`. Every refusal and
/// error posts a notice titled `TidyShot URL command`; every URL is logged with its sender, the
/// URL passed as an argument and never as a format.
final class URLCommandHandler {
    struct Screens {
        /// In `NSScreen.screens` order, CoreGraphics frames.
        var displays: [URLCommandGeometry.Display]
        /// The display under the pointer.
        var pointerIndex: Int?
    }

    static let noticeTitle = "TidyShot URL command"
    /// URLs held before `ready()`. A cold launch from a URL brings one; more is a flood.
    static let queueLimit = 8

    private let settings: AppSettings
    private weak var target: (any URLCommandTarget)?
    private let screens: () -> Screens
    private let post: (URLCommandNotice) -> Void
    private var isReady = false
    private var queued: [(url: URL, sender: String?)] = []

    init(settings: AppSettings, target: any URLCommandTarget, screens: @escaping () -> Screens,
         post: @escaping (URLCommandNotice) -> Void) {
        self.settings = settings
        self.target = target
        self.screens = screens
        self.post = post
    }

    /// Runs `url` now, or queues it until `ready()`.
    func handle(_ url: URL, sender: String?) async {
        guard isReady else {
            guard queued.count < Self.queueLimit else {
                NSLog("%@", "URL command dropped, \(Self.queueLimit) are already waiting for launch: \(url.absoluteString)")
                return
            }
            queued.append((url, sender))
            return
        }
        await run(url, sender: sender)
    }

    /// Called once `AppCoordinator.start()` has run: the waiting URLs run in the order they came.
    /// Only the first capture command among them runs; later ones are dropped as if a capture were
    /// running, so a burst sent before launch cannot open one overlay after another.
    func ready() async {
        guard !isReady else { return }
        isReady = true
        let waiting = queued
        queued = []
        var captureRan = false
        for item in waiting {
            if await run(item.url, sender: item.sender, busy: captureRan) {
                captureRan = true
            }
        }
    }

    /// The sender as messages show it (`URLCommand.displayed`), or nil when unknown or empty.
    static func senderName(_ sender: String?) -> String? {
        guard let sender else { return nil }
        let shown = URLCommand.displayed(sender)
        return shown.isEmpty ? nil : shown
    }

    /// Runs `url`; `busy` drops a capture command as a running capture does. Returns whether a
    /// capture command reached the target.
    @discardableResult
    private func run(_ url: URL, sender rawSender: String?, busy: Bool = false) async -> Bool {
        let sender = Self.senderName(rawSender)
        let command: URLCommand
        switch URLCommand.parse(url) {
        case .failure(let error):
            // With URL commands off nothing is parsed: every URL gets the same refusal.
            refuse(settings.urlCommandsEnabled ? error.message : URLCommandGate.disabledMessage, url: url, sender: sender)
            return false
        case .success(let parsed):
            command = parsed
        }
        if case .refuse(let message) = URLCommandGate.decision(for: command, enabled: settings.urlCommandsEnabled,
                                                               allowSilent: settings.urlCommandsAllowSilent, sender: sender) {
            refuse(message, url: url, sender: sender)
            return false
        }
        guard let target else { return false }
        // Never queued behind a running capture, and never a Start or Done for a scrolling session.
        // Dropped the same way while the microphone prompt is open.
        if command.kind.isCapture, busy || target.capturesRefused {
            let reason = busy ? "a queued capture command ran first" : "a capture is running"
            NSLog("%@", "URL command from \(sender ?? "an unknown app") dropped, \(reason): \(url.absoluteString)")
            return false
        }
        var placement: ScreenRect?
        if let area = command.area {
            let current = screens()
            switch URLCommandGeometry.resolve(area, display: command.display, displays: current.displays,
                                              pointerIndex: current.pointerIndex) {
            case .area(let resolved):
                placement = resolved
            case .noDisplay(let number):
                refuse(URLCommandError.noDisplay(String(number)).message, url: url, sender: sender)
                return false
            case .outside(let number):
                refuse(URLCommandGeometry.outsideMessage(display: number), url: url, sender: sender)
                return false
            }
        }
        NSLog("%@", "URL command from \(sender ?? "an unknown app"): \(url.absoluteString)")
        let intent = CaptureIntent(urlAction: command.action, setting: settings.afterCaptureAction, sender: sender)
        switch command.kind {
        case .captureArea:
            if let placement {
                await target.captureArea(at: placement, intent: intent)
            } else {
                await target.captureArea(intent: intent)
            }
        case .captureWindow: await target.captureWindow(intent: intent)
        case .captureFullscreen: await target.captureFullscreen(intent: intent)
        case .capturePreviousArea: await target.capturePreviousArea(intent: intent)
        case .allInOne: await target.captureAllInOne(intent: intent, preselect: placement, fromURLCommand: true)
        case .selfTimer: await target.captureSelfTimer(intent: intent)
        case .captureScrolling: await target.captureScrolling(intent: intent, preselect: placement)
        case .captureText:
            if let placement {
                await target.captureText(at: placement)
            } else {
                await target.captureText()
            }
        case .restoreRecentlyClosed: await target.restoreClosedOverlay()
        case .hideDesktopIcons: await target.setDesktopIconsHidden(true)
        case .showDesktopIcons: await target.setDesktopIconsHidden(false)
        case .toggleDesktopIcons: await target.toggleDesktopIconsHidden()
        }
        return command.kind.isCapture
    }

    private func refuse(_ message: String, url: URL, sender: String?) {
        NSLog("%@", "URL command from \(sender ?? "an unknown app") refused (\(message)): \(url.absoluteString)")
        post(URLCommandNotice(title: Self.noticeTitle, subtitle: sender.map { "From \($0)" }, body: message))
    }
}
