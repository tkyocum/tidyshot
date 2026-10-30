import Foundation
import Testing
@testable import TidyShot

/// When a payload goes multipart, the part size and ranges, progress, the resume decision, and the
/// stored state's coding (design, Multipart upload).
struct MultipartPlanTests {
    private static let mib: Int64 = 1_048_576
    private static let gib: Int64 = 1_073_741_824
    private let plan = MultipartPlan.standard
    private let file = UploadPayload.file(URL(fileURLWithPath: "/tmp/a.mp4"), scope: nil)

    private static let bucket = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                               bucket: "snap.tky.io", usePathStyle: true)
    private static let otherBucket = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                                    bucket: "other.tky.io", usePathStyle: true)
    /// A modification date with sub-millisecond digits, as APFS gives.
    private static let modified = Date(timeIntervalSinceReferenceDate: 783_456_789.123_456_7)

    private static func state(key: String = "r/abc.mp4", location: ObjectLocation = bucket) -> MultipartUploadState {
        MultipartUploadState(uploadID: "upload-1", key: key, location: location, partSize: 16 * mib,
                             byteCount: 300 * mib, sourceModified: modified, sourcePath: "/Users/tim/Captures/a.mp4",
                             startedAt: Date(timeIntervalSinceReferenceDate: 783_400_000))
    }

    private static let matching = MultipartSourceAttributes(byteCount: 300 * mib, modified: modified)

    // MARK: Constants

    @Test func standardPlanAndLimits() {
        #expect(MultipartPlan.standard == MultipartPlan(threshold: 104_857_600, partSize: 16_777_216, inFlight: 3))
        #expect(MultipartPlan.maxPartSize == 64 * Self.mib)
        #expect(MultipartPlan.maxParts == 10_000)
        #expect(MultipartPlan.maxBytes == 625 * Self.gib)
        #expect(MultipartPlan.restartLimit == 2)
        #expect(MultipartPlan.stateLifetime == 7 * 24 * 60 * 60)
    }

    // MARK: uses

    @Test func usesAtTheThresholdForAFile() {
        #expect(plan.uses(payload: file, byteCount: 100 * Self.mib))
        #expect(plan.uses(payload: file, byteCount: 6 * Self.gib))
        #expect(!plan.uses(payload: file, byteCount: 100 * Self.mib - 1))
    }

    @Test(arguments: [0, 104_857_600, 6_442_450_944] as [Int64])
    func neverUsesForData(byteCount: Int64) {
        #expect(!plan.uses(payload: .data(Data([1, 2, 3])), byteCount: byteCount))
    }

    @Test func unknownSizeIsASinglePut() {
        #expect(!plan.uses(payload: file, byteCount: nil))
    }

    @Test func injectedThreshold() {
        let small = MultipartPlan(threshold: Self.mib, partSize: 256 * 1024, inFlight: 3)
        #expect(small.uses(payload: file, byteCount: Self.mib))
        #expect(!small.uses(payload: file, byteCount: Self.mib - 1))
    }

    // MARK: partSize

    @Test func partSizeIsTheBaseUpTo10000Parts() {
        #expect(plan.partSize(for: Self.gib) == 16 * Self.mib)
        #expect(plan.partSize(for: 167_772_160_000) == 16 * Self.mib)
    }

    @Test func partSizeIsRaisedToAWholeMiBAbove10000Parts() {
        #expect(plan.partSize(for: 167_772_160_001) == 17 * Self.mib)
        #expect(plan.partSize(for: 160 * Self.gib) == 17 * Self.mib)
        #expect(plan.partSize(for: 625 * Self.gib) == 64 * Self.mib)
    }

    @Test func partSizeIsNilAbove625GiB() {
        #expect(plan.partSize(for: 625 * Self.gib + 1) == nil)
    }

    @Test func raisedPartSizeKeepsWithin10000Parts() throws {
        for byteCount in [160 * Self.gib, 400 * Self.gib + 12_345, 625 * Self.gib] {
            let size = try #require(plan.partSize(for: byteCount))
            #expect(MultipartPlan.partCount(byteCount: byteCount, partSize: size) <= MultipartPlan.maxParts)
        }
    }

    // MARK: partCount and range

    @Test func partsOf100MiB() {
        let size = 16 * Self.mib
        #expect(MultipartPlan.partCount(byteCount: 100 * Self.mib, partSize: size) == 7)
        #expect(MultipartPlan.range(ofPart: 1, partSize: size, byteCount: 100 * Self.mib) == 0..<16_777_216)
        #expect(MultipartPlan.range(ofPart: 2, partSize: size, byteCount: 100 * Self.mib) == 16_777_216..<33_554_432)
        #expect(MultipartPlan.range(ofPart: 7, partSize: size, byteCount: 100 * Self.mib) == 100_663_296..<104_857_600)
    }

    @Test func oneByteOverAWholePartAddsAOneBytePart() {
        let size = 16 * Self.mib
        #expect(MultipartPlan.partCount(byteCount: 112 * Self.mib, partSize: size) == 7)
        #expect(MultipartPlan.partCount(byteCount: 112 * Self.mib + 1, partSize: size) == 8)
        let last = MultipartPlan.range(ofPart: 8, partSize: size, byteCount: 112 * Self.mib + 1)
        #expect(last == 117_440_512..<117_440_513)
        #expect(last.count == 1)
    }

    @Test func rangesCoverTheFileWithoutGaps() {
        let size: Int64 = 256 * 1024
        let byteCount: Int64 = 3 * Self.mib + 777
        let count = MultipartPlan.partCount(byteCount: byteCount, partSize: size)
        var next: Int64 = 0
        for number in 1...count {
            let range = MultipartPlan.range(ofPart: number, partSize: size, byteCount: byteCount)
            #expect(range.lowerBound == next)
            #expect(range.count == (number < count ? size : 777))
            next = range.upperBound
        }
        #expect(next == byteCount)
    }

    // MARK: fits

    @Test func fitsUpTo625GiB() {
        #expect(MultipartPlan.fits(byteCount: MultipartPlan.maxBytes))
        #expect(MultipartPlan.fits(byteCount: 6 * Self.gib))
        #expect(!MultipartPlan.fits(byteCount: MultipartPlan.maxBytes + 1))
    }

    // MARK: fraction

    @Test func fractionCountsDoneAndInFlightBytes() {
        #expect(MultipartPlan.fraction(doneBytes: 25, inFlightBytes: 25, total: 100) == 0.5)
        #expect(MultipartPlan.fraction(doneBytes: 0, inFlightBytes: 0, total: 100) == 0)
        #expect(MultipartPlan.fraction(doneBytes: 100, inFlightBytes: 0, total: 100) == 1)
    }

    @Test func fractionNeverExceedsOne() {
        #expect(MultipartPlan.fraction(doneBytes: 90, inFlightBytes: 40, total: 100) == 1)
        #expect(MultipartPlan.fraction(doneBytes: 200, inFlightBytes: 0, total: 100) == 1)
    }

    @Test func fractionIsZeroForNoTotal() {
        #expect(MultipartPlan.fraction(doneBytes: 10, inFlightBytes: 10, total: 0) == 0)
        #expect(MultipartPlan.fraction(doneBytes: 10, inFlightBytes: 10, total: -1) == 0)
    }

    // MARK: resumeDecision

    @Test func resumesWhenEverythingMatches() {
        let stored = Self.state()
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.bucket, fixedKey: "r/abc.mp4",
                                             source: Self.matching) == .resume(stored))
    }

    @Test func templateJobResumesUnderAnyStoredKey() {
        let stored = Self.state(key: "r/whatever-was-drawn.mp4")
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.bucket, fixedKey: nil,
                                             source: Self.matching) == .resume(stored))
    }

    @Test func startsOverWhenTheDestinationChanged() {
        let stored = Self.state()
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.otherBucket, fixedKey: nil, source: Self.matching)
            == .startOver(reason: .location, abort: stored.ref))
    }

    @Test func destinationIsCheckedBeforeKeyAndSource() {
        let stored = Self.state()
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.otherBucket, fixedKey: "r/new.mp4", source: nil)
            == .startOver(reason: .location, abort: stored.ref))
    }

    @Test func fixedKeyJobStartsOverWhenTheStoredKeyDiffers() {
        let stored = Self.state(key: "r/old.mp4")
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.bucket, fixedKey: "r/new.mp4", source: Self.matching)
            == .startOver(reason: .key, abort: stored.ref))
    }

    @Test func startsOverWhenTheSourceSizeDiffers() {
        let stored = Self.state()
        let source = MultipartSourceAttributes(byteCount: 300 * Self.mib + 1, modified: Self.modified)
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.bucket, fixedKey: nil, source: source)
            == .startOver(reason: .source, abort: stored.ref))
    }

    @Test func startsOverWhenTheSourceDateDiffers() {
        let stored = Self.state()
        // A millisecond-rounded date, as ISO 8601 with milliseconds would have kept it.
        let rounded = Date(timeIntervalSinceReferenceDate: 783_456_789.123)
        let source = MultipartSourceAttributes(byteCount: 300 * Self.mib, modified: rounded)
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.bucket, fixedKey: nil, source: source)
            == .startOver(reason: .source, abort: stored.ref))
    }

    @Test func startsOverWhenTheSourceIsMissing() {
        let stored = Self.state()
        #expect(MultipartPlan.resumeDecision(stored: stored, location: Self.bucket, fixedKey: nil, source: nil)
            == .startOver(reason: .source, abort: stored.ref))
    }

    @Test func abortRefIsTheStoredUpload() {
        let stored = Self.state()
        #expect(stored.ref == MultipartRef(uploadID: "upload-1", key: "r/abc.mp4", location: Self.bucket))
    }

    @Test func startOverReasonLogText() {
        #expect(MultipartStartOverReason.location.logText == "destination changed")
        #expect(MultipartStartOverReason.key.logText == "key changed")
        #expect(MultipartStartOverReason.source.logText == "source changed")
    }

    // MARK: Stored state

    @Test func stateRoundTripsThroughISO8601KeepingSubMillisecondDate() throws {
        let stored = Self.state()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(stored)
        let decoded = try decoder.decode(MultipartUploadState.self, from: data)
        #expect(decoded == stored)
        #expect(decoded.sourceModified == Self.modified)
        #expect(decoded.sourceModified.timeIntervalSinceReferenceDate == 783_456_789.123_456_7)
    }

    @Test func stateJSONHoldsSourceModifiedAsANumber() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Self.state())
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let value = (object["sourceModified"] as? NSNumber)?.doubleValue
        #expect(value == 783_456_789.123_456_7)
        #expect(object["startedAt"] is String)
        #expect(Set(object.keys) == ["uploadID", "key", "location", "partSize", "byteCount", "sourceModified",
                                     "sourcePath", "startedAt"])
    }

    @Test func sidecarRoundTrips() throws {
        let sidecar = MultipartSidecar(uploadID: "upload-1", completeSent: true,
                                       parts: [MultipartPart(number: 1, etag: "\"a\"", size: 16 * Self.mib),
                                               MultipartPart(number: 2, etag: "\"b\"", size: 5)])
        let decoded = try JSONDecoder().decode(MultipartSidecar.self, from: JSONEncoder().encode(sidecar))
        #expect(decoded == sidecar)
    }
}
