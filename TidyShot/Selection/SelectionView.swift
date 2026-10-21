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

    /// Screenshot of this view's display, in pixels, used by the loupe and to pick the crosshair
    /// colour.
    var snapshot: CGImage? {
        didSet {
            crosshairStyle = style(at: cursor)
            needsDisplay = true
        }
    }
    var snapshotScale: CGFloat = 2
    /// Recomputed when the cursor moves or the snapshot arrives, never while drawing.
    private var crosshairStyle: CrosshairStyle = .outlined

    private var dragStart: CGPoint?
    private var dragRect: CGRect?
    private var cursor: CGPoint?
    /// Set once an area selection completes; the hole stays open until the view is discarded.
    private var completedRect: CGRect?
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
        crosshairStyle = style(at: point)
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
        crosshairStyle = style(at: point)
        dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y)).integral
        needsDisplay = true
        if let window {
            let global = window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
            onMouseMoved?(global)
        }
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
            completedRect = rect
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

        if let completedRect {
            punchHole(completedRect)
            stroke(NSBezierPath(rect: completedRect.insetBy(dx: 0.5, dy: 0.5)))
            return
        }

        let isDragging = mode == .area && dragStart != nil && dragRect != nil

        if isDragging, let rect = dragRect {
            punchHole(rect)
            stroke(NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)))
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

        if let cursor, mode == .area {
            drawLoupe(at: cursor)
        }
    }

    private func punchHole(_ rect: CGRect) {
        NSColor.clear.setFill()
        rect.fill(using: .copy)
    }

    private func drawCrosshair(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.minX, y: point.y + 0.5))
        path.line(to: CGPoint(x: bounds.maxX, y: point.y + 0.5))
        path.move(to: CGPoint(x: point.x + 0.5, y: bounds.minY))
        path.line(to: CGPoint(x: point.x + 0.5, y: bounds.maxY))
        stroke(path)
    }

    /// Strokes `path` two-tone in the current `crosshairStyle`. Used for the crosshair, the drag
    /// and completed rectangle borders, and the loupe's cross. First a halo one device pixel wider
    /// on each side in the halo colour at `CrosshairStyle.haloAlpha`, then the 1 pt line in the line
    /// colour at `CrosshairStyle.lineAlpha`: black over white on light backgrounds, white over
    /// black on dark ones and before the snapshot arrives. Each tone is one stroke of the whole
    /// path, so where lines cross the halo is not painted twice.
    private func stroke(_ path: NSBezierPath) {
        NSColor(white: crosshairStyle.haloWhite, alpha: CrosshairStyle.haloAlpha).setStroke()
        path.lineWidth = 1 + 2 / (window?.backingScaleFactor ?? 2)
        path.stroke()
        NSColor(white: crosshairStyle.lineWhite, alpha: CrosshairStyle.lineAlpha).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// The style for the snapshot under `point` (view coordinates): the mean luminance of a
    /// `Luminance.sampleSide` point square around it. `.outlined` without a snapshot or a cursor.
    private func style(at point: CGPoint?) -> CrosshairStyle {
        guard let point, let snapshot else { return .outlined }
        // Snapshot pixels run top to bottom; the view's y runs bottom to top.
        let side = Luminance.sampleSide * snapshotScale
        let centre = CGPoint(x: point.x * snapshotScale, y: (bounds.height - point.y) * snapshotScale)
        let rect = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        return CrosshairStyle(luminance: Luminance.mean(of: snapshot, in: rect))
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

    private func drawLoupe(at point: CGPoint) {
        guard let snapshot, let context = NSGraphicsContext.current?.cgContext else { return }
        let regionPoints: CGFloat = 16
        let zoom: CGFloat = 8
        let diameter = regionPoints * zoom
        let pixelsToPoints = zoom / snapshotScale

        // Source region in snapshot pixels. CGImage rows run top to bottom; the view's y runs bottom to top.
        let half = regionPoints * snapshotScale / 2
        let centreX = point.x * snapshotScale
        let centreY = (bounds.height - point.y) * snapshotScale
        let source = CGRect(x: centreX - half, y: centreY - half, width: half * 2, height: half * 2)
        let imageRect = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        let visible = source.intersection(imageRect)
        guard !visible.isEmpty, let cropped = snapshot.cropping(to: visible) else { return }

        var origin = CGPoint(x: point.x + 24, y: point.y - 24 - diameter)
        if origin.x + diameter > bounds.maxX { origin.x = point.x - 24 - diameter }
        if origin.y < bounds.minY { origin.y = point.y + 24 }
        let destination = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))

        // Where the visible part lands inside the circle. Image y is flipped relative to the view.
        let drawRect = CGRect(x: destination.minX + (visible.minX - source.minX) * pixelsToPoints,
                              y: destination.minY + (source.maxY - visible.maxY) * pixelsToPoints,
                              width: visible.width * pixelsToPoints,
                              height: visible.height * pixelsToPoints)

        context.saveGState()
        context.addEllipse(in: destination)
        context.clip()
        context.setFillColor(NSColor.black.cgColor)
        context.fill(destination)
        context.interpolationQuality = .none
        context.draw(cropped, in: drawRect)
        context.restoreGState()

        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: destination.minX, y: destination.midY + 0.5))
        cross.line(to: CGPoint(x: destination.maxX, y: destination.midY + 0.5))
        cross.move(to: CGPoint(x: destination.midX + 0.5, y: destination.minY))
        cross.line(to: CGPoint(x: destination.midX + 0.5, y: destination.maxY))
        stroke(cross)

        let ring = NSBezierPath(ovalIn: destination.insetBy(dx: 1, dy: 1))
        ring.lineWidth = 2
        NSColor.white.setStroke()
        ring.stroke()
    }
}
