import Foundation

/// Decides when the display has stopped changing after an auto-scroll step (spec 2.8, Settling).
///
/// Content is compared, not the frame status, because a complete frame also arrives for a change
/// elsewhere on the display. The driver feeds each observation; the area is settled when no frame
/// with a new content hash arrived for `quiet`, or `timeout` after the step, whichever comes first.
nonisolated struct FrameSettler: Sendable {
    enum Observation: Equatable, Sendable {
        /// A complete frame whose content hash is `hash`.
        case frame(hash: UInt64, at: ContinuousClock.Instant)
        /// The stream reported that the display did not change. It counts as unchanged.
        case idle(at: ContinuousClock.Instant)
    }

    static let defaultQuiet: Duration = .milliseconds(150)
    static let defaultTimeout: Duration = .milliseconds(1500)

    let quiet: Duration
    let timeout: Duration
    private let stepStart: ContinuousClock.Instant
    private var lastHash: UInt64?
    private var lastChange: ContinuousClock.Instant

    /// `baselineHash` is the content hash of the frame before the step. A frame that still has
    /// it is not a change; without one the first frame is.
    init(stepStart: ContinuousClock.Instant, baselineHash: UInt64? = nil,
         quiet: Duration = defaultQuiet, timeout: Duration = defaultTimeout) {
        self.stepStart = stepStart
        self.quiet = quiet
        self.timeout = timeout
        lastHash = baselineHash
        lastChange = stepStart
    }

    /// Records an observation and reports whether the area has settled as of its time.
    mutating func observe(_ observation: Observation) -> Bool {
        switch observation {
        case .frame(let hash, let time):
            if hash != lastHash {
                lastHash = hash
                lastChange = time
            }
            return isSettled(at: time)
        case .idle(let time):
            return isSettled(at: time)
        }
    }

    /// For a timer that wakes the driver when no frames arrive at all.
    func isSettled(at now: ContinuousClock.Instant) -> Bool {
        now - lastChange >= quiet || now - stepStart >= timeout
    }

    /// A cheap content hash of a frame: FNV-1a (64 bit) over the grey plane of every third row,
    /// leaving out the rightmost `ignoringRightColumns` columns, where overlay scrollbars fade in
    /// and out. Scrolling changes every row, so sampling rows loses nothing here.
    static func contentHash(of frame: ScrollFrame, ignoringRightColumns: Int) -> UInt64 {
        let columns = max(1, frame.width - ignoringRightColumns)
        var hash: UInt64 = 0xcbf29ce484222325
        frame.gray.withUnsafeBufferPointer { grey in
            for y in stride(from: 0, to: frame.height, by: 3) {
                let base = y * frame.width
                for x in 0..<columns { hash = (hash ^ UInt64(grey[base + x])) &* 0x100000001b3 }
            }
        }
        return hash
    }
}
