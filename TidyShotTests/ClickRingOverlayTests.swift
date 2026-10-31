import AppKit
import QuartzCore
import Testing
@testable import TidyShot

/// The ring overlay's panel, rings and animations (design, The overlay, The ring, Animation).
struct ClickRingOverlayTests {
    let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    /// A colour's sRGB components with alpha, or nil when it has none.
    func srgba(_ color: CGColor?) -> [CGFloat]? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return color?.converted(to: srgb, intent: .defaultIntent, options: nil)?.components
    }

    func close(_ a: [CGFloat]?, _ b: [CGFloat]) -> Bool {
        guard let a, a.count == b.count else { return false }
        return zip(a, b).allSatisfy { abs($0 - $1) < 0.001 }
    }

    func shapes(of ring: CALayer) -> [CAShapeLayer] {
        (ring.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
    }

    /// A timing function's four control points, so two can be compared.
    func controlPoints(_ function: CAMediaTimingFunction?) -> [Float]? {
        guard let function else { return nil }
        var points: [Float] = []
        for index in 0..<4 {
            var values: [Float] = [0, 0]
            function.getControlPoint(at: index, values: &values)
            points += values
        }
        return points
    }

    // MARK: The ring

    @Test(arguments: [ClickRingColour.yellow, .blue])
    func theRingsLayers(colour: ClickRingColour) throws {
        let ring = ClickRingOverlay.makeRingLayer(colour: colour, scale: 2)
        #expect(ring.bounds == CGRect(x: 0, y: 0, width: 40, height: 40))
        let shapes = shapes(of: ring)
        try #require(shapes.count == 2)
        let (edge, stroke) = (shapes[0], shapes[1])
        let c = colour.components
        // The dark edge under the coloured stroke.
        #expect(edge.lineWidth == 6)
        #expect(close(srgba(edge.strokeColor), [0, 0, 0, 0.6]))
        #expect(edge.fillColor == nil)
        #expect(stroke.lineWidth == 3.5)
        #expect(close(srgba(stroke.strokeColor), [c.red, c.green, c.blue, 1]))
        #expect(close(srgba(stroke.fillColor), [c.red, c.green, c.blue, 0.2]))
        #expect(stroke.path?.boundingBox == CGRect(x: 0, y: 0, width: 40, height: 40))
        #expect(edge.path?.boundingBox == CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    @Test func everyLayerOfTheRingTakesTheScale() {
        let ring = ClickRingOverlay.makeRingLayer(colour: .yellow, scale: 2)
        #expect(ring.contentsScale == 2)
        #expect(shapes(of: ring).allSatisfy { $0.contentsScale == 2 })
    }

    // MARK: Animation

    @Test func aBeginAddsARingAtThePointGrowingFromHalfSize() throws {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        overlay.apply(.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 120, y: 80))))
        let rings = overlay.ringContainer.sublayers ?? []
        try #require(rings.count == 1)
        #expect(rings[0].position == CGPoint(x: 120, y: 80))
        #expect(rings[0].opacity == 1)
        let grow = try #require(rings[0].animation(forKey: ClickRingOverlay.growKey) as? CABasicAnimation)
        #expect(grow.keyPath == "transform.scale")
        #expect(grow.fromValue as? CGFloat == 0.5)
        #expect(grow.toValue as? CGFloat == 1)
        #expect(grow.duration == 0.15)
    }

    @Test func aMoveSetsThePosition() throws {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        overlay.apply(.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 120, y: 80))))
        overlay.apply(.move(.left, to: CGPoint(x: 300, y: 200)))
        let ring = try #require(overlay.ringContainer.sublayers?.first)
        #expect(ring.position == CGPoint(x: 300, y: 200))
        #expect(ring.animation(forKey: "position") == nil)
    }

    @Test func anEndFadesTheRingOut() throws {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        overlay.apply(.begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 120, y: 80))))
        overlay.apply(.end(.right))
        let ring = try #require(overlay.ringContainer.sublayers?.first)
        let fade = try #require(ring.animation(forKey: ClickRingOverlay.fadeKey) as? CAAnimationGroup)
        #expect(fade.duration == 0.35)
        let parts = (fade.animations ?? []).compactMap { $0 as? CABasicAnimation }
        let scale = try #require(parts.first { $0.keyPath == "transform.scale" })
        #expect(scale.fromValue as? CGFloat == 1)
        #expect(scale.toValue as? CGFloat == 1.3)
        let opacity = try #require(parts.first { $0.keyPath == "opacity" })
        #expect(opacity.fromValue as? Float == 1)
        #expect(opacity.toValue as? Float == 0)
    }

    /// An up right after the down starts the fade once the grow has finished.
    @Test func anEndDuringTheGrowWaitsForIt() throws {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        let before = CACurrentMediaTime()
        overlay.apply(.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 120, y: 80))))
        overlay.apply(.end(.left))
        let ring = try #require(overlay.ringContainer.sublayers?.first)
        let fade = try #require(ring.animation(forKey: ClickRingOverlay.fadeKey))
        #expect(fade.beginTime >= before + ClickRingTiming.grow)
        #expect(fade.beginTime <= CACurrentMediaTime() + ClickRingTiming.grow)
    }

    /// Each button has its own ring; an end for one leaves the other held.
    @Test func eachButtonHasItsOwnRing() throws {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        overlay.apply(.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 10, y: 10))))
        overlay.apply(.begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 50, y: 50))))
        overlay.apply(.end(.left))
        overlay.apply(.move(.right, to: CGPoint(x: 60, y: 70)))
        let rings = overlay.ringContainer.sublayers ?? []
        try #require(rings.count == 2)
        #expect(rings[0].animation(forKey: ClickRingOverlay.fadeKey) != nil)
        #expect(rings[1].animation(forKey: ClickRingOverlay.fadeKey) == nil)
        #expect(rings[1].position == CGPoint(x: 60, y: 70))
    }

    @Test func removeAllRingsLeavesNoLayers() {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        overlay.apply(.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 10, y: 10))))
        overlay.apply(.begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 50, y: 50))))
        overlay.apply(.end(.left))
        overlay.removeAllRings()
        #expect((overlay.ringContainer.sublayers ?? []).isEmpty)
        // A move or an end for a ring that is gone draws nothing.
        overlay.apply(.move(.right, to: CGPoint(x: 60, y: 70)))
        overlay.apply(.end(.right))
        #expect((overlay.ringContainer.sublayers ?? []).isEmpty)
    }

    // MARK: The panel

    @Test func thePanelIsClickThroughOverEverything() {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        #expect(overlay.level == .screenSaver)
        #expect(overlay.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle])
        #expect(overlay.ignoresMouseEvents)
        #expect(!overlay.hasShadow)
        #expect(!overlay.isOpaque)
        #expect(overlay.backgroundColor == .clear)
        #expect(!overlay.hidesOnDeactivate)
        #expect(!overlay.canBecomeKey)
        #expect(!overlay.canBecomeMain)
        #expect(overlay.styleMask.contains(.nonactivatingPanel))
    }

    @Test func theOverlayCoversTheScreenFrameAndHoldsNoRings() {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        #expect(overlay.frame == screenFrame)
        #expect(overlay.ringContainer.isGeometryFlipped)
        #expect(overlay.ringContainer.frame == CGRect(origin: .zero, size: screenFrame.size))
        #expect((overlay.ringContainer.sublayers ?? []).isEmpty)
    }

    @Test func setScreenFrameMovesTheOverlayAndItsRings() {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        let second = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        overlay.setScreenFrame(second)
        #expect(overlay.frame == second)
        #expect(overlay.ringContainer.frame == CGRect(origin: .zero, size: second.size))
    }

    /// recording-r3 :440 (call F). The ring's grow eases out and its fade is linear: the grow has the ease-out curve,
    /// and neither the fade group nor its parts has a timing function.
    @Test func theRingGrowsEasingOutAndFadesLinearly() throws {
        let overlay = ClickRingOverlay(screenFrame: screenFrame)
        overlay.apply(.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 120, y: 80))))
        let ring = try #require(overlay.ringContainer.sublayers?.first)
        let grow = try #require(ring.animation(forKey: ClickRingOverlay.growKey))
        #expect(controlPoints(grow.timingFunction) == controlPoints(CAMediaTimingFunction(name: .easeOut)))

        overlay.apply(.end(.left))
        let fade = try #require(ring.animation(forKey: ClickRingOverlay.fadeKey) as? CAAnimationGroup)
        #expect(fade.timingFunction == nil)
        #expect((fade.animations ?? []).allSatisfy { $0.timingFunction == nil })
    }
}
