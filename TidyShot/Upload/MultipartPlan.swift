import Foundation

/// When an upload goes in parts, how big the parts are, and whether a stored upload resumes.
/// Pure. The threshold and part size are injectable so tests can use small files.
nonisolated struct MultipartPlan: Equatable, Sendable {
    /// A `.file` payload of this many bytes or more goes multipart.
    var threshold: Int64
    /// The part size before any raise for the part limit.
    var partSize: Int64
    /// Parts in flight at a time within one job.
    var inFlight: Int

    init(threshold: Int64, partSize: Int64, inFlight: Int) {
        self.threshold = threshold
        self.partSize = partSize
        self.inFlight = inFlight
    }

    /// 100 MiB, 16 MiB parts, 3 at a time.
    static let standard = MultipartPlan(threshold: 104_857_600, partSize: 16_777_216, inFlight: 3)

    /// 64 MiB.
    static let maxPartSize: Int64 = 67_108_864
    static let maxParts = 10_000
    /// 10,000 parts of 64 MiB: 625 GiB. A larger file is not uploaded.
    static let maxBytes: Int64 = 671_088_640_000
    /// Restarts (a new upload id) a job may make before it fails.
    static let restartLimit = 2
    /// 7 days: the lifecycle rule has aborted an upload this old, or will.
    static let stateLifetime: TimeInterval = 604_800

    private static let mib: Int64 = 1_048_576

    static func fits(byteCount: Int64) -> Bool {
        byteCount <= maxBytes
    }

    /// True for a file of known size at or above the threshold. A size that cannot be read counts
    /// as a single PUT, as does data in memory.
    func uses(payload: UploadPayload, byteCount: Int64?) -> Bool {
        guard case .file = payload, let byteCount else { return false }
        return byteCount >= threshold
    }

    /// The base part size, raised to `ceil(byteCount / maxParts)` rounded up to a whole MiB when
    /// the base would need more than `maxParts` parts. Nil when that exceeds `maxPartSize`.
    func partSize(for byteCount: Int64) -> Int64? {
        var size = partSize
        if Self.partCount(byteCount: byteCount, partSize: size) > Self.maxParts {
            let least = Self.ceilDiv(byteCount, Int64(Self.maxParts))
            size = Self.ceilDiv(least, Self.mib) * Self.mib
        }
        return size <= Self.maxPartSize ? size : nil
    }

    static func partCount(byteCount: Int64, partSize: Int64) -> Int {
        guard byteCount > 0, partSize > 0 else { return 0 }
        return Int(ceilDiv(byteCount, partSize))
    }

    /// The bytes of part `number` (1-based). Every part is `partSize` long but the last, which
    /// holds what is left.
    static func range(ofPart number: Int, partSize: Int64, byteCount: Int64) -> Range<Int64> {
        let start = Int64(number - 1) * partSize
        return start..<min(start + partSize, byteCount)
    }

    /// Bytes of completed parts plus the bytes in-flight parts have sent, over the file's size,
    /// kept within 0...1.
    static func fraction(doneBytes: Int64, inFlightBytes: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(max(Double(doneBytes + inFlightBytes) / Double(total), 0), 1)
    }

    /// Resume when the stored upload is at the lane's location, under the fixed key for a
    /// fixed-key job (any stored key for a template job), and its source is unchanged. Otherwise
    /// start over and abort the stored upload, with the first reason found.
    static func resumeDecision(stored: MultipartUploadState, location: ObjectLocation, fixedKey: String?,
                               source: MultipartSourceAttributes?) -> MultipartResumeDecision {
        let reason: MultipartStartOverReason
        if stored.location != location {
            reason = .location
        } else if let fixedKey, fixedKey != stored.key {
            reason = .key
        } else if let source, source.byteCount == stored.byteCount, source.modified == stored.sourceModified {
            return .resume(stored)
        } else {
            reason = .source
        }
        return .startOver(reason: reason, abort: stored.ref)
    }

    /// True when the stored upload sends a kept Clop copy (`sourcePath` in `keptCopyFolder`) and
    /// the record's own file was written after the upload started: a trim since, so the copy holds
    /// the earlier file and must not be completed at the link. The copy's own size and date still
    /// match, so `startUpload` passes no source and the upload starts over. False when the record's
    /// file could not be read, or the upload sends that file (the source check covers it).
    static func keptCopyIsOutdated(stored: MultipartUploadState, keptCopyFolder: URL, recordFileModified: Date?) -> Bool {
        guard let recordFileModified,
              SaveLocation.contains(URL(filePath: stored.sourcePath), inFolder: keptCopyFolder) else { return false }
        return recordFileModified > stored.startedAt
    }

    /// What `startUpload` does for `decision` (nil when the record has no stored upload).
    static func startStep(decision: MultipartResumeDecision?) -> UploadStartStep {
        switch decision {
        case nil:
            UploadStartStep(runsClop: true, drawsCounter: true)
        case .resume(let state):
            UploadStartStep(runsClop: false, drawsCounter: false, resume: state)
        case .startOver(.location, let ref):
            UploadStartStep(runsClop: true, drawsCounter: true, abortElsewhere: ref)
        case .startOver(_, let ref):
            UploadStartStep(runsClop: true, drawsCounter: true, abortFirst: ref)
        }
    }

    /// `a / b` rounded up, for positive `a` and `b`, without overflowing near `Int64.max`.
    private static func ceilDiv(_ a: Int64, _ b: Int64) -> Int64 {
        a / b + (a % b == 0 ? 0 : 1)
    }
}

/// The size and modification date of the file a stored upload names, read now.
nonisolated struct MultipartSourceAttributes: Equatable, Sendable {
    var byteCount: Int64
    var modified: Date
}

nonisolated enum MultipartStartOverReason: Equatable, Sendable {
    case location, key, source

    /// For `Upload: <name> <logText>, starting again`.
    var logText: String {
        switch self {
        case .location: "destination changed"
        case .key: "key changed"
        case .source: "source changed"
        }
    }
}

nonisolated enum MultipartResumeDecision: Equatable, Sendable {
    case resume(MultipartUploadState)
    case startOver(reason: MultipartStartOverReason, abort: MultipartRef)
}

/// What `startUpload` does before it enqueues. `runsClop` and `drawsCounter` are permissions:
/// true applies the existing rule (Clop when the setting, the kind and a running Clop allow; a
/// counter when the template has `{counter}`), false skips it.
nonisolated struct UploadStartStep: Equatable, Sendable {
    var runsClop: Bool
    var drawsCounter: Bool
    /// The stored upload to resume; the job sends its `sourcePath`.
    var resume: MultipartUploadState?
    /// A stored upload the queue aborts first, through the lane's destination.
    var abortFirst: MultipartRef?
    /// A stored upload at another location, which the coordinator aborts through a destination
    /// built from the ref's location.
    var abortElsewhere: MultipartRef?

    init(runsClop: Bool, drawsCounter: Bool, resume: MultipartUploadState? = nil,
         abortFirst: MultipartRef? = nil, abortElsewhere: MultipartRef? = nil) {
        self.runsClop = runsClop
        self.drawsCounter = drawsCounter
        self.resume = resume
        self.abortFirst = abortFirst
        self.abortElsewhere = abortElsewhere
    }
}
