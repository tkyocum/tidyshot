import AppKit
import CoreGraphics
import Foundation
@testable import TidyShot

/// What the driver, the chrome and the environment did, in one ordered list, so a test can check
/// that nothing touched the file before the stop wait ended.
final class RecordingTestLog {
    private(set) var entries: [String] = []

    func append(_ entry: String) {
        entries.append(entry)
    }

    /// The file accesses (inspect, poster, remove), in order.
    var fileAccesses: [String] {
        entries.filter { ["inspect", "poster", "remove"].contains($0) }
    }
}

/// A `RecordingStreamDriver` the tests drive by hand: they send its events, hold its start, and
/// choose when its stop sends `recordingFinished`.
final class FakeRecordingDriver: RecordingStreamDriver {
    /// When `stop()` sends `recordingFinished`.
    enum FinishTiming {
        case beforeReturning
        /// In a task that runs once `stop()` has returned and the caller has suspended.
        case afterReturning
        /// Only when the test sends it.
        case never
    }

    let log: RecordingTestLog
    var finishTiming: FinishTiming = .beforeReturning
    /// When true, `start` suspends after counting itself until `releaseStart()`, like a driver
    /// still fetching the shareable content.
    var holdsStart = false
    /// Thrown by `start` when set, after any hold.
    var startError: (any Error)?
    /// When true, `stop` suspends after any finish it sends first, until `releaseStop()`, like a
    /// `stopCapture()` that does not return.
    var holdsStop = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var configuration: RecordingConfiguration?
    private(set) var outputURL: URL?
    private(set) var exclusions: RecordingExclusions?
    private var events: ((RecordingStreamEvent) -> Void)?
    private var startGate: CheckedContinuation<Void, Never>?
    private var stopGate: CheckedContinuation<Void, Never>?

    init(log: RecordingTestLog) {
        self.log = log
    }

    func start(_ configuration: RecordingConfiguration, outputURL: URL, exclusions: RecordingExclusions,
               events: @escaping (RecordingStreamEvent) -> Void) async throws {
        startCount += 1
        self.configuration = configuration
        self.outputURL = outputURL
        self.exclusions = exclusions
        self.events = events
        log.append("start")
        if holdsStart { await withCheckedContinuation { startGate = $0 } }
        if let startError { throw startError }
    }

    func stop() async throws {
        stopCount += 1
        log.append("stop")
        switch finishTiming {
        case .beforeReturning:
            send(.recordingFinished)
        case .afterReturning:
            Task { self.send(.recordingFinished) }
        case .never:
            break
        }
        if holdsStop { await withCheckedContinuation { stopGate = $0 } }
        log.append("stop returned")
    }

    /// True while a held `start` waits.
    var isHoldingStart: Bool { startGate != nil }

    func releaseStart() {
        holdsStart = false
        startGate?.resume()
        startGate = nil
    }

    /// True while a held `stop` waits.
    var isHoldingStop: Bool { stopGate != nil }

    func releaseStop() {
        holdsStop = false
        stopGate?.resume()
        stopGate = nil
    }

    /// Delivers `event` as the real driver does, on the main actor.
    func send(_ event: RecordingStreamEvent) {
        log.append("\(event)")
        events?(event)
    }
}

/// A `RecordingChrome` that records its calls and answers the discard question as scripted.
final class FakeRecordingChrome: RecordingChrome {
    let log: RecordingTestLog
    var windowNumbers: Set<CGWindowID> = [41, 42]
    /// What `askToDiscard` answers: true for Discard, false for Save.
    var discards = true
    /// When true, `askToDiscard` waits until `answerDiscardWithSave()`, like the real alert while
    /// AppKit holds a quit and the run loop never enters its default mode.
    var holdsAsk = false
    private(set) var calls: [String] = []
    /// The bar each `show` laid out.
    private(set) var shownBars: [RecordingPanelLayout.Bar] = []
    private(set) var elapsedShown: [TimeInterval] = []
    private var onStop: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var askGate: CheckedContinuation<Bool, Never>?

    init(log: RecordingTestLog) {
        self.log = log
    }

    func show(onStop: @escaping () -> Void, onCancel: @escaping () -> Void, bar: RecordingPanelLayout.Bar) {
        self.onStop = onStop
        self.onCancel = onCancel
        shownBars.append(bar)
        calls.append("show")
        log.append("show")
    }

