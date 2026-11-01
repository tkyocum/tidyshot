import AppKit
import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// The coordinator's notifier in the suite: every call as a value, in order (harness design 2.4).
final class FakeNotifier: Notifying {
    enum Call: Equatable {
        case setUp
        case saved(title: String, file: String)
        case uploaded(url: URL, copied: Bool)
        case error(title: String, message: String, subtitle: String? = nil)
        case notice(title: String, body: String, subtitle: String? = nil)
        case held
        case released
        case waited(Duration)
    }

    private(set) var calls: [Call] = []

    /// The `notifyError` calls, in order.
    var errors: [(title: String, message: String)] {
        calls.compactMap { call -> (title: String, message: String)? in
            guard case .error(let title, let message, _) = call else { return nil }
            return (title, message)
        }
    }

    func setUp() { calls.append(.setUp) }

    func notifySaved(fileURL: URL, title: String) {
        calls.append(.saved(title: title, file: fileURL.lastPathComponent))
    }

    func notifyUploaded(url: URL, copied: Bool) { calls.append(.uploaded(url: url, copied: copied)) }

    func notifyError(_ message: String, title: String, subtitle: String?, revealing fileURL: URL?) {
        calls.append(.error(title: title, message: message, subtitle: subtitle))
    }

    func notify(title: String, body: String, subtitle: String?, openURL: URL?) {
        calls.append(.notice(title: title, body: body, subtitle: subtitle))
    }

    func holdNotices() { calls.append(.held) }

    func releaseHeldNotices() -> Int {
        calls.append(.released)
        return 0
    }

    /// Runs at each `waitForReleasedNotices`, before it returns, so a test can read the coordinator's
    /// state at the moment of the wait (test 56).
    var onWait: (() -> Void)?

    func waitForReleasedNotices(upTo limit: Duration) async {
        calls.append(.waited(limit))
        onWait?()
    }
}

/// The card stack in the suite: what the coordinator told it, in order, and the records a test
/// says are showing. No card is ever made. A close of a showing record reports it, as the real
/// stack does.
final class FakeCards: QuickAccessCards {
    enum Call: Equatable {
        case show(UUID)
        case update(UUID, CaptureRecord.UploadState)
        case optimizing(UUID, Bool)
        case downloading(UUID, DragDownloadStatus?)
        case linkWasCopied(UUID, Bool)
        case trimState(UUID)
        case thumbnail(UUID)
        case dragFile(UUID, URL?)
        case close(UUID, QuickAccessCloseReason)
    }

    /// A card's download status as set, with nil as `.cleared`.
    enum DownloadShown: Equatable {
        case running(Double)
        case failed(String)
        case cleared
    }

    private(set) var calls: [Call] = []
    /// The records whose card shows.
    var showing: Set<UUID> = []
    var onDidClose: ((UUID, QuickAccessCloseReason) -> Void)?

    var windowNumbers: Set<CGWindowID> { [] }
    var shownIDs: [UUID] { Array(showing) }
    var screen: NSScreen? { nil }

    func isShowing(recordID: UUID) -> Bool { showing.contains(recordID) }

    func show(record: CaptureRecord, thumbnail: NSImage?, screen: NSScreen, autoCloseSeconds: Double,
              actions: QuickAccessController.Actions) {
        showing.insert(record.id)
        calls.append(.show(record.id))
    }

    func update(record: CaptureRecord) { calls.append(.update(record.id, record.uploadState)) }
    func setOptimizing(_ isOptimizing: Bool, for recordID: UUID) { calls.append(.optimizing(recordID, isOptimizing)) }
    func setDownloading(_ status: DragDownloadStatus?, for recordID: UUID) { calls.append(.downloading(recordID, status)) }
    func setLinkWasCopied(_ linkWasCopied: Bool, for recordID: UUID) { calls.append(.linkWasCopied(recordID, linkWasCopied)) }
    func setTrimState(_ trimState: RecordingTrim.MenuState, for recordID: UUID) { calls.append(.trimState(recordID)) }
    func setThumbnail(_ thumbnail: NSImage?, for recordID: UUID) { calls.append(.thumbnail(recordID)) }
    func setDragFile(_ url: URL?, for recordID: UUID) { calls.append(.dragFile(recordID, url)) }

