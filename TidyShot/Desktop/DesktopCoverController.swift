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
    private var reasons = DesktopCoverReasons()
    private var panels: [CGDirectDisplayID: DesktopCoverPanel] = [:]
    /// The panels are on screen.
    private var isShowing = false
    /// The show that is capturing and ordering the panels front, for a later show to wait on.
    private var bringingUp: Task<Void, Never>?
    /// The capture in flight, shared by every show and refresh that arrives meanwhile.
    private var capturing: Task<[CGDirectDisplayID: CGImage], Never>?
    private var hasReportedFailure = false
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    private var refreshTimer: Timer?

    init(source: WallpaperSource, reportFailure: @escaping @MainActor () -> Void) {
        self.source = source
        self.reportFailure = reportFailure
    }

    /// Whether `Hide Desktop Icons` is on until turned off.
    var isPersistent: Bool { reasons.active.contains(.persistent) }

    /// Adds `reason`. When the covers were not already up, captures the wallpapers, orders the
    /// panels front and returns once a capture would see them.
    func show(for reason: DesktopCoverReasons.Reason) async {
        reasons.insert(reason)
        while true {
            // A hide and a show while it ran can leave the covers down, hence the loop.
            if let bringingUp {
                await bringingUp.value
                continue
            }
            guard reasons.showsCovers, !isShowing else { return }
            bringingUp = Task {
                await bringUp()
                bringingUp = nil
            }
        }
    }

    /// Removes `reason`, and orders the panels out when no reason is left.
    func hide(for reason: DesktopCoverReasons.Reason) {
        reasons.remove(reason)
        guard !reasons.showsCovers else { return }
        stopRefreshing()
        for panel in panels.values {
            panel.orderOut(nil)
        }
        isShowing = false
    }

    private func bringUp() async {
        let wallpapers = await captureWallpapers()
        // Hidden again while capturing.
        guard reasons.showsCovers else { return }
        update(with: wallpapers)
        isShowing = true
        startRefreshing()
        CATransaction.flush()
        try? await Task.sleep(for: Self.settleDelay)
    }

    private func refresh() {
        guard isShowing else { return }
        Task {
            let wallpapers = await captureWallpapers()
            guard isShowing else { return }
            update(with: wallpapers)
        }
    }

    private func captureWallpapers() async -> [CGDirectDisplayID: CGImage] {
        if let capturing { return await capturing.value }
        let source = source
        let task = Task {
            let wallpapers = await source.wallpapers()
            capturing = nil
            return wallpapers
        }
        capturing = task
        return await task.value
    }

    /// Builds or updates one panel per screen that has a wallpaper, orders them front, and drops
    /// the panels of screens that are gone or have none.
    private func update(with wallpapers: [CGDirectDisplayID: CGImage]) {
        var updated: [CGDirectDisplayID: DesktopCoverPanel] = [:]
        var missing = false
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            guard let wallpaper = wallpapers[displayID] else {
                missing = true
                continue
            }
            let panel = panels[displayID] ?? DesktopCoverPanel(frame: screen.frame)
            panel.setFrame(screen.frame, display: false)
            panel.setWallpaper(wallpaper)
            panel.orderFrontRegardless()
            updated[displayID] = panel
        }
        for (displayID, panel) in panels where updated[displayID] == nil {
            panel.orderOut(nil)
        }
        panels = updated
        if missing, !hasReportedFailure {
            hasReportedFailure = true
            reportFailure()
        }
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
