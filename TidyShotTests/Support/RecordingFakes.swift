import AppKit
import CoreGraphics
import Foundation
import Synchronization
import Testing
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
    /// Each `setMuted`, in order.
    private(set) var mutedShown: [Bool] = []
    private var onStop: (() -> Void)?
    private var onCancel: (() -> Void)?
    private var onMute: (() -> Void)?
    private var askGate: CheckedContinuation<Bool, Never>?

    init(log: RecordingTestLog) {
        self.log = log
    }

    func show(onStop: @escaping () -> Void, onCancel: @escaping () -> Void, onMute: @escaping () -> Void,
              bar: RecordingPanelLayout.Bar) {
        self.onStop = onStop
        self.onCancel = onCancel
        self.onMute = onMute
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

    func setMuted(_ muted: Bool) {
        mutedShown.append(muted)
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

    /// The panel's mute button. The real button is disabled with Stop; the controller ignores a
    /// press once the recording is ending all the same.
    func pressMute() {
        onMute?()
    }
}

/// The controller's world on two `FakeScrollClock`s, the continuous one and the one that stops
/// while the Mac sleeps: a date the test sets, free space, the listed windows, the card and cover
/// windows, the file's facts, and which microphones are lost. It logs every file access and each
/// activity's begin and end, and has its own `NotificationCenter` for the workspace.
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
    /// What the recording's mute log writer was given to write.
    let muteLogWrites = MuteLogWrites()
    /// The mute log URL of each writer made, in order.
    private(set) var muteLogWritersMade: [URL] = []
    /// Each removal, with how many mute log writes had landed by then.
    private(set) var removals: [Removal] = []
    /// `microphoneLossReason`'s answers, by device ID; nil for any other.
    var microphoneLossReasons: [String: String] = [:]
    /// The device IDs `microphoneLossReason` was asked about, in order.
    private(set) var microphoneLossQueries: [String] = []
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
            removeFiles: { [unowned self] urls in
                removals.append(Removal(urls: urls, writesLanded: muteLogWrites.logs.count))
                log.append("remove")
            },
            workspaceCenter: center,
            microphoneLossReason: { [unowned self] id in
                microphoneLossQueries.append(id)
                return microphoneLossReasons[id]
            },
            makeMuteLogWriter: { [unowned self] url in
                muteLogWritersMade.append(url)
                return MuteLogWriter(url: url, write: muteLogWrites.write)
            })
    }

    /// One removal's files, in the order given, and how many of the mute log writer's writes had
    /// landed when it was asked for.
    struct Removal: Equatable {
        var urls: [URL]
        var writesLanded: Int
    }

    /// The files removed, in order.
    var removedURLs: [URL] {
        removals.flatMap(\.urls)
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

/// A `MuteLogWriter`'s write for tests. It records each log it writes, in order, from the writer's
/// consumer off the main actor, and can hold each write until the test releases it, slow each by
/// `delay`, fail the next few, and also write to disk.
nonisolated final class MuteLogWrites: Sendable {
    private struct State {
        var logs: [MuteLog] = []
        var ended = 0
        var holds = false
        var failures = 0
    }

    struct Failed: Error {}

    /// Each write first sleeps this long, as a slow disk would.
    let delay: TimeInterval
    /// Whether a write also writes the log to its URL (`MuteLog.write`).
    let writesToDisk: Bool
    private let state = Mutex(State())
    private let gate = DispatchSemaphore(value: 0)

    init(delay: TimeInterval = 0, writesToDisk: Bool = false) {
        self.delay = delay
        self.writesToDisk = writesToDisk
    }

    /// The logs written, in order. A failed write is not among them.
    var logs: [MuteLog] {
        state.withLock { $0.logs }
    }

    /// The writes that have returned or thrown.
    var ended: Int {
        state.withLock { $0.ended }
    }

    /// From now on, each write waits until `releaseWrites()`, for at most 10 s, so a test that
    /// never releases fails instead of hanging.
    func holdWrites() {
        state.withLock { $0.holds = true }
    }

    func releaseWrites() {
        state.withLock { $0.holds = false }
        gate.signal()
    }

    /// The next `count` writes throw.
    func failNext(_ count: Int) {
        state.withLock { $0.failures = count }
    }

    /// The write a `MuteLogWriter` is given.
    func write(_ log: MuteLog, to url: URL) throws {
        if state.withLock({ $0.holds }) {
            _ = gate.wait(timeout: .now() + 10)
        }
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        defer { state.withLock { $0.ended += 1 } }
        let fails = state.withLock { state in
            guard state.failures > 0 else { return false }
            state.failures -= 1
            return true
        }
        if fails { throw Failed() }
        if writesToDisk {
            try MuteLog.write(log, to: url)
        }
        state.withLock { $0.logs.append(log) }
    }

    /// Waits in real time, up to 2 s, until `count` writes have returned or thrown.
    func waitForWrites(_ count: Int) async {
        for _ in 0..<2_000 where ended < count {
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(ended >= count, "waited for \(count) mute log writes")
    }
}

/// Audio inputs and an access the tests set. `requestAccess` answers with `grants`, and the
/// access is then what the prompt answered.
final class FakeMicrophoneDevices: MicrophoneDevices {
    var devices: [MicrophoneDevice]
    var defaultInput: MicrophoneDevice?
    var currentAccess: MicrophoneAccess
    var grants: Bool
    private(set) var requestCount = 0

    init(devices: [MicrophoneDevice] = [], defaultInput: MicrophoneDevice? = nil,
         access: MicrophoneAccess = .authorized, grants: Bool = true) {
        self.devices = devices
        self.defaultInput = defaultInput
        self.currentAccess = access
        self.grants = grants
    }

    func list() -> [MicrophoneDevice] { devices }
    func defaultDevice() -> MicrophoneDevice? { defaultInput }
    func access() -> MicrophoneAccess { currentAccess }

    func requestAccess() async -> Bool {
        requestCount += 1
        currentAccess = grants ? .authorized : .denied
        return grants
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
