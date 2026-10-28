import AppKit
import Testing
@testable import TidyShot

/// Where a click draws a ring and how a held ring follows (design, Click highlights; plan Gap 11).
struct ClickHighlightRuleTests {
    /// A 1440 × 900 display to the right of a 1512-wide primary, and an area inside it.
    let display = CGRect(x: 1512, y: 0, width: 1440, height: 900)
    let area = CGRect(x: 1612, y: 100, width: 400, height: 300)

    func event(_ phase: ClickEvent.Phase, _ button: ClickButton = .left, control: Bool = false,
               at point: CGPoint) -> ClickEvent {
        ClickEvent(phase: phase, button: button, isControl: control, point: point)
    }

    // MARK: Colours

    @Test func aLeftClickIsYellow() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        #expect(rule.handle(event(.down, at: CGPoint(x: 1600, y: 50)))
                == [.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 88, y: 50)))])
    }

    @Test func aRightClickIsBlue() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        #expect(rule.handle(event(.down, .right, at: CGPoint(x: 1600, y: 50)))
                == [.begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 88, y: 50)))])
    }

    /// A control-click is the left button, blue, and its left up ends it.
    @Test func aControlClickIsBlueOnTheLeftButton() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        #expect(rule.handle(event(.down, control: true, at: CGPoint(x: 1600, y: 50)))
                == [.begin(ClickRing(button: .left, colour: .blue, point: CGPoint(x: 88, y: 50)))])
        #expect(rule.handle(event(.up, at: CGPoint(x: 1600, y: 50))) == [.end(.left)])
        #expect(rule.held.isEmpty)
    }

    @Test func theColoursComponentsAndGIFColours() {
        #expect(ClickRingColour.yellow.components == (red: 1.0, green: 0.8, blue: 0.0))
        #expect(ClickRingColour.blue.components == (red: 0.04, green: 0.52, blue: 1.0))
        #expect(ClickRingColour.yellow.gifColour == GIFColour(r: 255, g: 204, b: 0))
        #expect(ClickRingColour.blue.gifColour == GIFColour(r: 10, g: 133, b: 255))
        #expect(ClickRingColour.reservedGIFColours
                == [GIFColour(r: 255, g: 204, b: 0), GIFColour(r: 10, g: 133, b: 255), GIFColour(r: 0, g: 0, b: 0)])
    }

    // MARK: Where rings draw

    @Test func theRecordedRectIsTheAreaOrTheDisplay() {
        #expect(ClickHighlightRule(displayFrame: display, area: nil).recordedRect == display)
        #expect(ClickHighlightRule(displayFrame: display, area: area).recordedRect == area)
    }

    @Test func aDownInsideTheDisplayAndTheAreaDraws() {
        var rule = ClickHighlightRule(displayFrame: display, area: area)
        #expect(rule.handle(event(.down, at: CGPoint(x: 1700, y: 200)))
                == [.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 188, y: 200)))])
        #expect(rule.held[.left] == ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 188, y: 200)))
    }

    @Test func aDownOutsideTheAreaDrawsNothing() {
        var rule = ClickHighlightRule(displayFrame: display, area: area)
        #expect(rule.handle(event(.down, at: CGPoint(x: 1600, y: 200))).isEmpty)
        #expect(rule.held.isEmpty)
    }

    @Test func aDownOutsideTheDisplayDrawsNothing() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        #expect(rule.handle(event(.down, at: CGPoint(x: 700, y: 200))).isEmpty)
        #expect(rule.handle(event(.down, .right, at: CGPoint(x: 1600, y: 950))).isEmpty)
        #expect(rule.held.isEmpty)
    }

    @Test func anUpOrADragWithNoDownIsIgnored() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        #expect(rule.handle(event(.dragged, at: CGPoint(x: 1600, y: 50))).isEmpty)
        #expect(rule.handle(event(.up, at: CGPoint(x: 1600, y: 50))).isEmpty)
        #expect(rule.handle(event(.dragged, .right, at: CGPoint(x: 1600, y: 50))).isEmpty)
        #expect(rule.handle(event(.up, .right, at: CGPoint(x: 1600, y: 50))).isEmpty)
        #expect(rule.held.isEmpty)
    }

    /// An up of one button does not end the other button's ring.
    @Test func anUpOfTheOtherButtonIsIgnored() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        _ = rule.handle(event(.down, at: CGPoint(x: 1600, y: 50)))
        #expect(rule.handle(event(.up, .right, at: CGPoint(x: 1600, y: 50))).isEmpty)
        #expect(Set(rule.held.keys) == [.left])
    }

    @Test func aDragMovesTheHeldRingAndTheUpEndsIt() {
        var rule = ClickHighlightRule(displayFrame: display, area: area)
        _ = rule.handle(event(.down, at: CGPoint(x: 1700, y: 200)))
        #expect(rule.handle(event(.dragged, at: CGPoint(x: 1750, y: 250))) == [.move(.left, to: CGPoint(x: 238, y: 250))])
        #expect(rule.held[.left]?.point == CGPoint(x: 238, y: 250))
        #expect(rule.handle(event(.up, at: CGPoint(x: 1750, y: 250))) == [.end(.left)])
        #expect(rule.held.isEmpty)
    }

    /// The area spans x 1612...2012 and y 100...400; its overlay points are x 100...500.
    @Test func aDragOutOfTheAreaHoldsTheRingAtTheNearestEdgePoint() {
        var rule = ClickHighlightRule(displayFrame: display, area: area)
        _ = rule.handle(event(.down, at: CGPoint(x: 1700, y: 200)))
        #expect(rule.handle(event(.dragged, at: CGPoint(x: 2100, y: 250))) == [.move(.left, to: CGPoint(x: 500, y: 250))])
        #expect(rule.handle(event(.dragged, at: CGPoint(x: 1500, y: 50))) == [.move(.left, to: CGPoint(x: 100, y: 100))])
        #expect(rule.handle(event(.dragged, at: CGPoint(x: 1800, y: 600))) == [.move(.left, to: CGPoint(x: 288, y: 400))])
        #expect(rule.handle(event(.dragged, at: CGPoint(x: 1800, y: 300))) == [.move(.left, to: CGPoint(x: 288, y: 300))])
    }

    @Test func aDragOffTheDisplayHoldsTheRingAtItsEdge() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        _ = rule.handle(event(.down, .right, at: CGPoint(x: 1600, y: 50)))
        #expect(rule.handle(event(.dragged, .right, at: CGPoint(x: 700, y: -20))) == [.move(.right, to: CGPoint(x: 0, y: 0))])
    }

    @Test func anUpOutsideTheAreaStillEndsTheRing() {
        var rule = ClickHighlightRule(displayFrame: display, area: area)
        _ = rule.handle(event(.down, at: CGPoint(x: 1700, y: 200)))
        #expect(rule.handle(event(.up, at: CGPoint(x: 1600, y: 600))) == [.end(.left)])
        #expect(rule.held.isEmpty)
    }

    @Test func anUpOnTheOtherDisplayStillEndsTheRing() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        _ = rule.handle(event(.down, .right, at: CGPoint(x: 1600, y: 50)))
        #expect(rule.handle(event(.up, .right, at: CGPoint(x: 400, y: 300))) == [.end(.right)])
        #expect(rule.held.isEmpty)
    }

    @Test func twoButtonsDownGiveTwoRings() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        #expect(rule.handle(event(.down, at: CGPoint(x: 1600, y: 50)))
                == [.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 88, y: 50)))])
        #expect(rule.handle(event(.down, .right, at: CGPoint(x: 1610, y: 60)))
                == [.begin(ClickRing(button: .right, colour: .blue, point: CGPoint(x: 98, y: 60)))])
        #expect(rule.held.count == 2)
        #expect(rule.handle(event(.dragged, .right, at: CGPoint(x: 1620, y: 70))) == [.move(.right, to: CGPoint(x: 108, y: 70))])
        #expect(rule.held[.left]?.point == CGPoint(x: 88, y: 50))
        #expect(rule.handle(event(.up, at: CGPoint(x: 1600, y: 50))) == [.end(.left)])
        #expect(rule.held[.right] != nil)
    }

    /// A down for a button whose ring is still held ends that ring first (plan Gap 11).
    @Test func aSecondDownOfAHeldButtonEndsTheOldRingFirst() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        _ = rule.handle(event(.down, at: CGPoint(x: 1600, y: 50)))
        #expect(rule.handle(event(.down, control: true, at: CGPoint(x: 1700, y: 80)))
                == [.end(.left), .begin(ClickRing(button: .left, colour: .blue, point: CGPoint(x: 188, y: 80)))])
        #expect(rule.held[.left] == ClickRing(button: .left, colour: .blue, point: CGPoint(x: 188, y: 80)))
    }

    /// The old ring ends even when the new down lands outside, and the new one draws nothing.
    @Test func aSecondDownOutsideEndsTheOldRingOnly() {
        var rule = ClickHighlightRule(displayFrame: display, area: area)
        _ = rule.handle(event(.down, at: CGPoint(x: 1700, y: 200)))
        #expect(rule.handle(event(.down, at: CGPoint(x: 1600, y: 600))) == [.end(.left)])
        #expect(rule.held.isEmpty)
    }

    /// Turning highlights off starts every held ring's fade, left then right.
    @Test func endAllEndsEveryHeldRing() {
        var rule = ClickHighlightRule(displayFrame: display, area: nil)
        _ = rule.handle(event(.down, .right, at: CGPoint(x: 1600, y: 50)))
        _ = rule.handle(event(.down, at: CGPoint(x: 1610, y: 60)))
        #expect(rule.endAll() == [.end(.left), .end(.right)])
        #expect(rule.held.isEmpty)
        #expect(rule.endAll().isEmpty)
        #expect(rule.handle(event(.up, at: CGPoint(x: 1610, y: 60))).isEmpty)
    }

    // MARK: Points

    @Test func theScreenPointOfAGlobalEventIsItsLocation() {
        #expect(ClickHighlightRule.screenPoint(locationInWindow: CGPoint(x: 100, y: 200), windowFrame: nil)
                == CGPoint(x: 100, y: 200))
    }

    @Test func theScreenPointOfALocalEventOnTheBubbleAddsTheFramesOrigin() {
        let bubble = CGRect(x: 500, y: 300, width: 200, height: 200)
        #expect(ClickHighlightRule.screenPoint(locationInWindow: CGPoint(x: 30, y: 40), windowFrame: bubble)
                == CGPoint(x: 530, y: 340))
    }

    @Test func theCocoaToCGFlip() {
        #expect(ClickHighlightRule.cgPoint(fromCocoa: CGPoint(x: 100, y: 200), primaryMaxY: 1410) == CGPoint(x: 100, y: 1210))
    }

    /// A second display left of and below the primary has negative Cocoa coordinates.
    @Test func theFlipOnASecondDisplayLeftOfAndBelowThePrimary() {
        #expect(ClickHighlightRule.cgPoint(fromCocoa: CGPoint(x: -100, y: -500), primaryMaxY: 1410)
                == CGPoint(x: -100, y: 1910))
    }

    // MARK: ClickEvent.make

    @Test(arguments: [
        (NSEvent.EventType.leftMouseDown, ClickEvent.Phase.down, ClickButton.left),
        (.leftMouseDragged, .dragged, .left),
        (.leftMouseUp, .up, .left),
        (.rightMouseDown, .down, .right),
        (.rightMouseDragged, .dragged, .right),
        (.rightMouseUp, .up, .right),
    ])
    func eachTypeMapsToItsPhaseAndButton(type: NSEvent.EventType, phase: ClickEvent.Phase, button: ClickButton) {
        let made = ClickEvent.make(type: type, modifierFlags: [], locationInWindow: CGPoint(x: 100, y: 200),
                                   windowFrame: nil, primaryMaxY: 1410)
        #expect(made == ClickEvent(phase: phase, button: button, isControl: false, point: CGPoint(x: 100, y: 1210)))
    }

    @Test func controlSetsIsControl() {
        let made = ClickEvent.make(type: .leftMouseDown, modifierFlags: [.control, .shift],
                                   locationInWindow: CGPoint(x: 100, y: 200), windowFrame: nil, primaryMaxY: 1410)
        #expect(made?.isControl == true)
        let plain = ClickEvent.make(type: .leftMouseDown, modifierFlags: [.shift],
                                    locationInWindow: CGPoint(x: 100, y: 200), windowFrame: nil, primaryMaxY: 1410)
        #expect(plain?.isControl == false)
    }

    @Test func otherTypesGiveNil() {
        for type in [NSEvent.EventType.keyDown, .mouseMoved, .otherMouseDown, .scrollWheel] {
            #expect(ClickEvent.make(type: type, modifierFlags: [], locationInWindow: .zero,
                                    windowFrame: nil, primaryMaxY: 1410) == nil)
        }
    }

    @Test func aGlobalEventIsFlippedToCG() {
        let made = ClickEvent.make(type: .leftMouseDown, modifierFlags: [], locationInWindow: CGPoint(x: 100, y: 200),
                                   windowFrame: nil, primaryMaxY: 1410)
        #expect(made?.point == CGPoint(x: 100, y: 1210))
    }

    @Test func aLocalEventAddsTheWindowsOriginThenFlips() {
        let made = ClickEvent.make(type: .leftMouseUp, modifierFlags: [], locationInWindow: CGPoint(x: 30, y: 40),
                                   windowFrame: CGRect(x: 500, y: 300, width: 200, height: 200), primaryMaxY: 1410)
        #expect(made?.point == CGPoint(x: 530, y: 1070))
    }

    // MARK: The note after Stop

    @Test func theNotFilmedNotice() {
        #expect(ClickHighlightRule.notFilmedNotice
                == RecordingNotice(title: "Recorded without click highlights", body: "The click highlights could not be filmed."))
    }

    @Test func theNoteOnlyWhenOnAtStartAndMissed() {
        #expect(ClickHighlightRule.noteAfterStop(onAtStart: true, missed: true) == ClickHighlightRule.notFilmedNotice)
        #expect(ClickHighlightRule.noteAfterStop(onAtStart: true, missed: false) == nil)
        #expect(ClickHighlightRule.noteAfterStop(onAtStart: false, missed: true) == nil)
        #expect(ClickHighlightRule.noteAfterStop(onAtStart: false, missed: false) == nil)
    }
}
