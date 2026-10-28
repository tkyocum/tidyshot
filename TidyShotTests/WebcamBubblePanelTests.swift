import AppKit
import QuartzCore
import Testing
@testable import TidyShot

/// The bubble's window with a plain preview layer and no camera (design, Webcam bubble, The
/// window, Dragging, Double-click).
struct WebcamBubblePanelTests {
    let recorded = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func makePanel(size: BubbleSize = .medium, at origin: CGPoint = CGPoint(x: 804, y: 16)) -> WebcamBubblePanel {
        let d = size.diameter
        return WebcamBubblePanel(preview: CALayer(), size: size,
                                 frame: CGRect(origin: origin, size: CGSize(width: d, height: d)),
                                 recorded: recorded)
    }

    // MARK: The panel

    @Test func thePanelsStyle() {
        let panel = makePanel()
        #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
        #expect(panel.level == .floating)
        #expect(panel.collectionBehavior == [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle])
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.hasShadow)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.ignoresMouseEvents)
    }

    @Test func theFirstClickCounts() throws {
        let view = try #require(makePanel().contentView)
        #expect(view.acceptsFirstMouse(for: nil))
    }

    @Test func theFrameAndSize() {
        let panel = makePanel(size: .small, at: CGPoint(x: 864, y: 16))
        #expect(panel.frame == CGRect(x: 864, y: 16, width: 120, height: 120))
        #expect(panel.size == .small)
        #expect(panel.recorded == recorded)
    }

    @Test(arguments: BubbleSize.allCases)
    func theCircle(size: BubbleSize) throws {
        let panel = makePanel(size: size, at: .zero)
        let circle = try #require(panel.contentView?.layer)
        #expect(circle.cornerRadius == size.diameter / 2)
        #expect(circle.masksToBounds)
        #expect(panel.preview.frame == CGRect(x: 0, y: 0, width: size.diameter, height: size.diameter))
    }

    @Test func theLayers() throws {
        let panel = makePanel()
        let circle = try #require(panel.contentView?.layer)
        // The preview, then the loss symbol, then the border on top.
        #expect(circle.sublayers?.map(ObjectIdentifier.init)
            == [panel.preview, panel.lossSymbol, panel.border].map(ObjectIdentifier.init))
        #expect(circle.backgroundColor == WebcamBubblePanel.grey)
        #expect(panel.border.lineWidth == 2)
        #expect(panel.border.strokeColor == CGColor(gray: 1, alpha: 0.85))
        #expect(panel.border.fillColor == nil)
        // The stroke lies inside the circle's edge.
        #expect(panel.border.path?.boundingBox == CGRect(x: 1, y: 1, width: 178, height: 178))
        // The symbol is 40 % of the diameter, centred, and shown only after a loss.
        #expect(panel.lossSymbol.frame == CGRect(x: 54, y: 54, width: 72, height: 72))
        #expect(panel.lossSymbol.isHidden)
        #expect(!panel.preview.isHidden)
        #expect(!panel.border.isHidden)
    }

    @Test func everyLayerTakesTheScale() {
        let panel = makePanel()
        let scale = panel.backingScaleFactor
        #expect(panel.preview.contentsScale == scale)
        #expect(panel.border.contentsScale == scale)
        #expect(panel.lossSymbol.contentsScale == scale)
    }

    @Test func clicksOutsideTheCircleFindNoView() throws {
        let view = try #require(makePanel(at: .zero).contentView)
        #expect(view.hitTest(CGPoint(x: 90, y: 90)) === view)
        #expect(view.hitTest(CGPoint(x: 170, y: 90)) === view)
        #expect(view.hitTest(CGPoint(x: 5, y: 5)) == nil)
        #expect(view.hitTest(CGPoint(x: 175, y: 175)) == nil)
    }

    // MARK: Size steps

    @Test func aStepKeepsTheCentre() {
        let panel = makePanel(size: .small, at: CGPoint(x: 400, y: 300))
        var stepped: [(BubbleSize, CGRect)] = []
        panel.onSizeStepped = { stepped.append(($0, $1)) }
        panel.stepSize()
        let expected = CGRect(x: 370, y: 270, width: 180, height: 180)
        #expect(panel.size == .medium)
        #expect(panel.frame == expected)
        #expect(stepped.count == 1)
        #expect(stepped.first?.0 == .medium)
        #expect(stepped.first?.1 == expected)
        #expect(panel.contentView?.layer?.cornerRadius == 90)
    }

    @Test func aStepAgainstAnEdgeIsClamped() {
        // The default Small bubble stepped to Medium keeps its centre (924, 76), then is clamped.
        let panel = makePanel(size: .small, at: CGPoint(x: 864, y: 16))
        var stepped: [(BubbleSize, CGRect)] = []
        panel.onSizeStepped = { stepped.append(($0, $1)) }
        panel.stepSize()
        let expected = CGRect(x: 820, y: 0, width: 180, height: 180)
        #expect(panel.frame == expected)
        #expect(stepped.first?.1 == expected)
    }

    @Test func stepsGoRoundTheSizes() {
        let panel = makePanel(size: .small, at: CGPoint(x: 400, y: 300))
        var sizes: [BubbleSize] = []
        panel.onSizeStepped = { size, _ in sizes.append(size) }
        panel.stepSize()
        panel.stepSize()
        panel.stepSize()
        #expect(sizes == [.medium, .large, .small])
        #expect(panel.frame.size == CGSize(width: 120, height: 120))
    }

    @Test func aReclampMovesTheBubbleIntoTheNewRect() {
        let panel = makePanel()
        let smaller = CGRect(x: 0, y: 100, width: 600, height: 500)
        panel.reclamp(into: smaller)
        #expect(panel.recorded == smaller)
        #expect(panel.frame == CGRect(x: 420, y: 100, width: 180, height: 180))
    }

    // MARK: Picture and loss

    @Test func hidingThePictureDrawsNothingAndPassesClicks() throws {
        let panel = makePanel()
        let circle = try #require(panel.contentView?.layer)
        panel.setLost(true)
        panel.setPictureShown(false)
        #expect(panel.ignoresMouseEvents)
        #expect(panel.preview.isHidden)
        #expect(panel.border.isHidden)
        #expect(panel.lossSymbol.isHidden)
        #expect(circle.backgroundColor == nil)

        panel.setLost(false)
        panel.setPictureShown(true)
        #expect(!panel.ignoresMouseEvents)
        #expect(!panel.preview.isHidden)
        #expect(!panel.border.isHidden)
        #expect(panel.lossSymbol.isHidden)
        #expect(circle.backgroundColor == WebcamBubblePanel.grey)
    }

    @Test func aLossShowsTheSymbolOnGrey() {
        let panel = makePanel()
        panel.setLost(true)
        #expect(!panel.lossSymbol.isHidden)
        #expect(panel.preview.isHidden)
        #expect(!panel.border.isHidden)
        #expect(panel.lossSymbol.mask?.contents != nil)

        panel.setLost(false)
        #expect(panel.lossSymbol.isHidden)
        #expect(!panel.preview.isHidden)
    }

    @Test func aLossWhileHiddenShowsOnlyOnceThePictureIsBack() {
        let panel = makePanel()
        panel.setPictureShown(false)
        panel.setLost(true)
        #expect(panel.lossSymbol.isHidden)
        panel.setPictureShown(true)
        #expect(!panel.lossSymbol.isHidden)
        #expect(panel.preview.isHidden)
    }
}
