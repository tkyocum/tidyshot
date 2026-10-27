import Testing
@testable import TidyShot

/// The camera's format when the 720p preset cannot be set (plan Gap 15). No test makes a
/// `CameraSession` with a device.
struct CameraSessionTests {
    typealias Candidate = CameraFormat.Candidate

    @Test func takes720pAt30OverLargerAndSmallerFormats() {
        let formats = [
            Candidate(width: 1920, height: 1080, maxFrameRate: 60),
            Candidate(width: 640, height: 480, maxFrameRate: 30),
            Candidate(width: 1280, height: 720, maxFrameRate: 30),
        ]
        #expect(CameraFormat.pick(formats) == 2)
    }

    @Test func skipsA720pThatReachesOnly15fps() {
        let formats = [
            Candidate(width: 1280, height: 720, maxFrameRate: 15),
            Candidate(width: 1920, height: 1080, maxFrameRate: 30),
        ]
        #expect(CameraFormat.pick(formats) == 1)
    }

    @Test func nothingWhenNoFormatReaches30() {
        let formats = [
            Candidate(width: 1280, height: 720, maxFrameRate: 15),
            Candidate(width: 1920, height: 1080, maxFrameRate: 24),
        ]
        #expect(CameraFormat.pick(formats) == nil)
        #expect(CameraFormat.pick([]) == nil)
    }

    @Test func theSmallerOfTwoAtTheSameDistance() {
        // 1280 × 720 is 921,600 pixels; both are 230,400 away.
        let formats = [
            Candidate(width: 1280, height: 900, maxFrameRate: 30),
            Candidate(width: 960, height: 720, maxFrameRate: 30),
        ]
        #expect(CameraFormat.pick(formats) == 1)
    }

    @Test func theQueue() {
        #expect(CameraSession.queueLabel == "io.tky.tidyshot.camera")
    }
}
