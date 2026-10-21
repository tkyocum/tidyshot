import CoreGraphics
import Testing
@testable import TidyShot

struct DesktopCoverPlanTests {
    @Test func theFirstShowCoversEveryCapturedScreen() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [], captured: [1, 2], keepsExisting: false)
        #expect(plan == DesktopCoverPlan(wallpapered: [1, 2], removed: [], uncovered: []))
    }

    @Test func aScreenThatNeverHadAWallpaperStaysUncovered() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [], captured: [1], keepsExisting: false)
        #expect(plan == DesktopCoverPlan(wallpapered: [1], removed: [], uncovered: [2]))
    }

    @Test func aFailedRefreshKeepsTheExistingCover() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [1, 2], captured: [1], keepsExisting: false)
        #expect(plan == DesktopCoverPlan(wallpapered: [1], removed: [], uncovered: []))
    }

    @Test func aCoverIsRemovedOnlyWhenItsDisplayIsGone() {
        let plan = DesktopCoverPlan.make(screens: [1], covered: [1, 2], captured: [], keepsExisting: false)
        #expect(plan == DesktopCoverPlan(wallpapered: [], removed: [2], uncovered: []))
    }

    @Test func aRefreshCoversAnAddedDisplay() {
        let plan = DesktopCoverPlan.make(screens: [1, 3], covered: [1], captured: [1, 3], keepsExisting: false)
        #expect(plan == DesktopCoverPlan(wallpapered: [1, 3], removed: [], uncovered: []))
    }

    @Test func aShowWhileUpLeavesCoveredScreensAsTheyAre() {
        let plan = DesktopCoverPlan.make(screens: [1, 3], covered: [1], captured: [1, 3], keepsExisting: true)
        #expect(plan == DesktopCoverPlan(wallpapered: [3], removed: [], uncovered: []))
    }

    @Test func screensWithoutACoverNeedACapture() {
        #expect(DesktopCoverPlan.needingCapture(screens: [1, 2, 3], covered: [2]) == [1, 3])
        #expect(DesktopCoverPlan.needingCapture(screens: [1, 2], covered: [1, 2, 4]).isEmpty)
    }
}
