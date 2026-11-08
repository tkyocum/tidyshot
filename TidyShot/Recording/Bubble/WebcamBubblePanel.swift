import AppKit
import QuartzCore

/// The webcam bubble's window (design, Webcam bubble, The window): a round, borderless panel in
/// the recorded rect that the recording films as an excepted window. It shows the camera's preview
/// cropped to a circle, drags inside the recorded rect and steps its size on a double-click. While
/// the bubble is off it stays on screen, draws nothing and lets clicks through.
final class WebcamBubblePanel: OverlayPanel {
    /// The circle before the first frame and behind the loss symbol.
    static let grey = CGColor(gray: 0.15, alpha: 1)
    static let lossSymbolName = "video.slash"
    /// The loss symbol's side, as a fraction of the diameter.
    static let lossSymbolFraction: CGFloat = 0.4

    /// The camera's `AVCaptureVideoPreviewLayer`, or a plain layer when there is no camera.
    let preview: CALayer
    /// The 2 pt white edge, above the preview.
    let border = CAShapeLayer()
    /// White, masked by `video.slash`; shown only after a loss.
    let lossSymbol = CALayer()

    /// AppKit points: the area, or the display's visible frame for fullscreen.
    var recorded: CGRect
    private(set) var size: BubbleSize
    private(set) var isPictureShown = true
    private(set) var isLost = false

    /// A drag ended where the bubble now is.
    var onDragEnded: (CGRect) -> Void = { _ in }
    /// A double-click stepped the size; the bubble's new frame.
    var onSizeStepped: (BubbleSize, CGRect) -> Void = { _, _ in }
    /// Any left click on the bubble, before it acts on it.
    var onInteraction: () -> Void = {}

    /// The frame and pointer when the drag began, and whether the bubble has moved since.
    private var drag: (frame: CGRect, pointer: CGPoint, moved: Bool)?

    init(preview: CALayer, size: BubbleSize, frame: CGRect, recorded: CGRect) {
        self.preview = preview
        self.size = size
        self.recorded = recorded
        // No shadow: it would be filmed as a dark halo.
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], level: .floating,
                   collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle], hasShadow: false)

        let view = BubbleView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        if let circle = view.layer {
            circle.masksToBounds = true
            circle.backgroundColor = Self.grey
            circle.addSublayer(preview)
            circle.addSublayer(lossSymbol)
            circle.addSublayer(border)
        }
        border.lineWidth = 2
        border.strokeColor = CGColor(gray: 1, alpha: 0.85)
        border.fillColor = nil
        lossSymbol.backgroundColor = CGColor(gray: 1, alpha: 1)
        lossSymbol.mask = CALayer()
        lossSymbol.mask?.contentsGravity = .resizeAspect
        lossSymbol.isHidden = true
        view.onResize = { [weak self] in self?.layoutLayers() }
        view.onBackingChange = { [weak self] in self?.updateScale() }
        contentView = view
        layoutLayers()
        updateScale()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        onInteraction()
        if event.clickCount == 2 {
            drag = nil
            stepSize()
        } else {
            drag = (frame, NSEvent.mouseLocation, false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = drag else { return }
        let moved = BubblePlacement.drag(startFrame: start.frame, from: start.pointer,
                                         to: NSEvent.mouseLocation, in: recorded)
        setFrame(moved, display: true)
        drag?.moved = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        if drag?.moved == true { onDragEnded(frame) }
    }

    /// A right-click does nothing.
    override func rightMouseDown(with event: NSEvent) {}

    // MARK: Size and place

    /// The next size about the same centre, clamped into the recorded rect.
    func stepSize() {
        let next = size.next
        let stepped = BubblePlacement.step(frame, to: next, in: recorded)
        size = next
        setFrame(stepped, display: true)
        onSizeStepped(next, stepped)
    }

    /// The recorded rect changed: the whole bubble back inside it.
    func reclamp(into recorded: CGRect) {
        self.recorded = recorded
        setFrame(BubblePlacement.clamp(frame, into: recorded), display: true)
    }

    // MARK: Picture

    /// Off hides the preview, the border and the loss symbol at once and lets clicks through, so
    /// the window stays on screen, filmed and invisible; on brings them back.
    func setPictureShown(_ shown: Bool) {
        isPictureShown = shown
        ignoresMouseEvents = !shown
        updatePicture()
    }

    /// After a loss the circle shows `video.slash` on grey in place of the preview.
    func setLost(_ lost: Bool) {
        isLost = lost
        updatePicture()
    }

    /// No fade: nothing is filmed after the picture goes.
    private func updatePicture() {
        CATransaction.withoutActions {
            contentView?.layer?.backgroundColor = isPictureShown ? Self.grey : nil
            preview.isHidden = !isPictureShown || isLost
            border.isHidden = !isPictureShown
            lossSymbol.isHidden = !isPictureShown || !isLost
        }
    }

    private func layoutLayers() {
        guard let view = contentView, let circle = view.layer else { return }
        let bounds = view.bounds
        let side = bounds.width
        CATransaction.withoutActions {
            circle.cornerRadius = side / 2
            preview.frame = bounds
            border.frame = bounds
            // The stroke lies inside the circle's edge.
            let inset = border.lineWidth / 2
            border.path = CGPath(ellipseIn: bounds.insetBy(dx: inset, dy: inset), transform: nil)
            let symbol = side * Self.lossSymbolFraction
            lossSymbol.frame = CGRect(x: (side - symbol) / 2, y: (side - symbol) / 2, width: symbol, height: symbol)
            lossSymbol.mask?.frame = lossSymbol.bounds
        }
    }

    /// Every layer at the screen's backing scale, the symbol drawn again at it.
    private func updateScale() {
        let scale = backingScaleFactor
        CATransaction.withoutActions {
            for layer in [preview, border, lossSymbol] { layer.contentsScale = scale }
            if let mask = lossSymbol.mask {
                // Drawn once at Large's size, so every size scales it down.
                let pointSize = BubbleSize.large.diameter * Self.lossSymbolFraction
                let image = NSImage(systemSymbolName: Self.lossSymbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
                mask.contents = image?.layerContents(forContentsScale: scale)
                mask.contentsScale = scale
            }
        }
    }
}

/// The bubble's layer-backed content view: the first click counts, clicks outside the circle find
/// no view, and its size and backing scale lay the layers out again.
private final class BubbleView: NSView {
    var onResize: () -> Void = {}
    var onBackingChange: () -> Void = {}

    // TidyShot is not active and the panel is never key, so the first click of a drag or a
    // double-click would otherwise be swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // The panel moves itself, clamped.
    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let radius = bounds.width / 2
        guard hypot(local.x - bounds.midX, local.y - bounds.midY) <= radius else { return nil }
        return super.hitTest(point)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onBackingChange()
    }
}
