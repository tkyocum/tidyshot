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

    @Test func softLimitIsFiveMinutes() {
        #expect(RecordingClock.softLimit == 300)
        #expect(!RecordingClock.isPastSoftLimit(299.9))
        #expect(RecordingClock.isPastSoftLimit(300))
        #expect(RecordingClock.isPastSoftLimit(4_000))
    }
}
