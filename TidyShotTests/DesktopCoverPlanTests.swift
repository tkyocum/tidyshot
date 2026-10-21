import CoreGraphics
import Testing
@testable import TidyShot

struct DesktopCoverPlanTests {
    @Test func theFirstShowCoversEveryCapturedScreen() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [], captured: [1, 2], kind: .show)
        #expect(plan == DesktopCoverPlan(wallpapered: [1, 2], removed: [], uncovered: []))
    }

    @Test func aScreenThatNeverHadAWallpaperStaysUncovered() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [], captured: [1], kind: .show)
        #expect(plan == DesktopCoverPlan(wallpapered: [1], removed: [], uncovered: [2]))
    }

    @Test func aShowFromHiddenGivesKeptCoversTheNewWallpaper() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [1, 2], captured: [1, 2], kind: .show)
        #expect(plan == DesktopCoverPlan(wallpapered: [1, 2], removed: [], uncovered: []))
    }

    @Test func aShowFromHiddenDropsAKeptCoverWithoutANewWallpaper() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [1, 2, 3], captured: [1], kind: .show)
        #expect(plan == DesktopCoverPlan(wallpapered: [1], removed: [2, 3], uncovered: [2]))
    }

    @Test func aFailedRefreshKeepsTheExistingCover() {
        let plan = DesktopCoverPlan.make(screens: [1, 2], covered: [1, 2], captured: [1], kind: .refresh)
        #expect(plan == DesktopCoverPlan(wallpapered: [1], removed: [], uncovered: []))
    }

    @Test func aRefreshRemovesACoverOnlyWhenItsDisplayIsGone() {
        let plan = DesktopCoverPlan.make(screens: [1], covered: [1, 2], captured: [], kind: .refresh)
        #expect(plan == DesktopCoverPlan(wallpapered: [], removed: [2], uncovered: []))
    }

    @Test func aRefreshCoversAnAddedDisplay() {
        let plan = DesktopCoverPlan.make(screens: [1, 3], covered: [1], captured: [1, 3], kind: .refresh)
        #expect(plan == DesktopCoverPlan(wallpapered: [1, 3], removed: [], uncovered: []))
    }

    @Test func aShowWhileUpLeavesCoveredScreensAsTheyAre() {
        let plan = DesktopCoverPlan.make(screens: [1, 3], covered: [1], captured: [1, 3], kind: .showWhileUp)
        #expect(plan == DesktopCoverPlan(wallpapered: [3], removed: [], uncovered: []))
    }

    @Test func aShowWhileUpKeepsACoverWhoseCaptureFailed() {
        let plan = DesktopCoverPlan.make(screens: [1, 3], covered: [1], captured: [], kind: .showWhileUp)
        #expect(plan == DesktopCoverPlan(wallpapered: [], removed: [], uncovered: [3]))
    }

    @Test func screensWithoutACoverNeedACapture() {
        #expect(DesktopCoverPlan.needingCapture(screens: [1, 2, 3], covered: [2]) == [1, 3])
        #expect(DesktopCoverPlan.needingCapture(screens: [1, 2], covered: [1, 2, 4]).isEmpty)
    }
}
