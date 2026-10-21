import AppKit

/// The dashed outline just outside a scrolling capture's area (spec 2.8, The session). It takes
/// no clicks and no scrolls, so wheel events reach the app beneath; the stream excludes it with
/// the rest of TidyShot.
final class ScrollAreaFrameWindow: NSWindow {
    static let lineWidth: CGFloat = 2
    static let dash: [CGFloat] = [6, 4]
    /// How far the window reaches past the area on each side: the line and its halo.
    static let outset: CGFloat = lineWidth + 2

    /// `area` is in AppKit global points.
    init(area: CGRect) {
        super.init(contentRect: area.insetBy(dx: -Self.outset, dy: -Self.outset), styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        contentView = ScrollAreaFrameView(inset: Self.outset)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the adaptive two-tone stroke of spec 2.6 (white over a dark halo), entirely outside the
/// area, which is the view's bounds inset by `inset`.
final class ScrollAreaFrameView: NSView {
    private let inset: CGFloat

    init(inset: CGFloat) {
        self.inset = inset
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let halo = ScrollAreaFrameWindow.lineWidth + 2 / (window?.backingScaleFactor ?? 2)
        let area = bounds.insetBy(dx: inset, dy: inset)
        // Centred half the halo outside the area, so neither stroke covers an area pixel.
        let path = NSBezierPath(rect: area.insetBy(dx: -halo / 2, dy: -halo / 2))
        path.setLineDash(ScrollAreaFrameWindow.dash, count: ScrollAreaFrameWindow.dash.count, phase: 0)
        NSColor(white: 0, alpha: CrosshairStyle.haloAlpha).setStroke()
        path.lineWidth = halo
        path.stroke()
        NSColor.white.setStroke()
        path.lineWidth = ScrollAreaFrameWindow.lineWidth
        path.stroke()
    }
}
