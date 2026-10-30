import AppKit
import Foundation
import Testing
@testable import TidyShot

nonisolated enum CoordinatorWorldError: Error {
    case noDefaults
    case noFile
}

/// A coordinator's world in the suite (harness design 2.4): temp folders, a `UserDefaults` suite named
/// after the test, settings and a save location over it, credentials in memory, the fakes, a clock the
/// test moves, a date it sets, free space it sets, a log it reads and a destination factory. Build it in
/// the suite's `init`, make the coordinator with `makeCoordinator()`, and `defer { world.removeAll() }`
/// first thing in each test. Nothing here reaches the system, except the `ProcessInfo` activity
/// (`Uploading a recording`) the coordinator begins while `fileUploadIDs` is not empty: the design
/// leaves `ProcessInfo` activities out of the environment (2.1, Deferred), and it ends when the set empties.
final class CoordinatorWorld {
    static let config = S3DestinationConfig(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                             bucket: "snap.tky.io", publicURLTemplate: "https://snap.tky.io/{key}")
    static let awsCredentials = AWSCredentials(accessKeyID: "AKIDEXAMPLE",
                                               secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")

    /// `<tmp>/CoordinatorWorld-<uuid>/`.
    let root: URL
    /// `<root>/Support/history.json`; `thumbnails/`, `pending/` and `multipart/` beside it.
    let historyFileURL: URL
    /// `<root>/tmp/`, the coordinator's `Drag/` and partial downloads.
    let temporaryDirectory: URL
    let suiteName: String
    let defaults: UserDefaults
    let settings: AppSettings
    let saveLocation: SaveLocation
    /// `awsCredentials` under the default account.
    let credentials: InMemoryCredentialStore
    /// The coordinator's store: `credentials`, unless a test sets another before `makeCoordinator()`.
    var credentialStore: any CredentialStore
    let notifier = FakeNotifier()
    let cards = FakeCards()
    let clipboard = FakeClipboard()
    let confirm = FakeConfirm()
    /// The coordinator's clock, and its self-timer's.
    let clock = FakeScrollClock()
    let factory = FakeDestinationFactory()
    let state = CoordinatorWorldState()
    /// The lanes' plan; a test sets another before `makeCoordinator()`.
    var multipartPlan = MultipartPlan.standard
    private(set) var shutterCount = 0
    /// The recorder's world, driver and chrome.
    let recording: RecordingTestWorld
    let driver: FakeRecordingDriver
    let chrome: FakeRecordingChrome
    let microphones = FakeMicrophoneDevices()
    /// The coordinator's cameras; a test sets others before `makeCoordinator()`.
    var cameras: any CameraDevices = FakeCameraDevices()

    init() throws {
        let name = Test.current?.name ?? "CoordinatorWorld"
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CoordinatorWorld-\(UUID().uuidString)", directoryHint: .isDirectory)
        let historyFileURL = root.appending(path: "Support", directoryHint: .isDirectory)
            .appending(path: HistoryStore.fileName)
        let temporaryDirectory = root.appending(path: "tmp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: historyFileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        self.root = root
        self.historyFileURL = historyFileURL
        self.temporaryDirectory = temporaryDirectory
        let suiteName = "io.tky.tidyshot.tests.CoordinatorWorld-\(name)-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw CoordinatorWorldError.noDefaults }
        defaults.removePersistentDomain(forName: suiteName)
        self.suiteName = suiteName
        self.defaults = defaults
        settings = AppSettings(defaults: defaults)
        saveLocation = SaveLocation(defaults: defaults)
        let credentials = InMemoryCredentialStore()
        try credentials.save(Self.awsCredentials, account: KeychainCredentialStore.defaultAccount)
        self.credentials = credentials
        credentialStore = credentials
        let recording = RecordingTestWorld()
        self.recording = recording
        driver = FakeRecordingDriver(log: recording.log)
        chrome = FakeRecordingChrome(log: recording.log)
        settings.s3Config = Self.config
    }

    /// Where the world's Upload settings write.
    var location: ObjectLocation { ObjectLocation(config: Self.config) }

    var date: Date {
        get { state.date }
        set { state.date = newValue }
    }

    var freeBytes: Int64? {
        get { state.freeBytes }
        set { state.freeBytes = newValue }
    }

    var freeBytesAsked: [URL] { state.freeBytesAsked }
    var logLines: [String] { state.lines }

    var environment: AppEnvironment {
        let factory = factory
        let state = state
        let confirm = confirm
        return AppEnvironment(
            historyFileURL: historyFileURL,
            temporaryDirectory: temporaryDirectory,
            settings: settings,
            saveLocation: saveLocation,
            credentialStore: credentialStore,
            notifier: notifier,
            overlay: cards,
            clipboard: clipboard,
            makeDestination: { config, credentials in factory.make(config, credentials) },
            multipartPlan: multipartPlan,
            uploadSleep: { _ in },
            freeBytes: { url in state.freeBytes(at: url) },
            confirm: { question in await confirm.confirm(question) },
            playShutter: { [weak self] in self?.shutterCount += 1 },
            now: { state.date },
            clock: clock,
            log: { line in state.append(line) })
    }

    /// A coordinator over this world, with the recorder, the self-timer, the microphones and the
    /// cameras set before anything builds the live ones.
    func makeCoordinator() -> AppCoordinator {
        let coordinator = AppCoordinator(environment: environment)
        let driver = driver
        coordinator.recorder = RecordingController(environment: recording.environment, makeDriver: { driver })
        coordinator.microphones = microphones
        coordinator.cameras = cameras
        coordinator.selfTimer = SelfTimerController(clock: clock)
        return coordinator
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A sparse file of `byteCount` bytes at `url`, its folder made.
    static func writeSparseFile(at url: URL, byteCount: Int64) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
            throw CoordinatorWorldError.noFile
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(byteCount))
        try handle.close()
    }

    /// A red image of `width` by `height` pixels.
    static func image(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// That image as a PNG.
    static func pngData(width: Int, height: Int) throws -> Data {
        try ImageEncoder.pngData(from: image(width: width, height: height), scale: 1)
    }
}
