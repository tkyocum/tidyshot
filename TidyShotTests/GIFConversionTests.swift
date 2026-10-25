import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The conversion step of a GIF recording's save (design, Conversion), with `make`, `save`,
/// `removeFile`, the free space and the quit flag faked.
@Suite(.timeLimit(.minutes(1)))
struct GIFConversionTests {
    /// What the step did, in order: `make`, `save <kind>`, `remove <name>`.
    final class World {
        var events: [String] = []
        var saves: [(recording: Recording, notice: RecordingNotice?, mode: RecordingSaveMode)] = []
        var progress: [GIFProgress] = []
        var freeBytes: Int64? = 100_000_000_000
        var isQuitting = false
        /// What `make` throws, if anything.
        var makeError: (any Error)?
        /// Runs inside `make`, before it returns or throws.
        var duringMake: () -> Void = {}
        /// False for the save that leaves its file in `tmp/Recording` (`.leftInTmp`).
        var saveMakesRecord = true
        let result = GIFResult(pixelWidth: 1280, pixelHeight: 800, outputFrameCount: 151, gifFrameCount: 40,
                               duration: 10.07, byteCount: 2_000_000)
        private(set) var madeFrom: (mp4: URL, gif: URL, settings: GIFSettings)?

        var conversion: GIFConversion {
            GIFConversion(
                freeBytes: { [unowned self] in freeBytes },
                make: { [unowned self] mp4, gif, settings, progress in
                    events.append("make")
                    madeFrom = (mp4, gif, settings)
                    progress(0.5)
                    duringMake()
                    if let makeError { throw makeError }
                    return result
                },
                save: { [unowned self] recording, notice, mode in
                    events.append("save \(recording.mediaKind.rawValue)")
                    saves.append((recording, notice, mode))
                    guard saveMakesRecord else { return nil }
                    return CaptureRecord(id: recording.id, fileURL: recording.fileURL, pixelWidth: recording.pixelWidth,
                                         pixelHeight: recording.pixelHeight, appName: nil, mediaKind: recording.mediaKind)
                },
                removeFile: { [unowned self] url in events.append("remove \(url.lastPathComponent)") },
                isQuitting: { [unowned self] in isQuitting })
        }

        func run(_ mp4: Recording, settings: GIFSettings = GIFSettings(fps: 15, maxSide: 1280)) async {
            await conversion.run(mp4, settings: settings) { [unowned self] in progress.append($0) }
        }
    }

    let world = World()
    let id = UUID()
    let poster = GIFConversionTests.makePoster()

    var mp4: Recording {
        Recording(id: id, fileURL: Recording.fileURL(for: id), startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
                  pixelWidth: 2560, pixelHeight: 1600, duration: 10.05, poster: poster, displayID: 3,
                  gif: GIFSettings(fps: 15, maxSide: 1280))
    }

    var mp4Name: String { "\(id.uuidString).mp4" }
    var gifName: String { "\(id.uuidString).gif" }

    /// The one save's recording, notice and mode.
    func onlySave() throws -> (recording: Recording, notice: RecordingNotice?, mode: RecordingSaveMode) {
        try #require(world.saves.count == 1)
        return world.saves[0]
    }

    func expectSavedAsMP4(_ saved: (recording: Recording, notice: RecordingNotice?, mode: RecordingSaveMode)) {
        #expect(saved.recording.mediaKind == .video)
        #expect(saved.recording.fileURL == Recording.fileURL(for: id))
        #expect(saved.recording.recoveryURL == Recording.fileURL(for: id))
        #expect(saved.recording.duration == 10.05)
    }

    // MARK: Success

    @Test func onSuccessTheGIFIsSavedAndTheMP4RemovedOnlyAfterTheRecordExists() async throws {
        await world.run(mp4)

        #expect(world.events == ["make", "save gif", "remove \(mp4Name)"])
        let saved = try onlySave()
        #expect(saved.notice == nil)
        #expect(saved.mode == .normal)
        let gif = saved.recording
        #expect(gif.id == id)
        #expect(gif.mediaKind == .gif)
        #expect(gif.fileURL == Recording.gifURL(for: id))
        #expect(gif.recoveryURL == Recording.fileURL(for: id))
        #expect(gif.pixelWidth == 1280)
        #expect(gif.pixelHeight == 800)
        #expect(gif.duration == 10.07)
        #expect(gif.poster === poster)
        #expect(gif.startedAt == mp4.startedAt)
        #expect(gif.displayID == 3)
    }

    @Test func makeReadsTheMP4AndWritesTheGIFBesideIt() async throws {
        await world.run(mp4, settings: GIFSettings(fps: 20, maxSide: 0))
        let made = try #require(world.madeFrom)
        #expect(made.mp4 == Recording.fileURL(for: id))
        #expect(made.gif == Recording.gifURL(for: id))
        #expect(made.gif.deletingLastPathComponent() == Recording.directory)
        #expect(made.gif.lastPathComponent == gifName)
        #expect(made.settings == GIFSettings(fps: 20, maxSide: 0))
    }

    /// The fraction goes on with the output frame count, 10.05 s at 15 fps rounded up.
    @Test func progressCarriesTheOutputFrameCount() async {
        await world.run(mp4)
        #expect(world.progress == [GIFProgress(fraction: 0.5, frameCount: 151)])
    }