    func update(elapsed: TimeInterval) {
        elapsedShown.append(elapsed)
    }

    func setStopEnabled(_ enabled: Bool) {
        calls.append(enabled ? "stop enabled" : "stop disabled")
    }

    func askToDiscard(elapsed: TimeInterval) async -> Bool {
        calls.append("ask \(RecordingClock.format(elapsed))")
        log.append("ask")
        guard holdsAsk else { return discards }
        return await withCheckedContinuation { askGate = $0 }
    }

    /// True while a held `askToDiscard` waits.
    var isAsking: Bool { askGate != nil }

    func answerDiscardWithSave() {
        calls.append("answer save")
        askGate?.resume(returning: false)
        askGate = nil
    }

    func close() {
        calls.append("close")
        log.append("close")
    }

    /// The panel's Stop button.
    func pressStop() {
        onStop?()
    }

    /// The panel's Cancel button.
    func pressCancel() {
        onCancel?()
    }
}

/// The controller's world on two `FakeScrollClock`s, the continuous one and the one that stops
/// while the Mac sleeps: a date the test sets, free space, the listed windows, the card and cover
/// windows, and the file's facts. It logs every file access and each activity's begin and end,
/// and has its own `NotificationCenter` for the workspace.
final class RecordingTestWorld {
    let clock = FakeScrollClock()
    let awakeClock = FakeScrollClock()
    let center = NotificationCenter()
    let log = RecordingTestLog()
    var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var freeBytes: Int64? = 100_000_000_000
    var listedWindows: Set<CGWindowID> = []
    var cardWindows: Set<CGWindowID> = [7]
    var coverWindows: [CGDirectDisplayID: Set<CGWindowID>] = [:]
    var facts = VideoFacts.playable(seconds: 10)
    let poster = RecordingTestWorld.makePoster()
    private(set) var freeSpaceURLs: [URL] = []
    private(set) var activitiesBegun = 0
    private(set) var activitiesEnded = 0

    var environment: RecordingEnvironment {
        RecordingEnvironment(
            clock: clock,
            awakeClock: awakeClock,
            now: { [unowned self] in date },
            freeBytes: { [unowned self] url in
                freeSpaceURLs.append(url)
                return freeBytes
            },
            windowIsListed: { [unowned self] id in listedWindows.contains(id) },
            cardWindowNumbers: { [unowned self] in cardWindows },
            coverWindowNumbers: { [unowned self] id in coverWindows[id] ?? [] },
            beginActivity: { [unowned self] in
                activitiesBegun += 1
                log.append("activity begun")
                return NSObject()
            },
            endActivity: { [unowned self] _ in
                activitiesEnded += 1
                log.append("activity ended")
            },
            inspect: { [unowned self] _ in
                log.append("inspect")
                return facts
            },
            poster: { [unowned self] _ in
                log.append("poster")
                return poster
            },
            removeFile: { [unowned self] _ in log.append("remove") },
            workspaceCenter: center)
    }

    /// Lets `duration` pass with the Mac awake: both clocks move.
    func advance(by duration: Duration) async {
        await clock.advance(by: duration)
        await awakeClock.advance(by: duration)
    }

    /// Lets `duration` pass with the Mac asleep: only the continuous clock moves.
    func sleepTheMac(for duration: Duration) async {
        await clock.advance(by: duration)
    }

    private static func makePoster() -> CGImage {
        let context = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}

extension VideoFacts {
    /// A playable 1600×1000 file with one video track.
    static func playable(seconds: TimeInterval) -> VideoFacts {
        VideoFacts(isPlayable: true, duration: seconds, naturalSize: CGSize(width: 1600, height: 1000), videoTracks: 1,
                   audioTracks: 0, byteCount: 1_000_000, meetsMinimum: seconds >= RecordingLimits.minimumDuration)
    }

    static let unplayable = VideoFacts(isPlayable: false, duration: 0, naturalSize: nil, videoTracks: 0, audioTracks: 0,
                                       byteCount: 0, meetsMinimum: false)
}

extension RecordingOutcome {
    /// The kept recording, or nil.
    var kept: Recording? {
        if case .keep(let recording, _) = self { recording } else { nil }
    }

    var notice: RecordingNotice? {
        switch self {
        case .keep(_, let notice), .nothing(let notice): notice
        }
    }
}