    func close(recordID: UUID, reason: QuickAccessCloseReason) {
        calls.append(.close(recordID, reason))
        guard showing.remove(recordID) != nil else { return }
        onDidClose?(recordID, reason)
    }

    /// The download statuses set for `id`, in order.
    func downloads(for id: UUID) -> [DownloadShown] {
        calls.compactMap { call -> DownloadShown? in
            guard case .downloading(let callID, let status) = call, callID == id else { return nil }
            switch status {
            case .some(.running(let fraction)): return .running(fraction)
            case .some(.failed(let message)): return .failed(message)
            case .none: return .cleared
            }
        }
    }

    /// The drag files handed to `id`'s card, in order.
    func dragFiles(for id: UUID) -> [URL?] {
        calls.compactMap { call -> URL?? in
            guard case .dragFile(let callID, let url) = call, callID == id else { return nil }
            return .some(url)
        }
    }

    /// The upload states pushed to `id`'s card, in order.
    func updates(for id: UUID) -> [CaptureRecord.UploadState] {
        calls.compactMap { call -> CaptureRecord.UploadState? in
            guard case .update(let callID, let state) = call, callID == id else { return nil }
            return state
        }
    }

    /// Every close, in order.
    var closes: [QuickAccessCloseReason] {
        calls.compactMap { call -> QuickAccessCloseReason? in
            guard case .close(_, let reason) = call else { return nil }
            return reason
        }
    }
}

/// The pasteboard in the suite: what was put there, in order. Every write moves `changeCount`, as
/// the pasteboard's does, and a test moves it to stand for a copy made elsewhere.
final class FakeClipboard: Clipboard {
    enum Copy: Equatable {
        case image
        case pngAndTIFF
        case tiff
        case fileURL(URL)
        case url(URL)
        case annotationClip(Data)
        case string(String)
    }

    private(set) var copies: [Copy] = []
    /// The PNG of every `.image` and `.pngAndTIFF` copy, in order (what Preview's New from Clipboard reads).
    private(set) var pngs: [Data] = []
    var changeCount = 0
    var annotationClip: Data?

    func setString(_ string: String) { write(.string(string)) }
    func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int { pngs.append(pngData); return write(.image) }
    func copy(pngData: Data, tiffData: Data?) -> Int { pngs.append(pngData); return write(.pngAndTIFF) }
    func copy(tiffData: Data?) -> Int { write(.tiff) }
    func copy(fileURL: URL) -> Int { write(.fileURL(fileURL)) }
    func copy(url: URL) -> Int { write(.url(url)) }

    func copy(annotationClip data: Data) -> Int {
        annotationClip = data
        return write(.annotationClip(data))
    }

    func annotationClipData() -> Data? { annotationClip }
    var hasAnnotationClip: Bool { annotationClip != nil }

    @discardableResult
    private func write(_ copy: Copy) -> Int {
        copies.append(copy)
        changeCount += 1
        return changeCount
    }
}

/// Delete's alerts in the suite: each question, in order, answered from `answers` (Yes when they
/// run out), or held until `answer(_:)` while `holds` is set. A held question whose task is
/// cancelled is answered Cancel, so a suite's time limit can end it. A second question while one
/// is held is a fault in the code under test: it is recorded as an issue and answered Cancel at
/// once, so the test fails instead of hanging.
final class FakeConfirm {
    private(set) var asked: [DeleteConfirmation] = []
    var answers: [Bool] = []
    var holds = false
    private let held = SingleWaiter(cancelled: false,
                                    secondEntry: "FakeConfirm was asked again while a question was held")

    var isWaiting: Bool { held.isWaiting }

    func confirm(_ question: DeleteConfirmation) async -> Bool {
        asked.append(question)
        guard holds else { return answers.isEmpty ? true : answers.removeFirst() }
        return await held.wait()
    }

    /// Answers the held question; later ones come from `answers`.
    func answer(_ yes: Bool) {
        holds = false
        held.resume(yes)
    }
}

