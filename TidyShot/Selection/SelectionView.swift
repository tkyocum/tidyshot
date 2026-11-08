import AppKit

/// Draws the dimmed overlay, crosshair, drag rectangle, size label, window highlight and Record Screen's preset rect.
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
    /// Freeze screen: draw `snapshot` opaque under the dimming, so the screen looks stopped. Set
    /// with `snapshot`, only on a view whose display has a frozen snapshot.
    var isFrozen = false {
        didSet { if isFrozen != oldValue { needsDisplay = true } }
    }
    private var showsFrozenBackdrop: Bool { isFrozen && snapshot != nil }
    /// Frozen, the view paints every pixel, which lets AppKit skip compositing it over the window.
    override var isOpaque: Bool { showsFrozenBackdrop }
    /// Recomputed when the cursor moves or the snapshot arrives, never while drawing.
    private var crosshairStyle: CrosshairStyle = .outlined

    /// Record Screen's preset rect (a URL command's), set by the controller. Drawn as a hole
    /// with the selection stroke and its size; a click inside it records it.
    var presetRect: CGRect? {
        didSet { if presetRect != oldValue { needsDisplay = true } }
    }
    /// True while the current press started inside `presetRect`.

    private var dragStart: CGPoint?
    private var dragRect: CGRect?
    private var cursor: CGPoint?
    /// Set once an area selection completes; the hole stays open until the view is discarded.
    private var completedRect: CGRect?
    private var trackingArea: NSTrackingArea?
    /// The area the pointer's artwork covered at the last invalidation: the crosshair's two strips,
    /// the loupe, the drag or adjust rect with its label and handles, and the highlight or preset
    /// the pointer can hide or show. A pointer move repaints the union of the old and the new area
    /// instead of the display, which with Freeze on is a full snapshot blit per move.
    private var pointerArtwork: CGRect = .null

    // MARK: All-in-One state

    /// The adjustable selection on this display, view coordinates. Set through `beginAdjusting`
    /// (a drag, a window click, the preselected rect); a resize, move, nudge or typed size changes it.
    private(set) var adjustRect: CGRect?
    /// True while `adjustRect` came from a window click: the Window button is enabled.
    private(set) var adjustRectIsWindow = false
    /// Return, keypad Enter and a double-click capture only while this is true. A URL command's
    /// rect (spec 2.9) opens disarmed, so a key typed in another app as the overlay appears, or
    /// the second click of a double-click elsewhere, does not capture the sender's rect; a press
    /// in the view or a toolbar size, lock or action arms it, and a toolbar action pressed
    /// disarmed does nothing else. Arrows and Escape work disarmed. In the other modes (a URL
    /// command's window, self-timer or scrolling overlay) the controller sets it false and the
    /// first press only arms: no window pick and no drag.
    var keyCaptureArmed = true
    /// The toolbar's lock, from `settings.allInOneAspectLock` when the overlay opens.
    var isAspectLocked = false
    /// Width over height kept while locked. Set when the lock goes on and when a new rect is set while locked.
    private var lockedRatio: CGFloat?
    /// The Timer button's seconds, for its tooltip (`settings.selfTimerSeconds`).
    var timerSeconds = 0
    /// A new rect: `fromWindow` is true for a window click. The controller clears the other displays.
    var onAdjustRectSet: ((_ fromWindow: Bool) -> Void)?
    /// A press that resolved to nothing (no drag, no window, no rect here). The controller cancels
    /// unless another display holds a rect.
    var onEmptyClick: (() -> Void)?
    /// Capture, Window, Fullscreen, Scrolling or Timer, with the rect in AppKit global points.
    var onAllInOneAction: ((AllInOneAction, CGRect) -> Void)?
    var onAspectLockChanged: ((Bool) -> Void)?
    private enum AdjustDrag {
        case resize(SelectionHandle, CGRect)
        case move(start: CGPoint, original: CGRect)
    }
    private var adjustDrag: AdjustDrag?
    private var toolbar: AllInOneToolbar?

    private let dimColor = NSColor.black.withAlphaComponent(0.35)
    private let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

    override var acceptsFirstResponder: Bool { true }

    /// Clicks on a non-key overlay window (another screen) must register as mouseDown, not just activate.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        var options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        // All-in-One sets the cursor itself (see `updateAllInOneCursor`).
        if mode == .allInOne { options.insert(.cursorUpdate) }
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        // Overlapping cursor rects are undefined in AppKit, so All-in-One sets the cursor itself.
        guard mode != .allInOne else { return }
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        guard mode == .allInOne else {
            super.cursorUpdate(with: event)
            return
        }
        updateAllInOneCursor(at: convert(event.locationInWindow, from: nil))
    }

    // MARK: Mouse

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        cursor = nil
        invalidatePointerArtwork()
    }

    /// The pointer in AppKit global coordinates, for the controller's hover (`onMouseMoved`).
    private func reportPointer(_ event: NSEvent) {
        guard let window else { return }
        onMouseMoved?(window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin)
    }

    /// The whole-point rect between the press and the pointer.
    private static func dragRect(from start: CGPoint, to point: CGPoint) -> CGRect {
        CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
               width: abs(point.x - start.x), height: abs(point.y - start.y)).integral
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        updateAllInOneCursor(at: point)
        restyle(at: point)
        invalidatePointerArtwork()
        reportPointer(event)
    }

    override func mouseDown(with event: NSEvent) {
        if mode == .allInOne {
            allInOneMouseDown(event)
            return
        }
        // Disarmed, the press only arms: it may be the second click of a double-click begun
        // before the overlay appeared, on whatever window lies under it.
        guard keyCaptureArmed else {
            keyCaptureArmed = true
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        if mode == .allInOne {
            allInOneMouseDragged(event)
            return
        }
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        cursor = point
        restyle(at: point)
        dragRect = Self.dragRect(from: start, to: point)
        invalidatePointerArtwork()
        reportPointer(event)
    }

    override func mouseUp(with event: NSEvent) {
        if mode == .allInOne {
            allInOneMouseUp(event)
            return
        }
        // The press only armed (or started before the overlay): nothing to resolve.
        guard dragStart != nil else { return }
        defer {
            dragStart = nil
            dragRect = nil
            needsDisplay = true
        }
        switch SelectionOutcome.resolve(mode: mode, dragRect: dragRect, hasHighlight: highlightedRect != nil,
                                        clickInPreset: clickInPreset(releasedAt: convert(event.locationInWindow, from: nil))) {
        case .area(let rect):
            guard let window else {
                onCancel?()
                return
            }
            completedRect = rect
            onComplete?(window.convertToScreen(convert(rect, to: nil)))
        case .window:
            onPickWindow?()
        case .cancel:
            onCancel?()
        }
    }

    /// The preset rect when the press and the release were both inside it and there was no real
    /// drag; nil otherwise.
    private func clickInPreset(releasedAt point: CGPoint) -> CGRect? {
        guard let dragStart, let presetRect, presetRect.contains(dragStart), presetRect.contains(point) else { return nil }
        if let dragRect, dragRect.width >= SelectionOutcome.minimumDragSide,
           dragRect.height >= SelectionOutcome.minimumDragSide {
            return nil
        }
        return presetRect
    }

    override func keyDown(with event: NSEvent) {
        if mode == .allInOne {
            // Command or Control: not the overlay's, so Cmd-Return and Cmd-arrow neither capture
            // nor nudge. Shift-arrow stays the 10 pt nudge.
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else {
                super.keyDown(with: event)
                return
            }
            switch SelectionAdjust.keyCommand(keyCode: event.keyCode, hasRect: adjustRect != nil) {
            case .cancel?:
                onCancel?()
            case .capture?:
                if keyCaptureArmed { fireAllInOne(.capture) } else { super.keyDown(with: event) }
            case .nudge(let arrow)?:
                if let adjustRect {
                    self.adjustRect = SelectionAdjust.nudged(adjustRect, key: arrow,
                                                             shift: event.modifierFlags.contains(.shift), bounds: bounds)
                    layoutToolbar()
                    needsDisplay = true
                }
            case nil:
                super.keyDown(with: event)
            }
            return
        }
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        drawFrozenBackdrop(in: dirtyRect)
        dimColor.setFill()
        bounds.fill()

        if let completedRect {
            punchHole(completedRect)
            stroke(NSBezierPath(rect: completedRect.insetBy(dx: 0.5, dy: 0.5)))
            return
        }

        if mode == .allInOne, let adjustRect, dragRect == nil {
            punchHole(adjustRect)
            stroke(NSBezierPath(rect: adjustRect.insetBy(dx: 0.5, dy: 0.5)))
            drawHandles(on: adjustRect)
            if adjustDrag != nil { drawSizeLabel(for: adjustRect) }
            if case .resize = adjustDrag, let cursor { drawLoupe(at: cursor) }
            return
        }

        let isDragging = mode != .window && dragStart != nil && dragRect != nil

        if !isDragging, let presetRect {
            punchHole(presetRect)
            stroke(NSBezierPath(rect: presetRect.insetBy(dx: 0.5, dy: 0.5)))
            drawSizeLabel(for: presetRect)
        }
        // Over the preset a click records the preset, not the window, so no highlight is drawn there.
        let cursorInPreset = cursor.map { presetRect?.contains($0) ?? false } ?? false

        if isDragging, let rect = dragRect {
            punchHole(rect)
            stroke(NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5)))
            drawSizeLabel(for: rect)
        } else if !cursorInPreset, let highlight = highlightedRect {
            punchHole(highlight)
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: highlight.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()
            drawSizeLabel(for: highlight)
        }

        if let cursor, !isDragging, mode != .window {
            drawCrosshair(at: cursor)
        }

        if let cursor, mode != .window {
            drawLoupe(at: cursor)
        }
    }

    /// All-in-One's eight handles: white 8 pt knobs with a half-opaque black ring.
    private func drawHandles(on rect: CGRect) {
        let diameter: CGFloat = 8
        for handle in SelectionHandle.resizeHandles {
            guard let point = handle.point(on: rect) else { continue }
            let knob = NSBezierPath(ovalIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                                   width: diameter, height: diameter))
            NSColor.white.setFill()
            knob.fill()
            NSColor.black.withAlphaComponent(0.5).setStroke()
            knob.lineWidth = 1
            knob.stroke()
        }
    }

    private func punchHole(_ rect: CGRect) {
        guard showsFrozenBackdrop, let snapshot, let context = NSGraphicsContext.current?.cgContext else {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            return
        }
        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .none
        context.draw(snapshot, in: bounds)
        context.restoreGState()
    }

    /// The snapshot at one pixel per pixel, clipped to what needs drawing. Row 0 of a `CGImage`
    /// is the top, which is the top of this non-flipped view when the image fills `bounds`.
    private func drawFrozenBackdrop(in dirtyRect: NSRect) {
        guard showsFrozenBackdrop, let snapshot, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: dirtyRect)
        context.interpolationQuality = .none
        context.draw(snapshot, in: bounds)
        context.restoreGState()
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

    /// Picks the style for `point`. A change recolours every two-tone line, the preset's and the
    /// completed rect's included, so it repaints the whole view; that happens only when the pointer
    /// crosses between a light and a dark area.
    private func restyle(at point: CGPoint?) {
        let style = style(at: point)
        guard style != crosshairStyle else { return }
        crosshairStyle = style
        needsDisplay = true
    }

    /// Repaints what the pointer's artwork covered and covers (see `pointerArtwork`).
    private func invalidatePointerArtwork() {
        let now = pointerArtworkRect()
        let dirty = now.union(pointerArtwork)
        if !dirty.isNull { setNeedsDisplay(dirty) }
        pointerArtwork = now
    }

    /// Everything `draw(_:)` paints that the pointer moves or can hide: a superset is fine, a miss
    /// leaves a stale line.
    private func pointerArtworkRect() -> CGRect {
        var area = CGRect.null
        // A two-tone line is 1 pt plus a halo of one device pixel on each side.
        let line: CGFloat = 3
        if let cursor, mode != .window {
            area = area.union(CGRect(x: bounds.minX, y: cursor.y - line, width: bounds.width, height: 2 * line))
            area = area.union(CGRect(x: cursor.x - line, y: bounds.minY, width: 2 * line, height: bounds.height))
            area = area.union(loupeFrame(at: cursor).insetBy(dx: -2, dy: -2))
        }
        // Each with its border and handles, and the label it may carry.
        for rect in [dragRect, mode == .allInOne ? adjustRect : nil, highlightedRect, presetRect].compactMap({ $0 }) {
            area = area.union(rect.insetBy(dx: -8, dy: -8)).union(sizeLabel(for: rect).frame)
        }
        return area
    }

    private static let labelPadding = CGSize(width: 12, height: 6)

    /// The size label's pill, text and attributes for `rect`: 6 pt under its bottom-left corner,
    /// else above it, else inside its bottom edge, and kept inside the view.
    private func sizeLabel(for rect: CGRect) -> (frame: CGRect, text: NSString, attributes: [NSAttributedString.Key: Any]) {
        let text = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attributes)
        let padding = Self.labelPadding
        var origin = CGPoint(x: rect.minX, y: rect.minY - textSize.height - padding.height - 6)
        if origin.y < bounds.minY + 4 {
            origin.y = rect.maxY + 6
        }
        if origin.y + textSize.height + padding.height > bounds.maxY {
            origin.y = rect.minY + 6
        }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - textSize.width - padding.width - 4)
        let frame = CGRect(origin: origin, size: CGSize(width: textSize.width + padding.width, height: textSize.height + padding.height))
        return (frame, text, attributes)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let label = sizeLabel(for: rect)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: label.frame, xRadius: 4, yRadius: 4).fill()
        label.text.draw(at: CGPoint(x: label.frame.minX + Self.labelPadding.width / 2, y: label.frame.minY + Self.labelPadding.height / 2),
                        withAttributes: label.attributes)
    }

    /// The loupe shows this many points of the screen around the cursor, magnified `loupeZoom` times.
    private static let loupeRegionPoints: CGFloat = 16
    private static let loupeZoom: CGFloat = 8

    /// Where the loupe sits for a cursor at `point`: below and to the right of it, else to the
    /// left, else above.
    private func loupeFrame(at point: CGPoint) -> CGRect {
        let diameter = Self.loupeRegionPoints * Self.loupeZoom
        var origin = CGPoint(x: point.x + 24, y: point.y - 24 - diameter)
        if origin.x + diameter > bounds.maxX { origin.x = point.x - 24 - diameter }
        if origin.y < bounds.minY { origin.y = point.y + 24 }
        return CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
    }

    private func drawLoupe(at point: CGPoint) {
        guard let snapshot, let context = NSGraphicsContext.current?.cgContext else { return }
        let regionPoints = Self.loupeRegionPoints
        let pixelsToPoints = Self.loupeZoom / snapshotScale

        // Source region in snapshot pixels. CGImage rows run top to bottom; the view's y runs bottom to top.
        let half = regionPoints * snapshotScale / 2
        let centreX = point.x * snapshotScale
        let centreY = (bounds.height - point.y) * snapshotScale
        let source = CGRect(x: centreX - half, y: centreY - half, width: half * 2, height: half * 2)
        let imageRect = CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
        let visible = source.intersection(imageRect)
        guard !visible.isEmpty, let cropped = snapshot.cropping(to: visible) else { return }

        let destination = loupeFrame(at: point)

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

// MARK: All-in-One

extension SelectionView {
    /// A new rect (view coordinates, on this display): handles and toolbar appear. While locked,
    /// its ratio becomes the one kept. `armed` false (a URL command's rect) leaves Return, Enter
    /// and a double-click unable to capture until the user touches the overlay.
    func beginAdjusting(_ rect: CGRect, fromWindow: Bool, armed: Bool = true) {
        keyCaptureArmed = armed
        adjustRect = rect
        adjustRectIsWindow = fromWindow
        lockedRatio = isAspectLocked && rect.height > 0 ? rect.width / rect.height : nil
        layoutToolbar()
        needsDisplay = true
    }

    /// Another display took the selection.
    func clearAdjustRect() {
        adjustRect = nil
        adjustRectIsWindow = false
        lockedRatio = nil
        adjustDrag = nil
        layoutToolbar()
        needsDisplay = true
    }

    fileprivate func allInOneMouseDown(_ event: NSEvent) {
        // The press arms Return and the double-click; this press itself counts only if armed before.
        let wasArmed = keyCaptureArmed
        keyCaptureArmed = true
        let point = convert(event.locationInWindow, from: nil)
        dragRect = nil
        guard let adjustRect,
              let handle = SelectionAdjust.handle(at: point, rect: adjustRect, tolerance: SelectionAdjust.handleTolerance) else {
            dragStart = point // a new rect, or a click outside
            return
        }
        if handle == .inside {
            if event.clickCount == 2, wasArmed {
                fireAllInOne(.capture)
                return
            }
            adjustDrag = .move(start: point, original: adjustRect)
        } else {
            adjustDrag = .resize(handle, adjustRect)
        }
    }

    fileprivate func allInOneMouseDragged(_ event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        // The rect stays on this display: the pointer is clamped to it.
        let point = CGPoint(x: min(max(raw.x, bounds.minX), bounds.maxX), y: min(max(raw.y, bounds.minY), bounds.maxY))
        cursor = point
        restyle(at: point)
        switch adjustDrag {
        case .resize(let handle, let original):
            adjustRect = SelectionAdjust.resized(original, handle: handle, to: point, lockedRatio: lockedRatio,
                                                 bounds: bounds, minSide: SelectionAdjust.minSide)
        case .move(let start, let original):
            adjustRect = SelectionAdjust.moved(original, by: CGVector(dx: point.x - start.x, dy: point.y - start.y),
                                               bounds: bounds)
        case nil:
            guard let start = dragStart else { return }
            dragRect = Self.dragRect(from: start, to: point)
        }
        toolbar?.isHidden = true
        updateAllInOneCursor(at: point)
        invalidatePointerArtwork()
        reportPointer(event)
    }

    fileprivate func allInOneMouseUp(_ event: NSEvent) {
        defer {
            dragStart = nil
            dragRect = nil
            adjustDrag = nil
            layoutToolbar()
            updateAllInOneCursor(at: cursor)
            needsDisplay = true
        }
        // A resize or move already changed the rect; a double-click already fired.
        guard adjustDrag == nil, dragStart != nil else { return }
        switch SelectionOutcome.resolve(mode: .allInOne, dragRect: dragRect, hasHighlight: highlightedRect != nil) {
        case .area(let rect):
            beginAdjusting(SelectionAdjust.fitted(rect, in: bounds), fromWindow: false)
            onAdjustRectSet?(false)
        case .window:
            guard let highlightedRect else { return }
            beginAdjusting(SelectionAdjust.fitted(highlightedRect, in: bounds), fromWindow: true)
            onAdjustRectSet?(true)
        case .cancel:
            if adjustRect == nil { onEmptyClick?() }
        }
    }

    /// Shows the toolbar under (or above, or inside) the rect, or hides it while there is no rect
    /// or a drag, resize or move runs. The menu bar's safe-area inset is left free at the top.
    fileprivate func layoutToolbar() {
        guard mode == .allInOne, let adjustRect, adjustDrag == nil, dragRect == nil else {
            toolbar?.isHidden = true
            return
        }
        let toolbar = self.toolbar ?? makeToolbar()
        toolbar.update(size: adjustRect.size, locked: isAspectLocked, windowEnabled: adjustRectIsWindow)
        var screenBounds = bounds
        screenBounds.size.height -= window?.screen?.safeAreaInsets.top ?? 0
        toolbar.frame = AllInOneToolbarPlacement.frame(toolbarSize: toolbar.fittingSize, selection: adjustRect,
                                                       screenBounds: screenBounds)
        toolbar.isHidden = false
    }

    private func makeToolbar() -> AllInOneToolbar {
        let toolbar = AllInOneToolbar(timerSeconds: timerSeconds)
        toolbar.onAction = { [weak self] action in
            guard let self else { return }
            // Disarmed, a button only arms: the sender's rect placed the toolbar, so the second
            // click of a double-click could land on Fullscreen. Cancel still cancels, as Escape does.
            let wasArmed = keyCaptureArmed
            keyCaptureArmed = true
            window?.makeFirstResponder(self)
            if action == .cancel { onCancel?() } else if wasArmed { fireAllInOne(action) }
        }
        toolbar.onSize = { [weak self] width, height in
            guard let self, let adjustRect else { return }
            keyCaptureArmed = true
            self.adjustRect = SelectionAdjust.sized(adjustRect, width: width.map { CGFloat($0) },
                                                    height: height.map { CGFloat($0) },
                                                    lockedRatio: lockedRatio, bounds: bounds)
            layoutToolbar()
            needsDisplay = true
        }
        toolbar.onToggleLock = { [weak self] in
            guard let self else { return }
            keyCaptureArmed = true
            isAspectLocked.toggle()
            lockedRatio = isAspectLocked ? adjustRect.flatMap { $0.height > 0 ? $0.width / $0.height : nil } : nil
            onAspectLockChanged?(isAspectLocked)
            window?.makeFirstResponder(self)
            layoutToolbar()
        }
        // Layout runs after editing ends, so `update` writes the clamped or moved size back.
        toolbar.onFieldDone = { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
            layoutToolbar()
        }
        toolbar.frame.size = toolbar.fittingSize
        addSubview(toolbar)
        self.toolbar = toolbar
        return toolbar
    }

    /// Hands the rect, in AppKit global points, to the controller. Window only while the rect
    /// came from a window click.
    fileprivate func fireAllInOne(_ action: AllInOneAction) {
        guard let adjustRect, let window, action.isEnabled(hasWindow: adjustRectIsWindow) else { return }
        onAllInOneAction?(action, window.convertToScreen(convert(adjustRect, to: nil)))
    }

    /// Arrow over the toolbar, the resize cursor over a handle, an open hand inside (closed while
    /// moving), the crosshair elsewhere. A resize keeps its handle's cursor while it runs.
    fileprivate func updateAllInOneCursor(at point: CGPoint?) {
        guard mode == .allInOne else { return }
        switch adjustDrag {
        case .move?:
            NSCursor.closedHand.set()
            return
        case .resize(let handle, _)?:
            resizeCursor(for: handle).set()
            return
        case nil:
            // A new rect is being drawn over the old one: keep the crosshair.
            if dragRect != nil { NSCursor.crosshair.set(); return }
        }
        if let point, let toolbar, !toolbar.isHidden, toolbar.frame.contains(point) { NSCursor.arrow.set(); return }
        guard let point, let adjustRect,
              let handle = SelectionAdjust.handle(at: point, rect: adjustRect, tolerance: SelectionAdjust.handleTolerance) else {
            NSCursor.crosshair.set()
            return
        }
        resizeCursor(for: handle).set()
    }

    private func resizeCursor(for handle: SelectionHandle) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch handle {
        case .inside: return .openHand
        case .topLeft: position = .topLeft
        case .top: position = .top
        case .topRight: position = .topRight
        case .right: position = .right
        case .bottomRight: position = .bottomRight
        case .bottom: position = .bottom
        case .bottomLeft: position = .bottomLeft
        case .left: position = .left
        }
        return .frameResize(position: position, directions: .all)
    }
}
