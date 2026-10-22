import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
@testable import TidyShot

@Suite(.timeLimit(.minutes(1)))
struct ClopOptimiserTests {
    /// Deterministic pseudo-noise so the PNG is large; flat colour when `noisy` is false so it is small.
    static func png(width: Int, height: Int, noisy: Bool, scale: CGFloat = 2) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if noisy {
            var state: UInt32 = 12345
            let buffer = context.data!.assumingMemoryBound(to: UInt8.self)
            for index in 0..<(width * height * 4) {
                state = state &* 1_664_525 &+ 1_013_904_223
                buffer[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: state >> 24)
            }
        } else {
            context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return try ImageEncoder.pngData(from: context.makeImage()!, scale: scale)
    }

    /// Records what the fake transport saw.
    final class Seen: Sendable {
        let urls = Mutex<[URL]>([])
        let data = Mutex<[Data]>([])
        let timeouts = Mutex<[TimeInterval]>([])
    }

    func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ClopOptimiserTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    func leftovers(in directory: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
    }

    /// Runs `optimisedPNG` with `behave` as the fake Clop: it gets the sent file's URL and may rewrite it.
    func run(_ input: Data, seen: Seen = Seen(), behave: @escaping @Sendable (URL) throws -> ClopResponse)
        async -> (outcome: ClopOutcome, directory: URL) {
        let directory = makeDirectory()
        let optimiser = ClopOptimiser(workDirectory: directory) { url, timeout in
            seen.urls.withLock { $0.append(url) }
            seen.timeouts.withLock { $0.append(timeout) }
            seen.data.withLock { $0.append((try? Data(contentsOf: url)) ?? Data()) }
            return try behave(url)
        }
        let outcome = await optimiser.optimisedPNG(input)
        return (outcome, directory)
    }

    nonisolated static func response(for url: URL, old: Int, new: Int, path: String? = nil, convertedFrom: String? = nil) -> ClopResponse {
        ClopResponse(path: path ?? url.path(percentEncoded: false), forURL: url, convertedFrom: convertedFrom,
                     oldBytes: old, newBytes: new)
    }

    // MARK: Success

    @Test func smallerValidPNGAtTheSamePathIsReturned() async throws {
        let input = try Self.png(width: 64, height: 48, noisy: true)
        let smaller = try Self.png(width: 64, height: 48, noisy: false)
        #expect(smaller.count < input.count)

        let (outcome, directory) = await run(input) { url in
            try smaller.write(to: url)
            return Self.response(for: url, old: input.count, new: smaller.count)
        }

        #expect(outcome == .optimised(smaller, oldBytes: input.count, newBytes: smaller.count))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func theTransportSeesAPNGFileHoldingExactlyTheInputBytes() async throws {
        let input = try Self.png(width: 32, height: 32, noisy: true)
        let seen = Seen()

        let (_, usedDirectory) = await run(input, seen: seen) { url in Self.response(for: url, old: 10, new: 10) }

        let urls = seen.urls.withLock { $0 }
        #expect(urls.count == 1)
        #expect(urls[0].pathExtension == "png")
        #expect(urls[0].deletingLastPathComponent().standardizedFileURL == usedDirectory.standardizedFileURL)
        #expect(seen.data.withLock { $0 } == [input])
    }

    // MARK: Fallbacks

    @Test func concurrentRequestsNeverRunTheirTransportsAtTheSameTime() async throws {
        let input = try Self.png(width: 64, height: 64, noisy: false)
        let active = Mutex(0)
        let overlapped = Mutex(false)
        let calls = Mutex(0)
        let directory = makeDirectory()
        let optimiser = ClopOptimiser(workDirectory: directory) { url, _ in
            let wasActive = active.withLock { value -> Int in value += 1; return value }
            if wasActive > 1 { overlapped.withLock { $0 = true } }
            calls.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.15)
            active.withLock { $0 -= 1 }
            return Self.response(for: url, old: 10, new: 10)
        }
        async let first = optimiser.optimisedPNG(input)
        async let second = optimiser.optimisedPNG(input)
        _ = await (first, second)
        #expect(calls.withLock { $0 } == 2)
        #expect(!overlapped.withLock { $0 })
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func throwingTransportReturnsFailed() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        let (outcome, directory) = await run(input) { _ in throw ClopClientError.sendFailed(-2) }

