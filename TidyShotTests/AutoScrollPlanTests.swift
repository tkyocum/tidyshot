import CoreGraphics
import Testing
@testable import TidyShot

struct AutoScrollPlanTests {
    @Test func aStepSplitsIntoEventsOfAtMostFiftyPoints() {
        #expect(AutoScrollPlan.events(forPoints: 120) == [50, 50, 20])
        #expect(AutoScrollPlan.events(forPoints: 50) == [50])
        #expect(AutoScrollPlan.events(forPoints: 231) == [50, 50, 50, 50, 31])
        #expect(AutoScrollPlan.events(forPoints: 1) == [1])
        #expect(AutoScrollPlan.events(forPoints: 400).reduce(0, +) == 400)
        #expect(AutoScrollPlan.events(forPoints: 400).allSatisfy { $0 <= 50 })
    }

    /// Events are whole points, because the wheel delta is an integer.
    @Test func eventsAreWholePoints() {
        #expect(AutoScrollPlan.events(forPoints: 120.4) == [50, 50, 20])
        #expect(AutoScrollPlan.events(forPoints: 120.6) == [50, 50, 21])
    }

    @Test func noEventsForNothingToScroll() {
        #expect(AutoScrollPlan.events(forPoints: 0).isEmpty)
        #expect(AutoScrollPlan.events(forPoints: -30).isEmpty)
        #expect(AutoScrollPlan.events(forPoints: 0.4).isEmpty)
        #expect(AutoScrollPlan.events(forPoints: .infinity).isEmpty)
        #expect(AutoScrollPlan.events(forPoints: .nan).isEmpty)
    }

    @Test func eventsArePostedTenMillisecondsApart() {
        #expect(AutoScrollPlan.eventSpacing == .milliseconds(10))
    }

    @Test func theFirstStepIsHalfTheAreasHeight() {
        #expect(AutoScrollPlan.firstStep(areaHeightPoints: 800) == 400)
        #expect(AutoScrollPlan.firstStep(areaHeightPoints: 100) == 50)
    }

    /// 0.6 of the last band: 770 rows at 2x are 385 points, 0.6 of which is 231.
    @Test func laterStepsAreSixtyPercentOfTheLastBandInPoints() {
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 770, scale: 2) == 231)
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 770, scale: 1) == 462)
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 1600, scale: 2) == 480)
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 0, scale: 2) == 1)
    }

    @Test func aLossHalvesTheStepDownToFortyPoints() {
        #expect(AutoScrollPlan.shrunk(400) == 200)
        #expect(AutoScrollPlan.shrunk(231) == 116)
        #expect(AutoScrollPlan.shrunk(60) == 40)
        #expect(AutoScrollPlan.shrunk(40) == 40)
        // Never grows a step that is already below the floor.
        #expect(AutoScrollPlan.shrunk(30) == 30)
    }
}
