import Foundation
import Testing
@testable import TidyShot

/// `MultipartPlan.startStep(decision:)`: what `startUpload` does after `resumeDecision`, that is
/// whether Clop runs, whether a counter is drawn, which file is sent and what is aborted first
/// (design, Resume).
struct UploadStartTests {
    private static let bucket = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                               bucket: "snap.tky.io", usePathStyle: true)
    private static let otherBucket = ObjectLocation(endpoint: "https://s3.eu-west-1.amazonaws.com", region: "eu-west-1",
                                                    bucket: "elsewhere", usePathStyle: false)
    private static let modified = Date(timeIntervalSinceReferenceDate: 783_456_789.123_456_7)
    private static let recordFile = "/Users/tim/Captures/Recording 2026-10-27 at 10.00.00.mp4"
    private static let keptClopCopy = "/Users/tim/Library/Containers/io.tky.TidyShot/Data/Library/Application Support/TidyShot/multipart/A.mp4"

    private static func state(sourcePath: String = keptClopCopy, key: String = "r/abc.mp4") -> MultipartUploadState {
        MultipartUploadState(uploadID: "upload-1", key: key, location: bucket, partSize: 16_777_216,
                             byteCount: 314_572_800, sourceModified: modified, sourcePath: sourcePath,
                             startedAt: Date(timeIntervalSinceReferenceDate: 783_400_000))
    }

    private static func step(stored: MultipartUploadState, location: ObjectLocation = bucket, fixedKey: String? = nil,
                             source: MultipartSourceAttributes?) -> UploadStartStep {
        MultipartPlan.startStep(decision: MultipartPlan.resumeDecision(stored: stored, location: location,
                                                                       fixedKey: fixedKey, source: source))
    }

    private static let matching = MultipartSourceAttributes(byteCount: 314_572_800, modified: modified)

    @Test func noStoredStateRunsAsToday() {
        let step = MultipartPlan.startStep(decision: nil)
        #expect(step == UploadStartStep(runsClop: true, drawsCounter: true, resume: nil, abortFirst: nil, abortElsewhere: nil))
    }

    @Test func matchingSourceResumesFromSourcePath() {
        let stored = Self.state()
        let step = Self.step(stored: stored, source: Self.matching)
        #expect(step.resume == stored)
        #expect(step.resume?.sourcePath == Self.keptClopCopy)
        #expect(!step.runsClop)
        #expect(!step.drawsCounter)
        #expect(step.abortFirst == nil)
        #expect(step.abortElsewhere == nil)
    }

    @Test func changedSourceStartsOverAndAbortsFirst() {
        let stored = Self.state()
        let source = MultipartSourceAttributes(byteCount: 314_572_801, modified: Self.modified)
        let step = Self.step(stored: stored, source: source)
        #expect(step == UploadStartStep(runsClop: true, drawsCounter: true, resume: nil, abortFirst: stored.ref, abortElsewhere: nil))
    }

    @Test func missingSourceStartsOverAndAbortsFirst() {
        let stored = Self.state()
        let step = Self.step(stored: stored, source: nil)
        #expect(step == UploadStartStep(runsClop: true, drawsCounter: true, resume: nil, abortFirst: stored.ref, abortElsewhere: nil))
    }

    @Test func changedKeyStartsOverAndAbortsFirst() {
        let stored = Self.state(key: "r/old.mp4")
        let step = Self.step(stored: stored, fixedKey: "r/new.mp4", source: Self.matching)
        #expect(step == UploadStartStep(runsClop: true, drawsCounter: true, resume: nil, abortFirst: stored.ref, abortElsewhere: nil))
    }

    @Test func changedDestinationStartsOverAndLeavesTheAbortToTheCoordinator() {
        let stored = Self.state()
        let step = Self.step(stored: stored, location: Self.otherBucket, source: Self.matching)
        #expect(step == UploadStartStep(runsClop: true, drawsCounter: true, resume: nil, abortFirst: nil, abortElsewhere: stored.ref))
        #expect(step.abortElsewhere?.location == Self.bucket)
    }

    /// The first attempt ran with Clop off (or not running), so the state names the record's own
    /// file. Clop running now changes nothing: the resume sends that file, so a Clop result is
    /// never spliced onto the original's parts.
    @Test func resumeAfterAFirstAttemptWithClopOffSendsTheRecordsFile() {
        let stored = Self.state(sourcePath: Self.recordFile)
        let step = Self.step(stored: stored, source: Self.matching)
        #expect(step.resume?.sourcePath == Self.recordFile)
        #expect(!step.runsClop)
        #expect(!step.drawsCounter)
    }

    // MARK: A kept Clop copy and a newer record file

    private static let keptCopyFolder = URL(filePath: "/Users/tim/Library/Containers/io.tky.TidyShot/Data/Library/Application Support/TidyShot/multipart",
                                            directoryHint: .isDirectory)

    private static func keptCopyIsOutdated(stored: MultipartUploadState, recordFileModified: Date?) -> Bool {
        MultipartPlan.keptCopyIsOutdated(stored: stored, keptCopyFolder: keptCopyFolder, recordFileModified: recordFileModified)
    }

    /// `Upload Trimmed` failed with Clop's copy kept, then a second trim wrote the record's file:
    /// the copy still matches its own size and date, but holds the earlier trim, so the upload
    /// starts over rather than completing the earlier trim's bytes at the link.
    @Test func aRecordFileWrittenAfterTheUploadStartedOutdatesTheKeptCopy() {
        let stored = Self.state()
        let outdated = Self.keptCopyIsOutdated(stored: stored, recordFileModified: stored.startedAt.addingTimeInterval(60))
        #expect(outdated)
        let step = Self.step(stored: stored, fixedKey: stored.key, source: outdated ? nil : Self.matching)
        #expect(step == UploadStartStep(runsClop: true, drawsCounter: true, resume: nil, abortFirst: stored.ref, abortElsewhere: nil))
    }

    /// The record's file was written before Create (capture, or the trim this upload sends):
    /// the kept copy is Clop's result of it, and the upload resumes.
    @Test func aRecordFileWrittenBeforeTheUploadStartedKeepsTheCopy() {
        let stored = Self.state()
        #expect(!Self.keptCopyIsOutdated(stored: stored, recordFileModified: stored.startedAt.addingTimeInterval(-60)))
    }

    /// The record's file could not be read: nothing says the copy is older, so the source check
    /// alone decides.
    @Test func anUnreadableRecordFileKeepsTheCopy() {
        #expect(!Self.keptCopyIsOutdated(stored: Self.state(), recordFileModified: nil))
    }

    /// A stored upload that sends the record's own file is checked by the source check itself.
    @Test func aStoredUploadOfTheRecordsFileHasNoKeptCopy() {
        let stored = Self.state(sourcePath: Self.recordFile)
        #expect(!Self.keptCopyIsOutdated(stored: stored, recordFileModified: stored.startedAt.addingTimeInterval(60)))
    }
}
