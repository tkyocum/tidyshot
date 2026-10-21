import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
@testable import TidyShot

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
        let optimiser = ClopOptimiser(workDirectory: directory) { url in
            seen.urls.withLock { $0.append(url) }
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
        let optimiser = ClopOptimiser(workDirectory: blocker.appending(path: "Clop")) { _ in
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
