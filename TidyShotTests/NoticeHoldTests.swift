import Testing
@testable import TidyShot

/// Notices wait while a recording runs and post in the order asked for once it stops (R2 design,
/// Decided 2026-10-24, 8); at any other time they post at once.
struct NoticeHoldTests {
    @Test func aNoticeAskedForWhileNotHoldingPostsAtOnce() {
        var hold = NoticeHold<String>()
        #expect(hold.post("Recording saved") == "Recording saved")
        #expect(hold.held.isEmpty)
        #expect(hold.release().isEmpty)
    }

    @Test func noticesAskedForWhileHoldingWaitAndAreReleasedInOrder() {
        var hold = NoticeHold<String>()
        hold.hold()
        #expect(hold.post("Recording saved") == nil)
        #expect(hold.post("Uploaded, URL copied") == nil)
        #expect(hold.post("Recorded without the microphone") == nil)
        #expect(hold.release() == ["Recording saved", "Uploaded, URL copied", "Recorded without the microphone"])
    }

    /// After the release nothing waits: the next notice posts at once, and a later hold starts empty.
    @Test func afterTheReleaseNoticesPostAtOnceAndTheNextHoldStartsEmpty() {
        var hold = NoticeHold<String>()
        hold.hold()
        _ = hold.post("Recording saved")
        _ = hold.release()
        #expect(!hold.isHolding)
        #expect(hold.post("Image copied") == "Image copied")
        #expect(hold.release().isEmpty)
        hold.hold()
        _ = hold.post("GIF not made")
        #expect(hold.release() == ["GIF not made"])
    }

    /// A hold with nothing asked for releases nothing; holding again keeps what already waits.
    @Test func anEmptyHoldReleasesNothingAndHoldingAgainKeepsTheQueue() {
        var hold = NoticeHold<String>()
        hold.hold()
        #expect(hold.release().isEmpty)
        hold.hold()
        _ = hold.post("Recording saved")
        hold.hold()
        #expect(hold.isHolding)
        _ = hold.post("Uploaded, URL copied")
        #expect(hold.release() == ["Recording saved", "Uploaded, URL copied"])
    }
}
