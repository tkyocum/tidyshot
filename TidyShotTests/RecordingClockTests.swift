import Foundation
import Testing
@testable import TidyShot

struct RecordingClockTests {
    @Test(arguments: [
        (0.0, "0:00"),
        (59.0, "0:59"),
        (59.9, "0:59"),
        (60.0, "1:00"),
        (3_599.0, "59:59"),
        (3_600.0, "1:00:00"),
        (3_723.0, "1:02:03"),
        (-1.0, "0:00"),
    ])
    func formatsElapsedTime(seconds: TimeInterval, text: String) {
        #expect(RecordingClock.format(seconds) == text)
    }

    /// The time turns orange at 0:30 for a GIF and at 5:00 for an MP4.
    @Test func softLimitDependsOnTheFormat() {
        #expect(RecordingClock.softLimit == 300)
        #expect(RecordingClock.gifSoftLimit == 30)
        #expect(!RecordingClock.isPastSoftLimit(29.9, format: .gif))
        #expect(RecordingClock.isPastSoftLimit(30, format: .gif))
        #expect(RecordingClock.isPastSoftLimit(299.9, format: .gif))
        #expect(!RecordingClock.isPastSoftLimit(30, format: .mp4))
        #expect(!RecordingClock.isPastSoftLimit(299.9, format: .mp4))
        #expect(RecordingClock.isPastSoftLimit(300, format: .mp4))
        #expect(RecordingClock.isPastSoftLimit(4_000, format: .mp4))
    }
}
