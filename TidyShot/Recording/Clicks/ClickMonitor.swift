import AppKit

/// Where click events come from: the real monitors, or a fake in tests.
protocol ClickEventSource: AnyObject {
    func install(_ handler: @escaping (ClickEvent) -> Void)
    func remove()
}

/// What draws the rings: the overlay, or a fake in tests.
protocol ClickRingDrawing: AnyObject {
    func apply(_ change: ClickRingChange)
    func removeAllRings()
}

/// The mouse button monitors (design, Click highlights, Seeing clicks). A global monitor sees
/// clicks on other apps' windows; a local one adds clicks on the bubble, which the global one
/// cannot see. No event tap, and never an Accessibility or Input Monitoring call, not even to log:
/// those checks raise the Accessibility prompt in the sandbox, and the monitors need no grant (G1).
final class ClickMonitor: ClickEventSource {
    static let mask: NSEvent.EventTypeMask = [
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
    ]

    private let isFilmedWindow: (NSWindow) -> Bool
    private var isInstalled = false
    private var global: Any?
    private var local: Any?

    /// `isFilmedWindow` is true for the bubble, the one TidyShot window whose downs draw.
    init(isFilmedWindow: @escaping (NSWindow) -> Bool) {
        self.isFilmedWindow = isFilmedWindow
    }

    func install(_ handler: @escaping (ClickEvent) -> Void) {
        guard !isInstalled else { return }
        isInstalled = true
        global = NSEvent.addGlobalMonitorForEvents(matching: Self.mask) { event in
            // A global event has no window; its location is already in screen coordinates.
            if let click = Self.click(from: event, windowFrame: nil) { handler(click) }
        }
        local = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { [weak self] event in
            guard let self, let click = Self.click(from: event, windowFrame: event.window?.frame) else { return event }
            let onFilmedWindow = event.window.map(self.isFilmedWindow) ?? false
            if Self.localEventPasses(click.phase, onFilmedWindow: onFilmedWindow) { handler(click) }
            return event
        }
    }

    func remove() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
        isInstalled = false
    }

    /// Gap 10: a local down draws only on the bubble; a local drag or up passes from any TidyShot
    /// window, so a held ring is still matched by its button and never stays on screen.
    nonisolated static func localEventPasses(_ phase: ClickEvent.Phase, onFilmedWindow: Bool) -> Bool {
        phase != .down || onFilmedWindow
    }

    private static func click(from event: NSEvent, windowFrame: CGRect?) -> ClickEvent? {
        // Read per event, as displays come and go. With no screen at all a down lands outside
        // every recorded rect, and an up still ends its ring.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return ClickEvent.make(type: event.type, modifierFlags: event.modifierFlags,
                               locationInWindow: event.locationInWindow, windowFrame: windowFrame,
                               primaryMaxY: primaryMaxY)
    }
}

/// Joins a click source, the rule and the ring drawing for one recording. The rule can be replaced
/// until the monitors are installed, so the start gives it the fresh recorded rect.
final class ClickHighlighter {
    private var rule: ClickHighlightRule
    private let source: any ClickEventSource
    private let drawing: any ClickRingDrawing
    private(set) var isMonitoring = false

    init(rule: ClickHighlightRule, source: any ClickEventSource, drawing: any ClickRingDrawing) {
        self.rule = rule
        self.source = source
        self.drawing = drawing
    }

    /// Ignored while monitoring.
    func setRule(_ rule: ClickHighlightRule) {
        guard !isMonitoring else { return }
        self.rule = rule
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        source.install { [weak self] event in self?.handle(event) }
    }

    /// Removes the monitors, and every held ring starts its fade, as the monitors will not see
    /// its up. A ring already fading finishes.
    func stop() {
        if isMonitoring {
            isMonitoring = false
            source.remove()
        }
        for change in rule.endAll() { drawing.apply(change) }
    }

    /// Stops and takes every ring off the overlay at once.
    func close() {
        stop()
        drawing.removeAllRings()
    }

    private func handle(_ event: ClickEvent) {
        guard isMonitoring else { return }
        for change in rule.handle(event) { drawing.apply(change) }
    }
}
