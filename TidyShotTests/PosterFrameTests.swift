import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The poster frame: the first frame, at most 800 px on the longer side, never enlarged.
@Suite(.timeLimit(.minutes(1)))
struct PosterFrameTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @Test func aSmallVideoKeepsItsSize() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "small.mp4")
        try await VideoFixtures.makeMP4(at: url, width: 640, height: 400, seconds: 0.5, audio: false)

        let poster = try #require(await PosterFrame.image(of: url))
        #expect(poster.width == 640)
        #expect(poster.height == 400)
    }

    @Test func aLargeVideoIsScaledToEightHundredOnItsLongerSide() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "large.mp4")
        try await VideoFixtures.makeMP4(at: url, width: 1600, height: 1000, seconds: 0.5, audio: false)

        let poster = try #require(await PosterFrame.image(of: url))
        #expect(poster.width == 800)
        #expect(poster.height == 500)
        #expect(PosterFrame.maxSide == 800)
    }

    @Test func anUnreadableFileHasNoPoster() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "garbage.mp4")
        try VideoFixtures.makeGarbage(at: url)

        #expect(await PosterFrame.image(of: url) == nil)
        #expect(await PosterFrame.image(of: dir.appending(path: "missing.mp4")) == nil)
    }
}