/// A card's Save As… panel in the suite (`environment.chooseSaveAsURL`): no panel is built and the app
/// is never activated. Every suggestion is kept, in order; each is answered from `answers` (a URL, or
/// nil for Cancel; Cancel when they run out), or held until `answer(_:)` while `holds` is set. A held
/// panel whose task is cancelled answers Cancel; a second panel while one is held records an issue.
final class FakeSaveAsChooser {
    private(set) var asked: [EditorNaming.SaveAsSuggestion] = []
    var answers: [URL?] = []
    var holds = false
    private let held = SingleWaiter<URL?>(cancelled: nil,
                                          secondEntry: "FakeSaveAsChooser was asked again while a panel was held")

    var isWaiting: Bool { held.isWaiting }

    func choose(_ suggestion: EditorNaming.SaveAsSuggestion) async -> URL? {
        asked.append(suggestion)
        guard holds else { return answers.isEmpty ? nil : answers.removeFirst() }
        return await held.wait()
    }

    /// Answers the held panel (nil: Cancel); later ones come from `answers`.
    func answer(_ url: URL?) {
        holds = false
        held.resume(url)
    }
}

/// `environment.makeDestination` in the suite: a `FakeDestination` per location, `standard` for the
/// rest, and every configuration asked for. Called off the main actor, so it is locked.
nonisolated final class FakeDestinationFactory: Sendable {
    private struct State {
        var byLocation: [ObjectLocation: FakeDestination] = [:]
        var asked: [S3DestinationConfig] = []
    }

    /// The destination of any location without its own, the world's Upload settings' among them.
    let standard = FakeDestination()
    private let state = Mutex(State())

    /// Hands out `destination` for every configuration that writes to `location`.
    func add(_ destination: FakeDestination, at location: ObjectLocation) {
        state.withLock { $0.byLocation[location] = destination }
    }

    /// The configurations asked for, in order.
    var askedConfigs: [S3DestinationConfig] { state.withLock { $0.asked } }
    var askedLocations: [ObjectLocation] { askedConfigs.map { ObjectLocation(config: $0) } }

    func make(_ config: S3DestinationConfig, _ credentials: AWSCredentials) -> any Destination {
        let location = ObjectLocation(config: config)
        let found = state.withLock { state -> FakeDestination? in
            state.asked.append(config)
            return state.byLocation[location]
        }
        return found ?? standard
    }
}

/// The world's values that the coordinator's `@Sendable` closures read and write: the date, the
/// free space and the two logs. Locked, as a closure may run off the main actor.
nonisolated final class CoordinatorWorldState: Sendable {
    private struct Values {
        var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var freeBytes: Int64? = 100_000_000_000
        var freeBytesAsked: [URL] = []
        var lines: [String] = []
        var recordingLines: [String] = []
    }

    private let values = Mutex(Values())

    var date: Date {
        get { values.withLock { $0.date } }
        set { values.withLock { $0.date = newValue } }
    }

    var freeBytes: Int64? {
        get { values.withLock { $0.freeBytes } }
        set { values.withLock { $0.freeBytes = newValue } }
    }

    var freeBytesAsked: [URL] { values.withLock { $0.freeBytesAsked } }
    var lines: [String] { values.withLock { $0.lines } }
    var recordingLines: [String] { values.withLock { $0.recordingLines } }

    func freeBytes(at url: URL) -> Int64? {
        values.withLock { values in
            values.freeBytesAsked.append(url)
            return values.freeBytes
        }
    }

    func append(_ line: String) {
        values.withLock { $0.lines.append(line) }
    }

    func appendRecording(_ line: String) {
        values.withLock { $0.recordingLines.append(line) }
    }
}

nonisolated struct CredentialReadFailed: LocalizedError {
    var errorDescription: String? { "The keychain is locked." }
}

/// A credential store whose every read fails, as a locked or denied Keychain does.
final class ThrowingCredentialStore: CredentialStore {
    func load(account: String) throws -> AWSCredentials? { throw CredentialReadFailed() }
    func save(_ credentials: AWSCredentials, account: String) throws { throw CredentialReadFailed() }
    func delete(account: String) throws { throw CredentialReadFailed() }
}

