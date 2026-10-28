import AppKit
import QuartzCore

/// The click rings' window (design, Click highlights, The overlay): one borderless, click-through
/// panel over the recorded display, above menus, the menu bar and the bubble. The recording films
/// it as an excepted window, so it stays on screen and empty while highlights are off.
final class ClickRingOverlay: NSPanel, ClickRingDrawing {
    static let growKey = "grow"
    static let fadeKey = "fade"
    static let diameter: CGFloat = 40

    /// Holds the rings. Flipped, so a ring's point is CG-oriented from the display's top-left.
    let ringContainer = CALayer()
    /// The rings whose button is down, with when their grow began.
    private var held: [ClickButton: (layer: CALayer, down: CFTimeInterval)] = [:]

    init(screenFrame: CGRect) {
        super.init(contentRect: screenFrame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // isFloatingPanel resets the level to .floating, so it must come first.
        isFloatingPanel = true
        level = .screenSaver
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        isReleasedWhenClosed = false

        let view = NSView(frame: CGRect(origin: .zero, size: screenFrame.size))
        view.wantsLayer = true
        ringContainer.isGeometryFlipped = true
        ringContainer.frame = view.bounds
        view.layer?.addSublayer(ringContainer)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Moves the overlay to the recorded display's frame, AppKit global points.
    func setScreenFrame(_ frame: CGRect) {
        setFrame(frame, display: false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringContainer.frame = CGRect(origin: .zero, size: frame.size)
        CATransaction.commit()
    }

    func apply(_ change: ClickRingChange) {
        CATransaction.begin()
        // Explicit animations only: a held ring sits on the pointer instead of trailing it.
        CATransaction.setDisableActions(true)
        switch change {
        case .begin(let ring):
            if held[ring.button] != nil { end(ring.button) }
            let layer = Self.makeRingLayer(colour: ring.colour, scale: backingScaleFactor)
            layer.position = ring.point
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = ClickRingTiming.startScale
            grow.toValue = 1.0 as CGFloat
            grow.duration = ClickRingTiming.grow
            grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(grow, forKey: Self.growKey)
            ringContainer.addSublayer(layer)
            held[ring.button] = (layer, CACurrentMediaTime())
        case .move(let button, let point):
            held[button]?.layer.position = point
        case .end(let button):
            end(button)
        }
        CATransaction.commit()
    }

    func removeAllRings() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        held = [:]
        for layer in ringContainer.sublayers ?? [] { layer.removeFromSuperlayer() }
        CATransaction.commit()
    }

    /// Once the grow has finished, the ring expands and fades to clear, then goes.
    private func end(_ button: ClickButton) {
        guard let (layer, down) = held.removeValue(forKey: button) else { return }
        let now = CACurrentMediaTime()
        let start = ClickRingTiming.fadeStart(down: down, up: now)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0 as CGFloat
        scale.toValue = ClickRingTiming.fadeScale
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 1 as Float
        opacity.toValue = 0 as Float
        let fade = CAAnimationGroup()
        fade.animations = [scale, opacity]
        fade.duration = ClickRingTiming.fade
        fade.beginTime = layer.convertTime(now, from: nil) + (start - now)
        // Held clear at the end, until the delegate takes the layer away.
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        fade.delegate = RingRemoval(layer: layer)
        layer.add(fade, forKey: Self.fadeKey)
    }

    /// A 40 pt ring: a 3.5 pt stroke of the colour over a 6 pt black edge at 60 %, with a 20 %
    /// fill of the colour. `scale` is the screen's backing scale, set on every layer.
    static func makeRingLayer(colour: ClickRingColour, scale: CGFloat) -> CALayer {
        let bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        let path = CGPath(ellipseIn: bounds, transform: nil)
        let c = colour.components

        let edge = CAShapeLayer()
        edge.frame = bounds
        edge.path = path
        edge.lineWidth = 6
        edge.strokeColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6)
        edge.fillColor = nil

        let stroke = CAShapeLayer()
        stroke.frame = bounds
        stroke.path = path
        stroke.lineWidth = 3.5
        stroke.strokeColor = CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
        stroke.fillColor = CGColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 0.2)

        let ring = CALayer()
        ring.bounds = bounds
        for layer in [ring, edge, stroke] { layer.contentsScale = scale }
        ring.addSublayer(edge)
        ring.addSublayer(stroke)
        return ring
    }
}

/// Takes a faded ring off the overlay when its fade stops, finished or removed.
private final class RingRemoval: NSObject, CAAnimationDelegate {
    private weak var layer: CALayer?

    init(layer: CALayer) {
        self.layer = layer
    }

    nonisolated func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        MainActor.assumeIsolated {
            layer?.removeFromSuperlayer()
        }
    }
}