        guard case .original(.failed(let message)) = outcome else {
            Issue.record("expected .original(.failed), got \(outcome)")
            return
        }
        #expect(!message.isEmpty)
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func notSmallerReportedByClopReturnsNotSmaller() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        for (old, new) in [(1000, 1000), (1000, 1200)] {
            let (outcome, directory) = await run(input) { url in Self.response(for: url, old: old, new: new) }
            #expect(outcome == .original(.notSmaller))
            #expect(leftovers(in: directory).isEmpty)
        }
    }

    @Test func aResultFileThatIsNotSmallerThanTheInputReturnsNotSmaller() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: false)
        let bigger = try Self.png(width: 16, height: 16, noisy: true)
        let (outcome, directory) = await run(input) { url in
            try bigger.write(to: url)
            return Self.response(for: url, old: 100, new: 50)
        }
        #expect(outcome == .original(.notSmaller))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func anotherPathReturnsConverted() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        let (outcome, directory) = await run(input) { url in
            let converted = url.deletingPathExtension().appendingPathExtension("jpg")
            return Self.response(for: url, old: 1000, new: 100, path: converted.path(percentEncoded: false))
        }
        #expect(outcome == .original(.converted))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func aConvertedOutputBesideTheWorkFileIsRemoved() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        let converted = Mutex<URL?>(nil)
        let (outcome, directory) = await run(input) { url in
            let jpg = url.deletingPathExtension().appendingPathExtension("jpg")
            try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: jpg)
            converted.withLock { $0 = jpg }
            return Self.response(for: url, old: 1000, new: 100, path: jpg.path(percentEncoded: false), convertedFrom: "image/png")
        }
        let jpg = try #require(converted.withLock { $0 })
        #expect(outcome == .original(.converted))
        #expect(!FileManager.default.fileExists(atPath: jpg.path(percentEncoded: false)))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func convertedFromReturnsConverted() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        let (outcome, directory) = await run(input) { url in
            Self.response(for: url, old: 1000, new: 100, convertedFrom: "image/png")
        }
        #expect(outcome == .original(.converted))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func nonPNGResultBytesReturnInvalidResult() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        let (outcome, directory) = await run(input) { url in
            try Data("not an image".utf8).write(to: url)
            return Self.response(for: url, old: input.count, new: 12)
        }
        #expect(outcome == .original(.invalidResult))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func aJPEGResultReturnsInvalidResult() async throws {
        let input = try Self.png(width: 64, height: 48, noisy: true)
        let jpeg = try Self.jpeg(width: 64, height: 48)
        #expect(jpeg.count < input.count)
        let (outcome, directory) = await run(input) { url in
            try jpeg.write(to: url)
            return Self.response(for: url, old: input.count, new: jpeg.count)
        }
        #expect(outcome == .original(.invalidResult))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func wrongSizeResultReturnsInvalidResult() async throws {
        let input = try Self.png(width: 64, height: 48, noisy: true)
        let smallerButWrongSize = try Self.png(width: 32, height: 24, noisy: false)
        let (outcome, directory) = await run(input) { url in
            try smallerButWrongSize.write(to: url)
            return Self.response(for: url, old: input.count, new: smallerButWrongSize.count)
        }
        #expect(outcome == .original(.invalidResult))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func aMissingResultFileReturnsInvalidResult() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        let (outcome, directory) = await run(input) { url in
            try FileManager.default.removeItem(at: url)
            return Self.response(for: url, old: input.count, new: 10)
        }
        #expect(outcome == .original(.invalidResult))
        #expect(leftovers(in: directory).isEmpty)
    }

    @Test func anUnwritableWorkDirectoryReturnsFailed() async throws {
        let input = try Self.png(width: 16, height: 16, noisy: true)
        let blocker = makeDirectory()
        try Data().write(to: blocker)  // a file where the directory should go
        defer { try? FileManager.default.removeItem(at: blocker) }
        let optimiser = ClopOptimiser(workDirectory: blocker.appending(path: "Clop")) { _, _ in
            Issue.record("transport must not run")
            throw ClopClientError.badReply
        }
        let outcome = await optimiser.optimisedPNG(input)
        guard case .original(.failed) = outcome else {
            Issue.record("expected .original(.failed), got \(outcome)")
            return
        }
    }

    // MARK: DPI survives Clop

    /// Clop drops `pHYs` and keeps `eXIf`; the optimised result must still decode as 2x.
    @Test func exifOnlyResolutionStillDecodesAs2x() async throws {
        let fixture = try ClopClientTests.fixture("exif-only-2x.png")
        #expect(!fixture.contains(Data("pHYs".utf8)))
        let input = try Self.png(width: 64, height: 48, noisy: true)
        #expect(fixture.count < input.count)

        let (outcome, _) = await run(input) { url in
            try fixture.write(to: url)
            return Self.response(for: url, old: input.count, new: fixture.count)
        }

        guard case .optimised(let data, _, _) = outcome else {
            Issue.record("expected .optimised, got \(outcome)")
            return
        }
        let decoded = try #require(ImageEncoder.decode(data))
        #expect(decoded.scale == 2)
        #expect(decoded.image.width == 64)
    }

    // MARK: Video

    /// One video test's folder: the optimiser works in `work`, the movies live in `movies`. The
    /// test removes it when done.
    struct Bench {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "ClopVideoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        var work: URL { base.appending(path: "Clop", directoryHint: .isDirectory) }
        var movies: URL { base.appending(path: "Movies", directoryHint: .isDirectory) }

        func remove() {
            try? FileManager.default.removeItem(at: base)
        }

        /// `<name>.mp4` in `movies`, from `VideoFixtures`.
        func movie(_ name: String, width: Int = 320, height: Int = 200, seconds: Double = 2,
                   audio: Bool = true) async throws -> URL {
            try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
            let url = movies.appending(path: "\(name).mp4", directoryHint: .notDirectory)
            try await VideoFixtures.makeMP4(at: url, width: width, height: height, seconds: seconds, audio: audio)
            return url
        }

        /// The recording Clop gets: a 2 s 320×200 movie padded by 256 KiB, and the same movie
        /// unpadded, which is the smaller result a good Clop writes back.
        func recording(audio: Bool = true) async throws -> (source: URL, smaller: URL) {
            let smaller = try await movie("smaller", audio: audio)
            let source = movies.appending(path: "Recording.mp4", directoryHint: .notDirectory)
            try FileManager.default.copyItem(at: smaller, to: source)
            try ClopOptimiserTests.pad(source, by: 256 * 1024)
            return (source, smaller)
        }

        /// Runs `optimisedVideo` on `source` with `clop` as the fake Clop, which gets the work file
        /// and may rewrite it. Free space reads as unknown unless `freeBytes` says otherwise.
        func optimise(_ source: URL, duration: TimeInterval = 2, seen: Seen = Seen(),
                      freeBytes: @escaping @Sendable (URL) -> Int64? = { _ in nil },
                      clop: @escaping @Sendable (URL) throws -> ClopResponse) async -> ClopVideoOutcome {
            let optimiser = ClopOptimiser(workDirectory: work, transport: { url, timeout in
                seen.urls.withLock { $0.append(url) }
                seen.timeouts.withLock { $0.append(timeout) }
                return try clop(url)
            }, freeBytes: freeBytes)
            return await optimiser.optimisedVideo(at: source, duration: duration, scope: nil)
        }

        var leftovers: [String] {
            (try? FileManager.default.contentsOfDirectory(atPath: work.path(percentEncoded: false))) ?? []
        }
    }

    /// Appends a top-level `free` box, which readers skip: the same movie, `bytes` larger.
    static func pad(_ url: URL, by bytes: Int) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var box = Data()
        withUnsafeBytes(of: UInt32(bytes).bigEndian) { box.append(contentsOf: $0) }
        box.append(contentsOf: Array("free".utf8))
        box.append(Data(count: bytes - 8))
        try handle.write(contentsOf: box)
    }

    /// The fake Clop's rewrite in place: the work file becomes a copy of `result`.
    nonisolated static func replace(_ file: URL, with result: URL) throws {
        try FileManager.default.removeItem(at: file)
        try FileManager.default.copyItem(at: result, to: file)
    }

    static func size(of url: URL) throws -> Int64 {
        Int64(try #require(url.resourceValues(forKeys: [.fileSizeKey]).fileSize))
    }

    @Test func thePaddedRecordingIsTheSameMovieAsTheSmallerOne() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, smaller) = try await bench.recording()
        let padded = await VideoValidation.inspect(source)
        let plain = await VideoValidation.inspect(smaller)
        #expect(padded.isPlayable)
        #expect(padded.duration == plain.duration)
        #expect(padded.naturalSize == plain.naturalSize)
        #expect(padded.audioTracks == 1)
        #expect(padded.byteCount == plain.byteCount + 256 * 1024)
    }

    @Test func aSmallerMovieAtTheWorkFileIsAccepted() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, smaller) = try await bench.recording()
        let seen = Seen()
        let outcome = await bench.optimise(source, seen: seen) { url in
            try Self.replace(url, with: smaller)
            return Self.response(for: url, old: 0, new: 0)
        }

        guard case .optimised(let result, let oldBytes, let newBytes) = outcome else {
            Issue.record("expected .optimised, got \(outcome)")
            return
        }
        #expect(seen.urls.withLock { $0 } == [result])
        #expect(result.deletingLastPathComponent().standardizedFileURL == bench.work.standardizedFileURL)
        #expect(result.pathExtension == "mp4")
        #expect(oldBytes == (try Self.size(of: source)))
        #expect(newBytes == (try Self.size(of: smaller)))
        // The caller owns the result, so it stays.
        #expect(bench.leftovers == [result.lastPathComponent])
    }

    @Test func theWorkCopyIsASeparateFileAndTheRecordingIsUnchanged() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let before = try Data(contentsOf: source)
        let seen = Seen()
        let outcome = await bench.optimise(source, seen: seen) { url in
            #expect(try Data(contentsOf: url) == before)
            try VideoFixtures.makeGarbage(at: url)
            return Self.response(for: url, old: 0, new: 0)
        }

        let sent = try #require(seen.urls.withLock { $0 }.first)
        #expect(sent.standardizedFileURL != source.standardizedFileURL)
        #expect(sent.deletingLastPathComponent().standardizedFileURL == bench.work.standardizedFileURL)
        #expect(sent.pathExtension == "mp4")
        #expect(UUID(uuidString: sent.deletingPathExtension().lastPathComponent) != nil)
        #expect(outcome == .original(.notPlayable))
        #expect(try Data(contentsOf: source) == before)
        #expect(bench.leftovers.isEmpty)
    }

    @Test func aDifferentPathIsRefusedAndTheSiblingRemoved() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, smaller) = try await bench.recording()
        let outcome = await bench.optimise(source) { url in
            let sibling = url.deletingPathExtension().appendingPathExtension("mov")
            try FileManager.default.copyItem(at: smaller, to: sibling)
            return Self.response(for: url, old: 0, new: 0, path: sibling.path(percentEncoded: false))
        }
        #expect(outcome == .original(.converted))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func aConvertedResultIsRefused() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, smaller) = try await bench.recording()
        let outcome = await bench.optimise(source) { url in
            try Self.replace(url, with: smaller)
            return Self.response(for: url, old: 0, new: 0, convertedFrom: "public.mpeg-4")
        }
        #expect(outcome == .original(.converted))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func aResultThatDoesNotPlayIsRefused() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let outcome = await bench.optimise(source) { url in
            try Data(String(repeating: "x", count: 64).utf8).write(to: url)
            return Self.response(for: url, old: 0, new: 0)
        }
        #expect(outcome == .original(.notPlayable))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func aMissingResultIsRefused() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let outcome = await bench.optimise(source) { url in
            try FileManager.default.removeItem(at: url)
            return Self.response(for: url, old: 0, new: 0)
        }
        #expect(outcome == .original(.notPlayable))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func aDifferentSizeIsRefused() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let other = try await bench.movie("other", width: 160, height: 100)
        let outcome = await bench.optimise(source) { url in
            try Self.replace(url, with: other)
            return Self.response(for: url, old: 0, new: 0)
        }
        #expect(outcome == .original(.differentVideo))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func aDurationOffByMoreThanHalfASecondIsRefused() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let longer = try await bench.movie("longer", seconds: 3)
        let outcome = await bench.optimise(source) { url in
            try Self.replace(url, with: longer)
            return Self.response(for: url, old: 0, new: 0)
        }
        #expect(outcome == .original(.durationChanged))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func aDurationWithinHalfASecondIsAccepted() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let longer = try await bench.movie("longer", seconds: 2.3)
        let outcome = await bench.optimise(source) { url in
            try Self.replace(url, with: longer)
            return Self.response(for: url, old: 0, new: 0)
        }
        guard case .optimised = outcome else {
            Issue.record("expected .optimised, got \(outcome)")
            return
        }
        #expect(bench.leftovers.count == 1)
    }

    @Test func aResultThatIsNotSmallerIsRefused() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        // Clop leaves the file as it was.
        let outcome = await bench.optimise(source) { url in Self.response(for: url, old: 100, new: 50) }
        #expect(outcome == .original(.notSmaller))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func droppedAudioIsRefused() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording(audio: true)
        let silent = try await bench.movie("silent", audio: false)
        let outcome = await bench.optimise(source) { url in
            try Self.replace(url, with: silent)
            return Self.response(for: url, old: 0, new: 0)
        }
        #expect(outcome == .original(.lostAudio))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func noAudioOnEitherSideIsAccepted() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, smaller) = try await bench.recording(audio: false)
        let outcome = await bench.optimise(source) { url in
            try Self.replace(url, with: smaller)
            return Self.response(for: url, old: 0, new: 0)
        }
        guard case .optimised(let result, _, _) = outcome else {
            Issue.record("expected .optimised, got \(outcome)")
            return
        }
        #expect(bench.leftovers == [result.lastPathComponent])
    }

    @Test func aFailedRequestUploadsTheOriginal() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let outcome = await bench.optimise(source) { _ in throw ClopClientError.badReply }
        #expect(outcome == .original(.failed("Clop sent an unreadable reply")))
        #expect(bench.leftovers.isEmpty)
    }

    @Test func notEnoughFreeSpaceSkipsClop() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let needed = try Self.size(of: source) + ClopOptimiser.videoHeadroomBytes
        let asked = Mutex<[URL]>([])
        let seen = Seen()
        let outcome = await bench.optimise(source, seen: seen, freeBytes: { url in
            asked.withLock { $0.append(url) }
            return needed - 1
        }) { url in Self.response(for: url, old: 0, new: 0) }

        #expect(outcome == .original(.notEnoughSpace))
        #expect(seen.urls.withLock { $0 }.isEmpty)
        #expect(asked.withLock { $0 } == [bench.work])
        #expect(bench.leftovers.isEmpty)
    }

    @Test func exactlyEnoughFreeSpaceAsksClop() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, smaller) = try await bench.recording()
        let needed = try Self.size(of: source) + ClopOptimiser.videoHeadroomBytes
        let outcome = await bench.optimise(source, freeBytes: { _ in needed }) { url in
            try Self.replace(url, with: smaller)
            return Self.response(for: url, old: 0, new: 0)
        }
        guard case .optimised = outcome else {
            Issue.record("expected .optimised, got \(outcome)")
            return
        }
    }

    @Test func aMissingRecordingNeverReachesClop() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let seen = Seen()
        let outcome = await bench.optimise(bench.movies.appending(path: "gone.mp4"), seen: seen) { url in
            Self.response(for: url, old: 0, new: 0)
        }
        guard case .original(.failed) = outcome else {
            Issue.record("expected .original(.failed), got \(outcome)")
            return
        }
        #expect(seen.urls.withLock { $0 }.isEmpty)
        #expect(bench.leftovers.isEmpty)
    }

    @Test func theTimeoutsComeFromTheKindAndTheDuration() {
        #expect(ClopOptimiser.imageTimeout == 30)
        #expect(ClopOptimiser.videoTimeout(duration: 0) == 60)
        #expect(ClopOptimiser.videoTimeout(duration: 10) == 90)
        #expect(ClopOptimiser.videoTimeout(duration: 300) == 960)
        #expect(ClopOptimiser.videoHeadroomBytes == 1_000_000_000)
    }

    @Test func theTransportReceivesTheTimeout() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let videoSeen = Seen()
        _ = await bench.optimise(source, duration: 12, seen: videoSeen) { url in Self.response(for: url, old: 0, new: 0) }
        #expect(videoSeen.timeouts.withLock { $0 } == [96])

        let imageSeen = Seen()
        _ = await run(try Self.png(width: 16, height: 16, noisy: true), seen: imageSeen) { url in
            Self.response(for: url, old: 10, new: 10)
        }
        #expect(imageSeen.timeouts.withLock { $0 } == [30])
    }

    @Test func aBlockedVideoRequestDoesNotDelayAnImageRequest() async throws {
        let bench = Bench()
        defer { bench.remove() }
        let (source, _) = try await bench.recording()
        let image = try Self.png(width: 16, height: 16, noisy: true)
        let videoWaiting = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let waited = Mutex<DispatchTimeoutResult?>(nil)
        let optimiser = ClopOptimiser(workDirectory: bench.work, transport: { url, _ in
            if url.pathExtension == "mp4" {
                videoWaiting.withLock { $0 = true }
                let result = release.wait(timeout: .now() + 10)
                waited.withLock { $0 = result }
            }
            return Self.response(for: url, old: 10, new: 10)
        }, freeBytes: { _ in nil })

        let video = Task { await optimiser.optimisedVideo(at: source, duration: 2, scope: nil) }
        var polls = 0
        while !videoWaiting.withLock({ $0 }), polls < 2_000 {
            try await Task.sleep(for: .milliseconds(5))
            polls += 1
        }
        #expect(videoWaiting.withLock { $0 })
        // Answered while the video request still waits, so the image did not queue behind it.
        let imageOutcome = await optimiser.optimisedPNG(image)
        release.signal()
        let videoOutcome = await video.value

        #expect(imageOutcome == .original(.notSmaller))
        #expect(waited.withLock { $0 } == .success)
        #expect(videoOutcome == .original(.notSmaller))
        #expect(bench.leftovers.isEmpty)
    }

    static func jpeg(width: Int, height: Int) throws -> Data {
        let png = try Self.png(width: width, height: height, noisy: false)
        let source = CGImageSourceCreateWithData(png as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
