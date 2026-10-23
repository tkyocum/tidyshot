import Testing
@testable import TidyShot

struct DesktopCoverReasonsTests {
    @Test func nothingActiveShowsNoCovers() {
        let reasons = DesktopCoverReasons()
        #expect(reasons.active.isEmpty)
        #expect(!reasons.showsCovers)
    }

    @Test func captureAndPersistentTogether() {
        var reasons = DesktopCoverReasons()
        reasons.insert(.capture)
        #expect(reasons.showsCovers)
        reasons.insert(.persistent)
        #expect(reasons.active == [.capture, .persistent])
        #expect(reasons.showsCovers)
    }

    @Test func theEndOfACaptureLeavesPersistent() {
        var reasons = DesktopCoverReasons()
        reasons.insert(.persistent)
        reasons.insert(.capture)
        reasons.remove(.capture)
        #expect(reasons.active == [.persistent])
        #expect(reasons.showsCovers)
    }

    @Test func persistentOffDuringACaptureKeepsTheCoversUntilTheCaptureEnds() {
        var reasons = DesktopCoverReasons()
        reasons.insert(.persistent)
        reasons.insert(.capture)
        reasons.remove(.persistent)
        #expect(reasons.showsCovers)
        reasons.remove(.capture)
        #expect(!reasons.showsCovers)
    }

    @Test func removingAnAbsentReasonChangesNothing() {
        var reasons = DesktopCoverReasons()
        reasons.remove(.capture)
        #expect(!reasons.showsCovers)
        reasons.insert(.capture)
        reasons.insert(.capture)
        reasons.remove(.capture)
        #expect(!reasons.showsCovers)
    }
}
