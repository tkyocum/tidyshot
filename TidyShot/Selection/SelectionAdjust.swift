import CoreGraphics

/// The eight handles of All-in-One's adjustable selection, plus its inside (a move). In the
/// selection view's coordinates, bottom-left origin: `.top` is the edge at `maxY`.
nonisolated enum SelectionHandle: Equatable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case inside

    /// The eight resize handles, in drawing order.
    static let resizeHandles: [SelectionHandle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]

    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var movesMaxY: Bool { self == .topLeft || self == .top || self == .topRight }

    /// Where the handle's knob is drawn: a corner, or an edge's midpoint. Nil for `.inside`.
    func point(on rect: CGRect) -> CGPoint? {
        guard self != .inside else { return nil }
        let x = movesMinX ? rect.minX : movesMaxX ? rect.maxX : rect.midX
        let y = movesMinY ? rect.minY : movesMaxY ? rect.maxY : rect.midY
        return CGPoint(x: x, y: y)
    }
}

/// All-in-One's selection arithmetic (spec 2.9): hit testing, resize, move, nudge, typed size,
/// aspect lock and the restored rect. Pure. Every rect is in the selection view's coordinates
/// (bottom-left origin, y up) or, for `restored`, AppKit global points; `bounds` is the display
/// the rect lives on. Results are whole points, as the overlay's drag rect is `integral`.
nonisolated enum SelectionAdjust {
    static let minSide: CGFloat = 4
    /// How far from an edge, in points, a press still takes that edge's handle.
    static let handleTolerance: CGFloat = 6
    static let nudgeStep: CGFloat = 1
    static let shiftNudgeStep: CGFloat = 10

    enum Arrow: Equatable, Sendable {
        case left, right, up, down

        /// The arrow keys' virtual key codes.
        init?(keyCode: UInt16) {
            switch keyCode {
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            default: return nil
            }
        }
    }

    /// What a key does in All-in-One while no text field is editing.
    enum KeyCommand: Equatable, Sendable {
        case capture
        case cancel
        case nudge(Arrow)
    }

    /// Escape (53) cancels always. Return (36) and keypad Enter (76) capture, and arrows nudge,
    /// only once a rect exists. Anything else is not the overlay's (nil).
    static func keyCommand(keyCode: UInt16, hasRect: Bool) -> KeyCommand? {
        if keyCode == 53 { return .cancel }
        guard hasRect else { return nil }
        if keyCode == 36 || keyCode == 76 { return .capture }
        return Arrow(keyCode: keyCode).map(KeyCommand.nudge)
    }

    /// The handle under `point`: a corner within `tolerance` of both its edges, an edge within
    /// `tolerance` anywhere along it, `.inside` further in, nil further out (a new rect). On a
    /// rect narrower than two tolerances both sides are in reach and the nearer one wins.
    static func handle(at point: CGPoint, rect: CGRect, tolerance: CGFloat) -> SelectionHandle? {
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0 else { return nil }
        guard point.x >= rect.minX - tolerance, point.x <= rect.maxX + tolerance,
              point.y >= rect.minY - tolerance, point.y <= rect.maxY + tolerance else { return nil }
        let toMinX = abs(point.x - rect.minX)
        let toMaxX = abs(point.x - rect.maxX)
        let toMinY = abs(point.y - rect.minY)
        let toMaxY = abs(point.y - rect.maxY)
        let left = toMinX <= tolerance && toMinX <= toMaxX
        let right = !left && toMaxX <= tolerance
        let bottom = toMinY <= tolerance && toMinY <= toMaxY
        let top = !bottom && toMaxY <= tolerance
        switch (left, right, bottom, top) {
        case (true, _, _, true): return .topLeft
        case (true, _, true, _): return .bottomLeft
        case (_, true, _, true): return .topRight
        case (_, true, true, _): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .bottom
        case (_, _, _, true): return .top
        default: return rect.contains(point) ? .inside : nil
        }
    }

    /// `rect` with `handle` dragged to `point`. The pointer is clamped to `bounds`; the handle's
    /// edges follow it and the opposite ones stay; a moving edge stops `minSide` short of the edge
    /// opposite it, so the rect never flips. With `lockedRatio` (width over height) the ratio holds:
    /// see `lockedResize`. `.inside` returns `rect` (a move is `moved`).
    static func resized(_ rect: CGRect, handle: SelectionHandle, to point: CGPoint, lockedRatio: CGFloat?,
                        bounds: CGRect, minSide: CGFloat) -> CGRect {
        guard handle != .inside else { return rect }
        let p = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY))
        if let ratio = usableRatio(lockedRatio) {
            return lockedResize(rect, handle: handle, to: p, ratio: ratio, bounds: bounds, minSide: minSide)
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX { minX = min(p.x, maxX - minSide) }
        if handle.movesMaxX { maxX = max(p.x, minX + minSide) }
        if handle.movesMinY { minY = min(p.y, maxY - minSide) }
        if handle.movesMaxY { maxY = max(p.y, minY + minSide) }
        return fitted(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), in: bounds)
    }

    /// A corner takes the larger of the pointer's width and its height times the ratio, so the
    /// rect reaches the pointer; an edge sets its own side and the other side grows about the
    /// rect's centre. The short side is at least `minSide`. The width is then limited by the room
    /// from the fixed edges to `bounds` (all of `bounds` along a centred side), and `fitted` moves
    /// a centred side inside.
    private static func lockedResize(_ rect: CGRect, handle: SelectionHandle, to p: CGPoint, ratio: CGFloat,
                                     bounds: CGRect, minSide: CGFloat) -> CGRect {
        let horizontal = handle.movesMinX || handle.movesMaxX
        let vertical = handle.movesMinY || handle.movesMaxY
        let pointerWidth = max(handle.movesMaxX ? p.x - rect.minX : rect.maxX - p.x, 0)
        let pointerHeight = max(handle.movesMaxY ? p.y - rect.minY : rect.maxY - p.y, 0)
        var width: CGFloat
        if horizontal && vertical {
            width = max(pointerWidth, pointerHeight * ratio)
        } else if horizontal {
            width = pointerWidth
        } else {
            width = pointerHeight * ratio
        }
        width = max(width, minSide, minSide * ratio)
        let roomWidth = horizontal ? (handle.movesMaxX ? bounds.maxX - rect.minX : rect.maxX - bounds.minX) : bounds.width
        let roomHeight = vertical ? (handle.movesMaxY ? bounds.maxY - rect.minY : rect.maxY - bounds.minY) : bounds.height
        width = min(width, roomWidth, roomHeight * ratio)
        let height = width / ratio
        let x = horizontal ? (handle.movesMaxX ? rect.minX : rect.maxX - width) : rect.midX - width / 2
        let y = vertical ? (handle.movesMaxY ? rect.minY : rect.maxY - height) : rect.midY - height / 2
        return fitted(CGRect(x: x, y: y, width: width, height: height), in: bounds)
    }

    /// `rect` moved by `delta`, kept inside `bounds` with its size.
    static func moved(_ rect: CGRect, by delta: CGVector, bounds: CGRect) -> CGRect {
        fitted(rect.offsetBy(dx: delta.dx, dy: delta.dy), in: bounds)
    }

    /// An arrow key: 1 pt, 10 pt with Shift. Up is +y in the view's coordinates.
    static func nudged(_ rect: CGRect, key: Arrow, shift: Bool, bounds: CGRect) -> CGRect {
        let step = shift ? shiftNudgeStep : nudgeStep
        let delta = switch key {
        case .left: CGVector(dx: -step, dy: 0)
        case .right: CGVector(dx: step, dy: 0)
        case .up: CGVector(dx: 0, dy: step)
        case .down: CGVector(dx: 0, dy: -step)
        }
        return moved(rect, by: delta, bounds: bounds)
    }

    /// The W and H fields. A nil side keeps its value, or with `lockedRatio` follows the typed one
    /// (the width wins when both are given). The rect grows from its top-left corner (`minX`,
    /// `maxY` here); it is limited to `bounds` (with the lock both sides shrink together) and
    /// moved inside them. Each side is at least `minSide`.
    static func sized(_ rect: CGRect, width: CGFloat?, height: CGFloat?, lockedRatio: CGFloat?, bounds: CGRect) -> CGRect {
        var w = width ?? rect.width
        var h = height ?? rect.height
        if let ratio = usableRatio(lockedRatio) {
            if width != nil {
                h = w / ratio
            } else if height != nil {
                w = h * ratio
            }
            if w < minSide || h < minSide {
                (w, h) = ratio >= 1 ? (minSide * ratio, minSide) : (minSide, minSide / ratio)
            }
            let shrink = min(1, bounds.width / w, bounds.height / h)
            w *= shrink
            h *= shrink
        } else {
            w = min(max(w, minSide), bounds.width)
            h = min(max(h, minSide), bounds.height)
        }
        return fitted(CGRect(x: rect.minX, y: rect.maxY - h, width: w, height: h), in: bounds)
    }

    /// All-in-One's starting rect from the remembered one: on the display holding its centre (the
    /// first, when frames overlap), clipped to it. Nil when no display holds the centre or less
    /// than `minSide` is left on a side. `rect` and `displayFrames` share one coordinate space.
    static func restored(_ rect: CGRect, displayFrames: [CGRect]) -> CGRect? {
        guard !rect.isNull, !rect.isInfinite else { return nil }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard let frame = displayFrames.first(where: { $0.contains(centre) }) else { return nil }
        let clipped = rect.intersection(frame)
        guard clipped.width >= minSide, clipped.height >= minSide else { return nil }
        return fitted(clipped, in: frame)
    }

    /// `rect` in whole points (origin and size rounded), no larger than `bounds`, moved inside them.
    static func fitted(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let width = min(rect.width.rounded(), bounds.width)
        let height = min(rect.height.rounded(), bounds.height)
        let x = min(max(rect.minX.rounded(), bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY.rounded(), bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func usableRatio(_ ratio: CGFloat?) -> CGFloat? {
        guard let ratio, ratio.isFinite, ratio > 0 else { return nil }
        return ratio
    }
}
