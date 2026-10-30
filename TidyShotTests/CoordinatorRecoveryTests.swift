import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import TidyShot

/// The `pending/` launch step on a built coordinator (harness design 4.2): an orphan is adopted with a
/// record kept until the user acts, never deleted, unless it is empty or cannot be read; only the listed
/// files are considered, and a record added since the listing keeps its file.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorRecoveryTests {
    let world: CoordinatorWorld

    init() throws {
        world = try CoordinatorWorld()
    }

    func pendingURL(_ coordinator: AppCoordinator, _ id: UUID, _ ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: coordinator.pendingFiles.directory, withIntermediateDirectories: true)
        return coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).\(ext)")
    }

    /// A two-frame GIF of 8 by 6 pixels, each frame shown for half a second.
    func writeGIF(at url: URL) throws {
        let frame = try CoordinatorWorld.image(width: 8, height: 6)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                       2, nil))
        let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary
        CGImageDestinationAddImage(destination, frame, properties)
        CGImageDestinationAddImage(destination, frame, properties)
        #expect(CGImageDestinationFinalize(destination))
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Harness design 4.2 (a `.png`) and 4.3: an orphan PNG gets a record of its pixel size and byte count,
    /// kept until the user acts, with a thumbnail, `Recovery: <name> recovered` and `Recovered a capture`.
    @Test func anOrphanPNGIsAdoptedWithItsSizeAThumbnailAndANotice() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let png = try CoordinatorWorld.pngData(width: 40, height: 30)
        let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")

        await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

        let record = try #require(coordinator.history.record(id: id))
        #expect(record.mediaKind == .image)
        #expect(record.pixelWidth == 40)
        #expect(record.pixelHeight == 30)
        #expect(record.byteCount == png.count)
        #expect(record.fileIsTemporary)
        #expect(record.fileURL?.lastPathComponent == url.lastPathComponent)
        #expect(record.uploadState == .none)
        #expect(record.isPendingOnly)
        #expect(world.notifier.calls == [.error(title: "Recovered a capture",
                                                 message: "\(url.lastPathComponent). Find it in Recent Captures.")])
        #expect(world.logLines == ["Recovery: \(url.lastPathComponent) recovered"])
        #expect(world.cards.calls.isEmpty)
        try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != nil }
    }

    /// Harness design 4.2 (a `.mp4`) and 4.3: an orphan MP4 gets a record with its length, and
    /// `Recovered a recording` with `m:ss`.
    @Test func anOrphanMP4IsAdoptedWithItsLength() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let url = try pendingURL(coordinator, id, "mp4")
        try await VideoFixtures.makeMP4(at: url, width: 64, height: 48, seconds: 1, audio: false)

        await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

        let record = try #require(coordinator.history.record(id: id))
        #expect(record.mediaKind == .video)
        #expect(record.pixelWidth == 64)
        #expect(record.pixelHeight == 48)
        let duration = try #require(record.durationSeconds)
        #expect(abs(duration - 1) < 0.1)
        #expect(record.byteCount == FileSizes.byteCount(of: url))
        #expect(world.notifier.calls == [.error(title: "Recovered a recording",
                                                 message: "\(url.lastPathComponent), \(RecordingClock.format(duration)). Find it in Recent Captures.")])
        try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != nil }
    }

    /// Harness design 4.2 (a zero-byte file) and 4.3: removed, with `Recovery: <name> is empty, removed` (D11).
    @Test func aZeroByteFileIsRemoved() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let url = try pendingURL(coordinator, UUID(), "png")
        #expect(FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data()))

        await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

        #expect(!exists(url))
        #expect(coordinator.history.records.isEmpty)
        #expect(world.notifier.calls.isEmpty)
        #expect(world.logLines == ["Recovery: \(url.lastPathComponent) is empty, removed"])
    }

    /// Harness design 4.2 (adopting re-reads the records) and 4.3: a record added between the listing and
    /// the adoption keeps its file.
    @Test func aFileWhoseRecordWasAddedAfterTheListingIsLeftAlone() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let url = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 40, height: 30), id: id, ext: "png")
        let listed = coordinator.pendingFiles.list()
        let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 40, pixelHeight: 30,
                                   appName: nil)
        coordinator.history.add(record)

        await coordinator.adoptPendingFiles(listed)

        #expect(coordinator.history.records == [record])
        #expect(exists(url))
        #expect(world.notifier.calls.isEmpty)
        #expect(world.logLines.isEmpty)
    }

    /// Harness design 4.2 (listing) and 4.3: a file written after the listing is never considered.
    @Test func aFileNotInTheListingIsLeftAlone() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let listed = coordinator.pendingFiles.list()
        let url = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 40, height: 30), id: UUID(),
                                                     ext: "png")

        await coordinator.adoptPendingFiles(listed)

        #expect(coordinator.history.records.isEmpty)
        #expect(exists(url))
        #expect(world.notifier.calls.isEmpty)
    }

    /// Harness design 4.2 (a `.png` that does not decode) and 4.3: removed, with
    /// `Recovery: <name> could not be read, removed`.
    @Test func aFileThatCannotBeReadIsRemovedAndLogged() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let url = try coordinator.pendingFiles.write(Data("not a png".utf8), id: UUID(), ext: "png")

        await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

        #expect(!exists(url))
        #expect(coordinator.history.records.isEmpty)
        #expect(world.notifier.calls.isEmpty)
        #expect(world.logLines == ["Recovery: \(url.lastPathComponent) could not be read, removed"])
    }

    /// Harness design 4.1 and 4.3, Phase 3's objection to a deleting sweep: an empty history (a corrupt
    /// file set aside) must not cost a capture. Every orphan comes back and every file stays.
    @Test func anEmptyHistoryAdoptsEveryOrphanAndDeletesNothing() async throws {
        defer { world.removeAll() }
        let coordinator = world.makeCoordinator()
        let image = UUID()
        let movie = UUID()
        let gif = UUID()
        let imageURL = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 40, height: 30), id: image,
                                                          ext: "png")
        let movieURL = try pendingURL(coordinator, movie, "mp4")
        try await VideoFixtures.makeMP4(at: movieURL, width: 64, height: 48, seconds: 1, audio: false)
        let gifURL = try pendingURL(coordinator, gif, "gif")
        try writeGIF(at: gifURL)

        await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

        #expect(coordinator.history.record(id: image)?.mediaKind == .image)
        #expect(coordinator.history.record(id: movie)?.mediaKind == .video)
        let gifRecord = try #require(coordinator.history.record(id: gif))
        #expect(gifRecord.mediaKind == .gif)
        #expect(gifRecord.pixelWidth == 8)
        #expect(gifRecord.pixelHeight == 6)
        #expect(abs((gifRecord.durationSeconds ?? 0) - 1) < 0.01)
        #expect(exists(imageURL) && exists(movieURL) && exists(gifURL))
        #expect(world.notifier.calls.count == 3)
        #expect(world.logLines.allSatisfy { $0.hasSuffix(" recovered") })
        // The three thumbnails are written on detached tasks; wait for them, so none lands after
        // `removeAll()` and makes the world's folders again.
        try await eventually {
            [image, movie, gif].allSatisfy { coordinator.history.record(id: $0)?.thumbnailFileName != nil }
        }
    }
}
