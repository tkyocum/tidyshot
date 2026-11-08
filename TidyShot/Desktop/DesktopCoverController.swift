import AppKit

/// Shows and hides the desktop covers, one `DesktopCoverPanel` per display (spec 2.10). The covers
/// show while any reason is active, and their wallpapers are captured again while they show.
final class DesktopCoverController {
    /// Dynamic wallpapers change through the day.
    private static let refreshInterval: TimeInterval = 10 * 60
    /// The probe saw a cover in a capture 16 ms after ordering it front.
    private static let settleDelay: Duration = .milliseconds(50)

    private let source: WallpaperSource
    private let reportFailure: @MainActor () -> Void
    private var reasons: Set<Reason> = []
    private var panels: [CGDirectDisplayID: DesktopCoverPanel] = [:]
    /// The panels are on screen.
    private var isShowing = false
    /// The show that is capturing and ordering the panels front, for a later show to wait on.
    private var bringingUp: Task<Void, Never>?
    /// The capture in flight, shared by every show that arrives meanwhile.
    private var capturing: Task<[CGDirectDisplayID: CGImage], Never>?
    /// A refresh arrived while a capture was in flight; one more runs when it ends.
    private var refreshPending = false
    private var hasReportedFailure = false
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var refreshTimer: Timer?

    init(source: WallpaperSource, reportFailure: @escaping @MainActor () -> Void) {
        self.source = source
        self.reportFailure = reportFailure
    }

    /// Why the covers are up. They show while any reason is active, so a capture that ends
    /// leaves a persistent cover in place, and turning the persistent cover off during a capture
    /// keeps the covers until the capture ends.
    nonisolated enum Reason: Hashable, Sendable {
        /// A capture flow is running with `Hide desktop icons while capturing` on.
        case capture
        /// `Hide Desktop Icons` is on until turned off.
        case persistent
    }

    /// Whether `Hide Desktop Icons` is on until turned off.
    var isPersistent: Bool { reasons.contains(.persistent) }

    /// The covers on screen by display, for a recording's filter: they are TidyShot windows the
    /// recording keeps in the picture.
    var windowNumbers: [CGDirectDisplayID: CGWindowID] {
        panels.compactMapValues { $0.isVisible && $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil }
    }

    /// Adds `reason`. When the covers were not already up, or a screen has none, captures the
    /// wallpapers, orders the panels front and returns once a capture would see them.
    func show(for reason: Reason) async {
        reasons.insert(reason)
        while true {
            if let bringingUp {
                await bringingUp.value
                // A hide and a show while it ran can leave the covers down; then go again.
                if isShowing || reasons.isEmpty { return }
                continue
            }
            guard !reasons.isEmpty else { return }
            if isShowing, DesktopCoverPlan.needingCapture(screens: screenIDs, covered: Set(panels.keys)).isEmpty { return }
            bringingUp = Task {
                await bringUp()
                bringingUp = nil
            }
        }
    }

    /// Removes `reason`, and orders the panels out when no reason is left.
    func hide(for reason: Reason) {
        reasons.remove(reason)
        guard reasons.isEmpty else { return }
        stopRefreshing()
        refreshPending = false
        for panel in panels.values {
            panel.orderOut(nil)
        }
        // A show from hidden captures every screen again, so the kept wallpapers (about 59 MB on
        // a 5K display) are of no use.
        panels.removeAll()
        isShowing = false
    }

    private func bringUp() async {
        // While the covers are up, only screens without one are new; the others are left as is.
        // From hidden, the kept panels' wallpapers may be hours old or from another Space.
        let wasShowing = isShowing
        let wallpapers = await captureWallpapers()
        // Hidden again while capturing.
        guard !reasons.isEmpty else { return }
        update(with: wallpapers, kind: wasShowing && isShowing ? .showWhileUp : .show)
        isShowing = true
        startRefreshing()
        CATransaction.flush()
        try? await Task.sleep(for: Self.settleDelay)
    }

    /// Captures the wallpapers again. A capture in flight began before the trigger and may miss
    /// what it is for (a new Space, a new display), so one more capture follows it.
    private func refresh() {
        guard isShowing else { return }
        if capturing != nil {
            refreshPending = true
            return
        }
        Task {
            let wallpapers = await captureWallpapers()
            guard isShowing else { return }
            update(with: wallpapers, kind: .refresh)
        }
    }

    private func captureWallpapers() async -> [CGDirectDisplayID: CGImage] {
        if let capturing { return await capturing.value }
        let source = source
        let task = Task {
            let wallpapers = await source.wallpapers()
            capturing = nil
            if refreshPending {
                refreshPending = false
                refresh()
            }
            return wallpapers
        }
        capturing = task
        return await task.value
    }

    /// Builds or updates one panel per screen with a new wallpaper and orders them front. While the
    /// covers show, a panel whose capture failed keeps its last wallpaper; one whose screen is gone
    /// is dropped.
    private func update(with wallpapers: [CGDirectDisplayID: CGImage], kind: DesktopCoverPlan.Kind) {
        let screens = NSScreen.screens.compactMap { screen in screen.displayID.map { ($0, screen) } }
        let plan = DesktopCoverPlan.make(screens: screens.map(\.0), covered: Set(panels.keys),
                                         captured: Set(wallpapers.keys), kind: kind)
        for displayID in plan.removed {
            panels.removeValue(forKey: displayID)?.orderOut(nil)
        }
        for (displayID, screen) in screens where panels[displayID] != nil || plan.wallpapered.contains(displayID) {
            let panel = panels[displayID] ?? DesktopCoverPanel(frame: screen.frame)
            panel.setFrame(screen.frame, display: false)
            if plan.wallpapered.contains(displayID), let wallpaper = wallpapers[displayID] {
                panel.setWallpaper(wallpaper)
            }
            panel.orderFrontRegardless()
            panels[displayID] = panel
        }
        if !plan.uncovered.isEmpty, !hasReportedFailure {
            hasReportedFailure = true
            reportFailure()
        }
    }

    private var screenIDs: [CGDirectDisplayID] {
        NSScreen.screens.compactMap(\.displayID)
    }

    private func startRefreshing() {
        stopRefreshing()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: workspace)
        observe(NSWorkspace.didWakeNotification, on: workspace)
        observe(NSApplication.didChangeScreenParametersNotification, on: .default)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append((center, token))
    }

    private func stopRefreshing() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}