/// Cameras whose access prompt stays open until `answer(_:)`, so a test can look while it is up. A
/// prompt whose task is cancelled ends as refused, so a suite's time limit can end it. A second
/// prompt while one is open is recorded as an issue and refused at once, so a regression fails the
/// test instead of hanging it.
final class HeldCameraDevices: CameraDevices {
    var currentAccess = CameraAccess.notDetermined
    private(set) var requestCount = 0
    private let prompt = SingleWaiter(cancelled: false,
                                      secondEntry: "HeldCameraDevices was asked again while its prompt was open")

    var isAsking: Bool { prompt.isWaiting }

    func list() -> [CameraDevice] { [] }
    func preferred() -> CameraDevice? { nil }
    func access() -> CameraAccess { currentAccess }

    func requestAccess() async -> Bool {
        requestCount += 1
        return await prompt.wait()
    }

    func answer(_ granted: Bool) {
        currentAccess = granted ? .authorized : .denied
        prompt.resume(granted)
    }
}

/// Microphones whose access prompt stays open until `answer(_:)`, as `HeldCameraDevices` does for the
/// camera. A prompt whose task is cancelled ends as refused, and a second prompt while one is open is
/// recorded as an issue and refused at once.
final class HeldMicrophoneDevices: MicrophoneDevices {
    var currentAccess = MicrophoneAccess.notDetermined
    private(set) var requestCount = 0
    private let prompt = SingleWaiter(cancelled: false,
                                      secondEntry: "HeldMicrophoneDevices was asked again while its prompt was open")

    var isAsking: Bool { prompt.isWaiting }

    func list() -> [MicrophoneDevice] { [] }
    func defaultDevice() -> MicrophoneDevice? { nil }
    func access() -> MicrophoneAccess { currentAccess }

    func requestAccess() async -> Bool {
        requestCount += 1
        return await prompt.wait()
    }

    func answer(_ granted: Bool) {
        currentAccess = granted ? .authorized : .denied
        prompt.resume(granted)
    }
}

/// A wait a test opens by hand, for a body held inside the capture lock. A wait whose task is
/// cancelled ends, so a suite's time limit can end it. A second wait while one is open is recorded
/// as an issue and ends at once.
final class TestGate {
    private let gate = SingleWaiter(cancelled: (),
                                    secondEntry: "TestGate was entered again while a wait was open")

    var isWaiting: Bool { gate.isWaiting }

    func wait() async {
        await gate.wait()
    }

    func open() {
        gate.resume(())
    }
}

/// The one wait the held fakes share. `wait()` holds until `resume(_:)`; a wait whose task is
/// cancelled ends with `cancelled`, so a suite's time limit can end it. A second wait while one is
/// held is a fault in the code under test: it records `secondEntry` as an issue and returns
/// `cancelled` at once, so the test fails instead of hanging.
final class SingleWaiter<Value: Sendable> {
    private let cancelled: Value
    private let secondEntry: String
    private var waiter: (id: Int, continuation: CheckedContinuation<Value, Never>)?
    private var nextID = 0

    init(cancelled: Value, secondEntry: String) {
        self.cancelled = cancelled
        self.secondEntry = secondEntry
    }

    var isWaiting: Bool { waiter != nil }

    func wait() async -> Value {
        guard waiter == nil else {
            Issue.record(Comment(rawValue: secondEntry))
            return cancelled
        }
        guard !Task.isCancelled else { return cancelled }
        let id = nextID
        nextID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiter = (id, $0) }
        } onCancel: {
            Task { @MainActor in self.resume(self.cancelled, id: id) }
        }
    }

    /// Ends the held wait with `value`, if one is held.
    func resume(_ value: Value) {
        resume(value, id: nil)
    }

    /// Ends the held wait: any one when `id` is nil, otherwise only the one it names.
    private func resume(_ value: Value, id: Int?) {
        guard let waiter, id == nil || waiter.id == id else { return }
        self.waiter = nil
        waiter.continuation.resume(returning: value)
    }
}

/// Whether a task the test started has returned, read without waiting for it. A test gates on
/// `hasReturned` with `eventually`, so a regression that would hold the task for ever fails the test
/// in two seconds; awaiting the task itself would hang the run, since a suite's time limit cancels
/// the test's task and not one it started.
final class TaskWatch {
    private(set) var hasReturned = false

    init<Success: Sendable>(_ task: Task<Success, Never>) {
        Task { [weak self] in
            _ = await task.value
            self?.hasReturned = true
        }
    }
}