    /// The GIF stayed in `tmp/Recording`: it goes, and the MP4 stays for the launch check, which
    /// the save's `Not saved to a folder` notice names.
    @Test func whenTheGIFIsLeftInTmpTheGIFIsRemovedAndTheMP4Stays() async throws {
        world.saveMakesRecord = false
        await world.run(mp4)

        #expect(world.events == ["make", "save gif", "remove \(gifName)"])
        let saved = try onlySave()
        let path = saved.recording.recoveryURL.path(percentEncoded: false)
        #expect(path == Recording.fileURL(for: id).path(percentEncoded: false))
        let plan = RecordingSavePlan.make(action: .save, hasDestination: false,
                                          result: .leftInTmp(reason: "No space.", path: path),
                                          copyImage: false, alsoCopyImage: false, quitMode: false)
        guard case .notice(let notice) = plan.notification else {
            Issue.record("no notice")
            return
        }
        #expect(notice.body.contains(mp4Name))
        #expect(!notice.body.contains(gifName))
    }

    // MARK: Failure and Stop

    @Test func onFailureTheMP4IsSavedAsAVideoWithGIFNotMade() async throws {
        world.makeError = GIFMakerError.couldNotWrite
        await world.run(mp4)

        #expect(world.events == ["make", "remove \(gifName)", "save video"])
        let saved = try onlySave()
        expectSavedAsMP4(saved)
        #expect(saved.mode == .normal)
        #expect(saved.notice == RecordingNotice(
            title: "GIF not made", body: "The GIF could not be written. The disk may be full. The recording was saved as an MP4."))
    }

    @Test func stopMakingGIFSavesTheMP4WithStopped() async throws {
        world.makeError = CancellationError()
        await world.run(mp4)

        #expect(world.events == ["make", "remove \(gifName)", "save video"])
        let saved = try onlySave()
        expectSavedAsMP4(saved)
        #expect(saved.mode == .normal)
        #expect(saved.notice == RecordingNotice(title: "GIF not made", body: "Stopped. The recording was saved as an MP4."))
        #expect(saved.notice == GIFConversion.notMade(GIFConversion.stoppedReason))
    }

    // MARK: Quit

    /// A quit before the conversion began: `make` never runs.
    @Test func aQuitBeforeTheConversionSavesTheMP4InQuitMode() async throws {
        world.isQuitting = true
        await world.run(mp4)

        #expect(world.events == ["save video"])
        let saved = try onlySave()
        expectSavedAsMP4(saved)
        #expect(saved.mode == .quit)
        #expect(saved.notice == nil)
    }

    /// A quit during the conversion cancels it.
    @Test func aQuitDuringTheConversionSavesTheMP4InQuitMode() async throws {
        world.duringMake = { [world] in world.isQuitting = true }
        world.makeError = CancellationError()
        await world.run(mp4)

        #expect(world.events == ["make", "remove \(gifName)", "save video"])
        let saved = try onlySave()
        expectSavedAsMP4(saved)
        #expect(saved.mode == .quit)
        #expect(saved.notice == nil)
    }

    // MARK: Disk space

    @Test func underOneGBFreeNeverMakesAndSavesTheMP4() async throws {
        world.freeBytes = 999_999_999
        await world.run(mp4)

        #expect(world.events == ["save video"])
        let saved = try onlySave()
        expectSavedAsMP4(saved)
        #expect(saved.notice == RecordingNotice(
            title: "GIF not made", body: "Not enough disk space to make the GIF. The recording was saved as an MP4."))
    }

    /// An unreadable free space counts as enough, as in R1.
    @Test func unreadableFreeSpaceMakesTheGIF() async {
        world.freeBytes = nil
        await world.run(mp4)
        #expect(world.events == ["make", "save gif", "remove \(mp4Name)"])
    }

    @Test func runningOutOfSpaceMidWriteGivesTheSameNotice() async throws {
        world.makeError = GIFMakerError.notEnoughSpace
        await world.run(mp4)

        #expect(world.events == ["make", "remove \(gifName)", "save video"])
        let saved = try onlySave()
        expectSavedAsMP4(saved)
        #expect(saved.notice == RecordingNotice(
            title: "GIF not made", body: "Not enough disk space to make the GIF. The recording was saved as an MP4."))
    }

    // MARK: The invariant

    /// Every path from the recorder's `.keep` saves exactly once.
    @Test(arguments: ["success", "leftInTmp", "failure", "stop", "quit before", "quit during", "no space", "space mid-write"])
    func everyPathSavesExactlyOnce(_ path: String) async {
        switch path {
        case "leftInTmp": world.saveMakesRecord = false
        case "failure": world.makeError = GIFMakerError.couldNotWrite
        case "stop": world.makeError = CancellationError()
        case "quit before": world.isQuitting = true
        case "quit during":
            world.duringMake = { [world] in world.isQuitting = true }
            world.makeError = CancellationError()
        case "no space": world.freeBytes = 0
        case "space mid-write": world.makeError = GIFMakerError.notEnoughSpace
        default: break
        }
        await world.run(mp4)
        #expect(world.saves.count == 1)
        #expect(world.events.count { $0.hasPrefix("save") } == 1)
    }

    @Test func theNoticeTextIsTheDesigns() {
        #expect(GIFConversion.notMade("Something failed.")
                == RecordingNotice(title: "GIF not made", body: "Something failed. The recording was saved as an MP4."))
        #expect(GIFConversion.stoppedReason == "Stopped.")
    }

    private static func makePoster() -> CGImage {
        let context = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }
}
