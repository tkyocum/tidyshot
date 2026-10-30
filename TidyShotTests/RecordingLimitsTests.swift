import Foundation
import Testing
@testable import TidyShot

struct RecordingLimitsTests {
    @Test func startIsRefusedUnder2GB() {
        #expect(RecordingLimits.startFreeBytes == 2_000_000_000)
        #expect(RecordingLimits.refusesStart(freeBytes: 1_999_999_999))
        #expect(!RecordingLimits.refusesStart(freeBytes: 2_000_000_000))
        #expect(!RecordingLimits.refusesStart(freeBytes: 50_000_000_000))
    }

    @Test func recordingStopsUnder1GB() {
        #expect(RecordingLimits.runningFreeBytes == 1_000_000_000)
        #expect(RecordingLimits.stopsRecording(freeBytes: 999_999_999))
        #expect(!RecordingLimits.stopsRecording(freeBytes: 1_000_000_000))
    }

    /// An unreadable free-space value counts as enough (Gap 1).
    @Test func unknownFreeSpaceNeitherRefusesNorStops() {
        #expect(!RecordingLimits.refusesStart(freeBytes: nil))
        #expect(!RecordingLimits.stopsRecording(freeBytes: nil))
    }

    /// Room for a step that writes a copy (R2): the copy's size plus the 1 GB a recording keeps free.
    @Test func roomNeedsTheSizePlus1GB() {
        let size: Int64 = 420_000_000
        #expect(RecordingLimits.hasRoom(for: size, freeBytes: size + 1_000_000_000))
        #expect(!RecordingLimits.hasRoom(for: size, freeBytes: size + 999_999_999))
        #expect(RecordingLimits.hasRoom(for: size, freeBytes: 50_000_000_000))
        #expect(RecordingLimits.hasRoom(for: 0, freeBytes: 1_000_000_000))
        #expect(!RecordingLimits.hasRoom(for: 0, freeBytes: 999_999_999))
    }

    /// An unreadable free-space value counts as enough, as in R1.
    @Test func unknownFreeSpaceHasRoom() {
        #expect(RecordingLimits.hasRoom(for: 0, freeBytes: nil))
        #expect(RecordingLimits.hasRoom(for: 5_000_000_000, freeBytes: nil))
    }

    @Test func cancelAsksFromFiveSeconds() {
        #expect(!RecordingLimits.asksBeforeDiscarding(elapsed: 4.9))
        #expect(RecordingLimits.asksBeforeDiscarding(elapsed: 5))
        #expect(RecordingLimits.asksBeforeDiscarding(elapsed: 300))
    }

    @Test func constants() {
        #expect(RecordingLimits.diskCheckInterval == .seconds(5))
        #expect(RecordingLimits.cancelConfirmationSeconds == 5)
        #expect(RecordingLimits.minimumDuration == 0.5)
        #expect(RecordingLimits.stopTimeout == .seconds(15))
        #expect(RecordingLimits.diskFullText == "Your disk is almost full.")
    }

    /// A fresh container has no `tmp/Recording` yet; its nearest existing folder is read instead.
    @Test func freeBytesOfAMissingFolderReadsItsNearestAncestor() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let missing = dir.appending(path: "Recording/deeper", directoryHint: .isDirectory)
        let free = try #require(RecordingLimits.freeBytes(at: missing))
        #expect(free > 0)
        #expect(!FileManager.default.fileExists(atPath: missing.path(percentEncoded: false)))
    }
}
