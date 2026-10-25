import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The launch check of `tmp/Recording` (design, Relaunch after a crash), on a folder of its own
/// with generated movies.
@Suite(.timeLimit(.minutes(1)))
struct RecordingRecoveryTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    @Test func aPlayableFileIsFoundWithItsFacts() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let url = dir.appending(path: "\(id.uuidString).mp4")
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: 2, audio: true)
        let created = try #require(try url.resourceValues(forKeys: [.creationDateKey]).creationDate)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.count == 1)
        let first = try #require(found.first)
        #expect(first.url.lastPathComponent == url.lastPathComponent)
        #expect(first.id == id)
        #expect(first.created == created)
        #expect(first.facts.isPlayable)
        #expect(abs(first.facts.duration - 2) <= 0.1)
        #expect(first.facts.naturalSize == CGSize(width: 320, height: 200))
        #expect(first.facts.videoTracks == 1)
        #expect(first.facts.audioTracks == 1)
        // A found file stays where it is, for the coordinator to move.
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    /// A crash gives no Stop, so a playable file under the end rule's 0.5 s is kept too.
    @Test func aShortPlayableFileIsFound() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "\(UUID().uuidString).mp4")
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: 0.3, audio: false)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.count == 1)
        #expect(found.first?.facts.meetsMinimum == false)
    }

    @Test func garbageIsRemovedAndAPlayableFileBesideItIsFound() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let garbage = dir.appending(path: "\(UUID().uuidString).mp4")
        try VideoFixtures.makeGarbage(at: garbage)
        let empty = dir.appending(path: "empty.mp4")
        try Data().write(to: empty)
        let playable = dir.appending(path: "\(UUID().uuidString).mp4")
        try await VideoFixtures.makeMP4(at: playable, width: 320, height: 200, seconds: 1, audio: false)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.map(\.url.lastPathComponent) == [playable.lastPathComponent])
        #expect(!FileManager.default.fileExists(atPath: garbage.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: empty.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: playable.path(percentEncoded: false)))
    }

    /// A crash during a GIF's conversion leaves the MP4 and a partial GIF: the MP4 is recovered
    /// and the GIF, which does not play, removed.
    @Test func anMP4BesideAPartialGIFIsFoundAndTheGIFRemoved() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let mp4 = dir.appending(path: "\(id.uuidString).mp4")
        let gif = dir.appending(path: "\(id.uuidString).gif")
        try await VideoFixtures.makeMP4(at: mp4, width: 320, height: 200, seconds: 1, audio: false)
        // A header, a logical screen and part of a global table, as a conversion cut short leaves it.
        try Data(Array("GIF89a".utf8) + [0x40, 0x01, 0xC8, 0x00, 0xF7, 0, 0] + Array(repeating: 0x80, count: 300)).write(to: gif)

        let found = await RecordingRecovery.scan(dir)
        #expect(found.map(\.url.lastPathComponent) == [mp4.lastPathComponent])
        #expect(found.first?.id == id)
        #expect(!FileManager.default.fileExists(atPath: gif.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: mp4.path(percentEncoded: false)))
    }

    /// The GIF's record exists, so its MP4 was saved already: only a `.gif` record with the found
    /// file's id counts.
    @Test func isSavedAsGIFHoldsOnlyForAnIDWithAGIFRecord() {
        let id = UUID()
        let found = RecordingRecovery.Found(url: URL(filePath: "/tmp/Recording/\(id.uuidString).mp4"), id: id,
                                            facts: .playable(seconds: 3), created: .now)
        func record(_ recordID: UUID, _ kind: MediaKind) -> CaptureRecord {
            CaptureRecord(id: recordID, fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, mediaKind: kind)
        }
        #expect(RecordingRecovery.isSavedAsGIF(found, records: [record(UUID(), .image), record(id, .gif)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: [record(id, .video)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: [record(id, .image)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: [record(UUID(), .gif)]))
        #expect(!RecordingRecovery.isSavedAsGIF(found, records: []))
        let unnamed = RecordingRecovery.Found(url: URL(filePath: "/tmp/Recording/clip.mp4"), id: nil,
                                              facts: .playable(seconds: 3), created: .now)
        #expect(!RecordingRecovery.isSavedAsGIF(unnamed, records: [record(id, .gif)]))
    }

    // MARK: The mute log (design, Relaunch)

    /// `tmp/Recording` and `tmp/Mute`, side by side under `dir`.
    var recordings: URL { dir.appending(path: "Recording", directoryHint: .isDirectory) }
    var mute: URL { dir.appending(path: "Mute", directoryHint: .isDirectory) }

    func found(_ id: UUID, seconds: TimeInterval = 4) -> RecordingRecovery.Found {
        RecordingRecovery.Found(url: recordings.appending(path: "\(id.uuidString).mp4"), id: id,
                                facts: .playable(seconds: seconds), created: .now)
    }

    func writeLog(_ log: MuteLog, for id: UUID) throws {
        try MuteLog.write(log, to: mute.appending(path: "\(id.uuidString).json"))
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// What `prepare`'s ladder was asked: the file, its duration, the intervals and the lag.
    final class LadderCalls {
        var calls: [(file: URL, duration: TimeInterval, intervals: [MuteInterval], lag: TimeInterval)] = []
        var outcome = RecordingMute.Outcome.muted
        let segments = [MuteInterval(start: 1.9, end: 3.3)]

        func resolve(_ file: URL, _ duration: TimeInterval, _ intervals: [MuteInterval],
                     _ lag: TimeInterval) async -> RecordingMute.Resolution {
            calls.append((file, duration, intervals, lag))
            return RecordingMute.Resolution(outcome: outcome, segments: segments)
        }
    }

    func prepare(_ found: RecordingRecovery.Found, records: [CaptureRecord] = [],
                 ladder: LadderCalls) async -> RecordingRecovery.Prepared {
        await RecordingRecovery.prepare(found, records: records, muteDirectory: mute, resolve: ladder.resolve)
    }

    /// The real ladder over a tone fixture: the muted stretch comes back silent, and the log goes once
    /// the file has left `tmp/Recording`.
    @Test func aFoundFileWithALogComesBackMutedAndItsLogIsRemoved() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let file = recordings.appending(path: "\(id.uuidString).mp4")
        try await VideoFixtures.makeMP4(at: file, width: 320, height: 200, seconds: 4, audio: true, tone: [0...4])
        try writeLog(MuteLog(intervals: [MuteInterval(start: 1.0, end: 2.0)], lag: 0.3, sequence: 2), for: id)
        let rewrite = mute.appending(path: "\(id.uuidString).mp4")

        // Listed before the loop, as `recoverRecordings` lists it.
        let listed = RecordingRecovery.listMuteFolder(mute)
        let found = try #require(await RecordingRecovery.scan(recordings).first)
        let prepared = await RecordingRecovery.prepare(found, records: [], muteDirectory: mute) { file, duration, intervals, lag in
            await RecordingMute.resolve(file: file, output: rewrite, duration: duration, intervals: intervals, lag: lag,
                                        hasRoom: { _ in true },
                                        apply: { try await RecordingMute.apply($0, intervals: $1, to: $2) },
                                        stripAudio: { try await RecordingMute.stripAudio($0, to: $1) },
                                        replace: { try RecordingMute.replaceOriginal($0, with: $1) })
        }
        #expect(prepared == .recover(unmutedIntervals: [], bodySuffix: RecordingRecovery.mutedSuffix,
                                     removesLogAfterRecord: true))
        let audio = try #require(try await MovieSamples.audio(of: file))
        // [0.9, 2.3] after the lead and the lag, less the edges' smear.
        #expect(audio.peak(from: 0.95, to: 2.25) < 0.01)
        #expect(audio.peak(from: 2.35, to: 3.9) > 0.5)
        #expect(!exists(rewrite))

        // The move to `pending/` takes the file out of `tmp/Recording`; the sweep then removes its log.
        try FileManager.default.removeItem(at: file)
        RecordingRecovery.sweepMuteFolder(listed, recordingDirectory: recordings)
        #expect(!exists(mute.appending(path: "\(id.uuidString).json")))
    }

    @Test func aFoundFileWithNoLogIsLeftAsItIs() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let ladder = LadderCalls()
        let prepared = await prepare(found(UUID()), ladder: ladder)
        #expect(prepared == .recover(unmutedIntervals: [], bodySuffix: nil, removesLogAfterRecord: false))
        #expect(ladder.calls.isEmpty)
        // A file whose name carries no id has no log either.
        let unnamed = RecordingRecovery.Found(url: recordings.appending(path: "clip.mp4"), id: nil,
                                              facts: .playable(seconds: 4), created: .now)
        #expect(await prepare(unnamed, ladder: ladder)
            == .recover(unmutedIntervals: [], bodySuffix: nil, removesLogAfterRecord: false))
        #expect(ladder.calls.isEmpty)
    }

    @Test func anUnreadableLogMutesTheWholeFile() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try FileManager.default.createDirectory(at: mute, withIntermediateDirectories: true)
        try Data("{\"intervals\": [".utf8).write(to: mute.appending(path: "\(id.uuidString).json"))
        let ladder = LadderCalls()
        let prepared = await prepare(found(id, seconds: 6.5), ladder: ladder)
        #expect(prepared == .recover(unmutedIntervals: [], bodySuffix: RecordingRecovery.mutedSuffix,
                                     removesLogAfterRecord: true))
        let call = try #require(ladder.calls.first)
        #expect(ladder.calls.count == 1)
        #expect(call.file == found(id).url)
        #expect(call.duration == 6.5)
        #expect(call.intervals == [MuteInterval(start: 0, end: 6.5)])
    }

    /// The log's intervals and lag go to the ladder, whose segments close an open interval at the
    /// file's end.
    @Test func anOpenIntervalClosesAtTheFilesEnd() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let log = MuteLog(intervals: [MuteInterval(start: 1, end: 1.5), MuteInterval(start: 3, end: nil)],
                          lag: 0.6, sequence: 3)
        try writeLog(log, for: id)
        let ladder = LadderCalls()
        _ = await prepare(found(id, seconds: 5), ladder: ladder)
        let call = try #require(ladder.calls.first)
        #expect(call.duration == 5)
        #expect(call.intervals == log.intervals)
        #expect(call.lag == 0.6)

        var applied: [MuteInterval]?
        _ = await RecordingMute.resolve(file: call.file, output: mute.appending(path: "\(id.uuidString).mp4"),
                                        duration: call.duration, intervals: call.intervals, lag: call.lag,
                                        hasRoom: { _ in true }, apply: { _, segments, _ in applied = segments },
                                        stripAudio: { _, _ in }, replace: { _, _ in })
        let last = try #require(applied?.last)
        #expect(abs(last.start - 2.9) < 1e-9)
        #expect(last.end == 5)
    }

    @Test(arguments: [
        (RecordingMute.Outcome.muted, RecordingRecovery.mutedSuffix),
        (.soundRemoved, RecordingRecovery.soundRemovedSuffix),
    ])
    func eachOutcomeAddsItsSentence(outcome: RecordingMute.Outcome, suffix: String) async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try writeLog(MuteLog(intervals: [MuteInterval(start: 2, end: 3)], lag: 0.3, sequence: 1), for: id)
        let ladder = LadderCalls()
        ladder.outcome = outcome
        #expect(await prepare(found(id), ladder: ladder)
            == .recover(unmutedIntervals: [], bodySuffix: suffix, removesLogAfterRecord: true))
    }

    /// The record is marked with the ladder's segments, and the log goes only once it exists.
    @Test func aLadderThatGivesNotMutedMarksTheRecord() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try writeLog(MuteLog(intervals: [MuteInterval(start: 2, end: 3)], lag: 0.3, sequence: 1), for: id)
        let ladder = LadderCalls()
        ladder.outcome = .notMuted
        let prepared = await prepare(found(id), ladder: ladder)
        #expect(prepared == .recover(unmutedIntervals: ladder.segments, bodySuffix: RecordingRecovery.notMutedSuffix,
                                     removesLogAfterRecord: true))
        // `prepare` itself leaves the log in place.
        #expect(exists(mute.appending(path: "\(id.uuidString).json")))
    }

    @Test func aFoundFileWithAGIFRecordIsSavedAsAGIF() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        try writeLog(MuteLog(intervals: [MuteInterval(start: 2, end: 3)], lag: 0.3, sequence: 1), for: id)
        let gif = CaptureRecord(id: id, fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, mediaKind: .gif)
        let ladder = LadderCalls()
        #expect(await prepare(found(id), records: [gif], ladder: ladder) == .savedAsGIF)
        #expect(ladder.calls.isEmpty)
        let video = CaptureRecord(id: id, fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, mediaKind: .video)
        #expect(await prepare(found(id), records: [video], ladder: ladder) != .savedAsGIF)
    }

    /// Writes a log and a partial rewrite for each id into `tmp/Mute`.
    func writeMuteFiles(_ ids: [UUID]) throws {
        try FileManager.default.createDirectory(at: mute, withIntermediateDirectories: true)
        for id in ids {
            try Data("{}".utf8).write(to: mute.appending(path: "\(id.uuidString).json"))
            try Data("partial".utf8).write(to: mute.appending(path: "\(id.uuidString).mp4"))
        }
    }

    func muteFolderNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: mute.path(percentEncoded: false)).sorted()
    }

    /// Logs and partial rewrites listed before the loop whose recording has left `tmp/Recording` go,
    /// whatever their names.
    @Test func aListedFileWithNoRecordingIsSwept() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeMuteFiles([UUID(), UUID()])
        try Data("stray".utf8).write(to: mute.appending(path: "stray.txt"))
        let listed = RecordingRecovery.listMuteFolder(mute)
        #expect(listed.count == 5)

        RecordingRecovery.sweepMuteFolder(listed, recordingDirectory: recordings)
        #expect(try muteFolderNames().isEmpty)
    }

    /// A listed log whose recording is still in `tmp/Recording` (a move that failed) keeps it, with its
    /// partial rewrite, for the next launch.
    @Test func aListedFileWhoseRecordingIsThereIsKept() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let kept = UUID()
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        try Data("movie".utf8).write(to: recordings.appending(path: "\(kept.uuidString).mp4"))
        try writeMuteFiles([kept])
        let listed = RecordingRecovery.listMuteFolder(mute)

        RecordingRecovery.sweepMuteFolder(listed, recordingDirectory: recordings)
        #expect(try muteFolderNames() == ["\(kept.uuidString).json", "\(kept.uuidString).mp4"])
        #expect(exists(recordings.appending(path: "\(kept.uuidString).mp4")))
    }

    /// A log written after the list, as a recording made since launch writes one when Mute is pressed
    /// before its first frame, is kept with no `<id>.mp4` in `tmp/Recording`, while a listed one
    /// beside it goes (Decided 2026-10-24, 6).
    @Test func aFileWrittenAfterTheListIsKeptWithNoRecording() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let (orphan, sinceLaunch) = (UUID(), UUID())
        try writeMuteFiles([orphan])
        let listed = RecordingRecovery.listMuteFolder(mute)
        try writeLog(MuteLog(intervals: [MuteInterval(start: 0, end: nil)], lag: 0.3, sequence: 1), for: sinceLaunch)

        RecordingRecovery.sweepMuteFolder(listed, recordingDirectory: recordings)
        #expect(try muteFolderNames() == ["\(sinceLaunch.uuidString).json"])
        #expect(!exists(recordings))
    }

    /// `begin`, the launch check's start, lists `tmp/Mute` before it scans `tmp/Recording`: a log
    /// written during the scan, as a recording made since launch writes one when Mute is pressed
    /// before its first frame, is not in the list, so the sweep keeps it (Decided 2026-10-24, 6).
    @Test func theListIsTakenBeforeTheScanSoALogWrittenDuringItIsKept() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let (orphan, sinceLaunch) = (UUID(), UUID())
        try writeMuteFiles([orphan])
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        var scanned: [URL] = []
        let (listed, found) = await RecordingRecovery.begin(recordingDirectory: recordings, muteDirectory: mute) { folder in
            scanned.append(folder)
            try? writeLog(MuteLog(intervals: [MuteInterval(start: 0, end: nil)], lag: 0.3, sequence: 1), for: sinceLaunch)
            return await RecordingRecovery.scan(folder)
        }
        #expect(scanned == [recordings])
        #expect(found.isEmpty)
        #expect(listed.map(\.lastPathComponent).sorted() == ["\(orphan.uuidString).json", "\(orphan.uuidString).mp4"])

        RecordingRecovery.sweepMuteFolder(listed, recordingDirectory: recordings)
        #expect(try muteFolderNames() == ["\(sinceLaunch.uuidString).json"])
    }

    @Test func aMissingFolderListsNothingAndItsSweepDoesNothing() {
        defer { try? FileManager.default.removeItem(at: dir) }
        let listed = RecordingRecovery.listMuteFolder(mute)
        #expect(listed.isEmpty)
        RecordingRecovery.sweepMuteFolder(listed, recordingDirectory: recordings)
        #expect(!exists(mute))
    }

    @Test func theSentencesHaveTheDesignsText() {
        #expect(RecordingRecovery.mutedSuffix == "The muted parts were silenced.")
        #expect(RecordingRecovery.soundRemovedSuffix == "It was saved without sound.")
        #expect(RecordingRecovery.notMutedSuffix == "Its sound is not muted, so it was not uploaded.")
    }

    @Test func aMissingFolderFindsNothing() async {
        defer { try? FileManager.default.removeItem(at: dir) }
        let found = await RecordingRecovery.scan(dir.appending(path: "missing", directoryHint: .isDirectory))
        #expect(found.isEmpty)
    }

    @Test func anEmptyFolderFindsNothing() async {
        defer { try? FileManager.default.removeItem(at: dir) }
        let found = await RecordingRecovery.scan(dir)
        #expect(found.isEmpty)
    }

    @Test func aUUIDNameGivesThatIDAndAnotherNameGivesNil() async throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let named = dir.appending(path: "\(id.uuidString).mp4")
        let other = dir.appending(path: "clip.mp4")
        try await VideoFixtures.makeMP4(at: named, width: 320, height: 200, seconds: 1, audio: false)
        try await VideoFixtures.makeMP4(at: other, width: 320, height: 200, seconds: 1, audio: false)

        let found = await RecordingRecovery.scan(dir)
        let ids = Dictionary(uniqueKeysWithValues: found.map { ($0.url.lastPathComponent, $0.id) })
        #expect(ids.count == 2)
        #expect(ids[named.lastPathComponent] == .some(id))
        #expect(ids[other.lastPathComponent] == .some(nil))
    }
}
