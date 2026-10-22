import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

@Suite(.timeLimit(.minutes(1)))
struct VideoValidationTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @Test func movieWithAudioReadsItsFacts() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "audio.mp4")
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: 2, audio: true)

        let facts = await VideoValidation.inspect(url)
        #expect(facts.isPlayable)
        #expect(abs(facts.duration - 2) <= 0.1)
        #expect(facts.naturalSize == CGSize(width: 320, height: 200))
        #expect(facts.videoTracks == 1)
        #expect(facts.audioTracks == 1)
        #expect(facts.byteCount > 0)
        #expect(facts.meetsMinimum)
    }

    @Test func movieWithoutAudioHasNoAudioTrack() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "silent.mp4")
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: 2, audio: false)

        let facts = await VideoValidation.inspect(url)
        #expect(facts.isPlayable)
        #expect(facts.videoTracks == 1)
        #expect(facts.audioTracks == 0)
        #expect(facts.meetsMinimum)
    }

    @Test func garbageIsNotPlayable() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "garbage.mp4")
        try VideoFixtures.makeGarbage(at: url)

        let facts = await VideoValidation.inspect(url)
        #expect(!facts.isPlayable)
        #expect(facts.videoTracks == 0)
        #expect(facts.audioTracks == 0)
        #expect(facts.naturalSize == nil)
        #expect(facts.byteCount > 0)
        #expect(!facts.meetsMinimum)
    }

    @Test func missingFileIsNotPlayable() async {
        defer { try? FileManager.default.removeItem(at: dir) }
        let facts = await VideoValidation.inspect(dir.appending(path: "missing.mp4"))
        #expect(!facts.isPlayable)
        #expect(facts.videoTracks == 0)
        #expect(facts.audioTracks == 0)
        #expect(facts.byteCount == 0)
        #expect(!facts.meetsMinimum)
    }

    @Test func shortMovieIsPlayableButTooShort() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "short.mp4")
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: 0.3, audio: false)

        let facts = await VideoValidation.inspect(url)
        #expect(facts.isPlayable)
        #expect(facts.videoTracks == 1)
        #expect(facts.duration < RecordingLimits.minimumDuration)
        #expect(!facts.meetsMinimum)
    }
}
