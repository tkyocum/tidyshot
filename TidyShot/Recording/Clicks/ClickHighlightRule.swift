import AppKit

/// A mouse button that draws a ring. A control-click is `.left`.
nonisolated enum ClickButton: Hashable, Sendable {
    case left
    case right
}

/// A ring's colour: yellow for the left button, blue for the right and for control-click.
nonisolated enum ClickRingColour: Equatable, Sendable {
    case yellow
    case blue

    /// sRGB components.
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat) {
        switch self {
        case .yellow: (red: 1.0, green: 0.8, blue: 0.0)
        case .blue: (red: 0.04, green: 0.52, blue: 1.0)
        }
    }

    var gifColour: GIFColour {
        switch self {
        case .yellow: GIFColour(r: 255, g: 204, b: 0)
        case .blue: GIFColour(r: 10, g: 133, b: 255)
        }
    }

    /// The colours a GIF palette keeps exactly when highlights ran: the two rings, then the
    /// rings' dark edge.
    static let reservedGIFColours: [GIFColour] = [
        ClickRingColour.yellow.gifColour, ClickRingColour.blue.gifColour, GIFColour(r: 0, g: 0, b: 0),
    ]
}

/// A mouse button event, its point in CG global points (top-left origin on the primary display).
nonisolated struct ClickEvent: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case down
        case dragged
        case up
    }

    var phase: Phase
    var button: ClickButton
    var isControl: Bool
    var point: CGPoint

    /// The event for one of the six mouse button types, nil for any other. `windowFrame` is nil
    /// for a global event, whose location is already in screen coordinates.
    static func make(type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags, locationInWindow: CGPoint,
                     windowFrame: CGRect?, primaryMaxY: CGFloat) -> ClickEvent? {
        let phase: Phase
        let button: ClickButton
        switch type {
        case .leftMouseDown: (phase, button) = (.down, .left)
        case .leftMouseDragged: (phase, button) = (.dragged, .left)
        case .leftMouseUp: (phase, button) = (.up, .left)
        case .rightMouseDown: (phase, button) = (.down, .right)
        case .rightMouseDragged: (phase, button) = (.dragged, .right)
        case .rightMouseUp: (phase, button) = (.up, .right)
        default: return nil
        }
        let screen = ClickHighlightRule.screenPoint(locationInWindow: locationInWindow, windowFrame: windowFrame)
        return ClickEvent(phase: phase, button: button, isControl: modifierFlags.contains(.control),
                          point: ClickHighlightRule.cgPoint(fromCocoa: screen, primaryMaxY: primaryMaxY))
    }
}

/// A ring on screen, its point in overlay points from the recorded display's top-left.
nonisolated struct ClickRing: Equatable, Sendable {
    var button: ClickButton
    var colour: ClickRingColour
    var point: CGPoint
}

/// What the overlay does for an event.
nonisolated enum ClickRingChange: Equatable, Sendable {
    case begin(ClickRing)
    case move(ClickButton, to: CGPoint)
    /// The ring starts its fade.
    case end(ClickButton)
}

/// Which clicks draw rings and where (design, Click highlights). A down draws only inside the
/// recorded rect; a held ring follows its button's drags clamped to that rect, and its button's up
/// ends it wherever the up lands.
nonisolated struct ClickHighlightRule: Equatable, Sendable {
    /// The recorded display's frame, CG global points.
    let displayFrame: CGRect
    /// An area recording's rect, already inside the display; nil for fullscreen.
    let area: CGRect?
    /// The rings whose button is still down.
    private(set) var held: [ClickButton: ClickRing] = [:]

    init(displayFrame: CGRect, area: CGRect?) {
        self.displayFrame = displayFrame
        self.area = area
    }

    /// Where a down draws and a held ring is clamped: the area, or the display for fullscreen.
    var recordedRect: CGRect { area ?? displayFrame }

    mutating func handle(_ event: ClickEvent) -> [ClickRingChange] {
        switch event.phase {
        case .down:
            // A held ring whose up was missed ends before the new down.
            var changes: [ClickRingChange] = []
            if held.removeValue(forKey: event.button) != nil { changes.append(.end(event.button)) }
            guard recordedRect.contains(event.point) else { return changes }
            let colour: ClickRingColour = event.button == .right || event.isControl ? .blue : .yellow
            let ring = ClickRing(button: event.button, colour: colour, point: overlayPoint(event.point))
            held[event.button] = ring
            changes.append(.begin(ring))
            return changes
        case .dragged:
            guard held[event.button] != nil else { return [] }
            let clamped = CGPoint(x: min(max(event.point.x, recordedRect.minX), recordedRect.maxX),
                                  y: min(max(event.point.y, recordedRect.minY), recordedRect.maxY))
            let point = overlayPoint(clamped)
            held[event.button]?.point = point
            return [.move(event.button, to: point)]
        case .up:
            guard held.removeValue(forKey: event.button) != nil else { return [] }
            return [.end(event.button)]
        }
    }

    /// Ends every held ring, left then right, as when highlights are turned off.
    mutating func endAll() -> [ClickRingChange] {
        let changes = [ClickButton.left, .right].filter { held[$0] != nil }.map { ClickRingChange.end($0) }
        held = [:]
        return changes
    }

    private func overlayPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - displayFrame.minX, y: point.y - displayFrame.minY)
    }

    /// An event's point in Cocoa screen coordinates: a global event's location as it is, a local
    /// one's offset by its (borderless) window's frame origin.
    static func screenPoint(locationInWindow: CGPoint, windowFrame: CGRect?) -> CGPoint {
        guard let windowFrame else { return locationInWindow }
        return CGPoint(x: windowFrame.minX + locationInWindow.x, y: windowFrame.minY + locationInWindow.y)
    }

    /// Cocoa to CG global points; `primaryMaxY` is the primary screen's frame's maxY.
    static func cgPoint(fromCocoa point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryMaxY - point.y)
    }

    static let notFilmedNotice = RecordingNotice(title: "Recorded without click highlights",
                                                 body: "The click highlights could not be filmed.")

    /// The highlights note after Stop: only when highlights were on at the start and their
    /// window was not filmed.
    static func noteAfterStop(onAtStart: Bool, missed: Bool) -> RecordingNotice? {
        onAtStart && missed ? notFilmedNotice : nil
    }
}
