import AppKit

/// Draws the dimmed overlay, crosshair, drag rectangle, size label, and window highlight.
/// All stored rects and points are in this view's coordinates (bottom-left origin).
final class SelectionView: NSView {
    var mode: SelectionMode = .area
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onMouseMoved: ((CGPoint) -> Void)?
    var onPickWindow: (() -> Void)?

    /// Window frame under the cursor, set by the controller. Drawn as a clear hole with an accent border.
    var highlightedRect: CGRect? {
        didSet { if highlightedRect != oldValue { needsDisplay = true } }
    }

    private var dragStart: CGPoint?
    private var dragRect: CGRect?
    private var cursor: CGPoint?
    private var trackingArea: NSTrackingArea?

    private let dimColor = NSColor.black.withAlphaComponent(0.35)
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    /// Clicks on a non-key overlay window (another screen) must register as mouseDown, not just activate.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        needsDisplay = true
        if let window {
            let global = window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
            onMouseMoved?(global)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y)).integral
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragRect = nil
            needsDisplay = true
        }
        if mode == .area, let rect = dragRect, rect.width >= 2, rect.height >= 2 {
            guard let window else {
                onCancel?()
                return
            }
            onComplete?(window.convertToScreen(convert(rect, to: nil)))
        } else if highlightedRect != nil {
            onPickWindow?()
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        dimColor.setFill()
        bounds.fill()

        let isDragging = mode == .area && dragStart != nil && dragRect != nil

        if isDragging, let rect = dragRect {
            punchHole(rect)
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            drawSizeLabel(for: rect)
        } else if let highlight = highlightedRect {
            punchHole(highlight)
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
            drawSizeLabel(for: highlight)
        }

        if let cursor, !isDragging, mode == .area {
            drawCrosshair(at: cursor)
        }
    }

    private func punchHole(_ rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill(using: .copy)
    }

    private func drawCrosshair(at point: CGPoint) {
        NSColor.white.withAlphaComponent(0.8).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: bounds.minX, y: point.y + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y + 0.5))
        path.move(to: CGPoint(x: point.x + 0.5, y: bounds.minY))
        path.line(to: CGPoint(x: point.x + 0.5, y: bounds.maxY))
        path.stroke()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attributes)
        let padding = CGSize(width: 12, height: 6)
        var origin = CGPoint(x: rect.minX, y: rect.minY - textSize.height - padding.height - 6)
        if origin.y < bounds.minY + 4 {
            origin.y = rect.maxY + 6
        }
        if origin.y + textSize.height + padding.height > bounds.maxY {
            origin.y = rect.minY + 6
        }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - textSize.width - padding.width - 4)
        let background = CGRect(origin: origin, size: CGSize(width: textSize.width + padding.width, height: textSize.height + padding.height))
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: origin.x + padding.width / 2, y: origin.y + padding.height / 2), withAttributes: attributes)
    }
}
