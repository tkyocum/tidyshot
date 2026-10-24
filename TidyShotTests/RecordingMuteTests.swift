import AVFoundation
import Foundation
import Testing
@testable import TidyShot

/// Muting a recording's file (design, After the end, Privacy rule): the segments, the rewrite over
/// `VideoFixtures` tones, the audio removal, the replace, the mute log and the ladder with its
/// steps injected.
@Suite(.timeLimit(.minutes(2)))
struct RecordingMuteTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "RecordingMuteTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func cleanUp() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path(percentEncoded: false))
        try? FileManager.default.removeItem(at: dir)
    }

    /// A tone fixture: 320 × 200, 4 s, the tone over `tone`, mono at 44.1 kHz unless told otherwise.
    func toneMovie(_ name: String = "source.mp4", seconds: Double = 4, tone: [ClosedRange<Double>] = [0...4],
                   sampleRate: Int = 44_100, channels: Int = 1) async throws -> URL {
        let url = dir.appending(path: name)
        try await VideoFixtures.makeMP4(at: url, width: 320, height: 200, seconds: seconds, audio: true, tone: tone,
                                        sampleRate: sampleRate, channels: channels)
        return url
    }

    /// The time of the first frame between `start` and `end` s with a channel louder than a tenth of
    /// full scale, or with `last` of the last one; nil when none is.
    func loud(_ audio: MovieSamples.Audio, from start: TimeInterval, to end: TimeInterval,
              last: Bool = false) -> TimeInterval? {
        let first = max(0, Int((start * audio.sampleRate).rounded(.down)))
        let stop = min(audio.samples.count / audio.channels, Int((end * audio.sampleRate).rounded(.up)))
        guard stop > first else { return nil }
        func isLoud(_ frame: Int) -> Bool {
            (0..<audio.channels).contains { abs(Int(audio.samples[frame * audio.channels + $0])) > 3_277 }
        }
        let frame = last ? (first..<stop).reversed().first(where: isLoud) : (first..<stop).first(where: isLoud)
        return frame.map { Double($0) / audio.sampleRate }
    }

    /// Closed intervals from pairs.
    func closed(_ pairs: [(Double, Double)]) -> [MuteInterval] {
        pairs.map { MuteInterval(start: $0.0, end: $0.1) }
    }

    func expectClose(_ intervals: [MuteInterval], _ pairs: [(Double, Double)],
                     sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(intervals.count == pairs.count, sourceLocation: sourceLocation)
        for (interval, pair) in zip(intervals, pairs) {
            #expect(abs(interval.start - pair.0) < 1e-9, "start \(interval.start) ≠ \(pair.0)", sourceLocation: sourceLocation)
            #expect(abs((interval.end ?? .nan) - pair.1) < 1e-9, "end \(String(describing: interval.end)) ≠ \(pair.1)",
                    sourceLocation: sourceLocation)
        }
    }

    // MARK: Segments

    @Test func theLeadIsATenthAndTheDefaultLagThreeTenths() {
        #expect(RecordingMute.lead == 0.1)
        #expect(RecordingMute.defaultLag == 0.3)
    }

    @Test func segmentsWidenByTheLeadAndTheLag() {
        let segments = RecordingMute.segments(duration: 10, intervals: closed([(2, 5)]), lead: 0.1, lag: 0.3)
        expectClose(segments, [(1.9, 5.3)])
    }

    @Test func segmentsMergeWhatOverlapsInTimeOrder() {
        // Widened: [5.9, 7.3], [1.9, 3.3] and [3.2, 4.3]; the last two overlap.
        let segments = RecordingMute.segments(duration: 10, intervals: closed([(6, 7), (2, 3), (3.3, 4)]),
                                              lead: 0.1, lag: 0.3)
        expectClose(segments, [(1.9, 4.3), (5.9, 7.3)])
    }

    @Test func segmentsClampToTheFile() {
        let segments = RecordingMute.segments(duration: 10, intervals: closed([(0.05, 0.5), (9.9, 9.95)]),
                                              lead: 0.1, lag: 0.3)
        expectClose(segments, [(0, 0.8), (9.8, 10)])
    }

    @Test func aShortIntervalIsKeptWidened() {
        let segments = RecordingMute.segments(duration: 10, intervals: closed([(3, 3.05)]), lead: 0.1, lag: 0.3)
        expectClose(segments, [(2.9, 3.35)])
        let length = (segments.first?.end ?? 0) - (segments.first?.start ?? 0)
        #expect(abs(length - 0.45) < 1e-9)
    }

    @Test func anOpenIntervalClosesAtTheEnd() {
        let segments = RecordingMute.segments(duration: 7, intervals: [MuteInterval(start: 4, end: nil)],
                                              lead: 0.1, lag: 0.3)
        expectClose(segments, [(3.9, 7)])
    }

    @Test func noIntervalsGiveNoSegments() {
        #expect(RecordingMute.segments(duration: 7, intervals: [], lead: 0.1, lag: 0.3).isEmpty)
    }

    // MARK: The mute log

    @Test func theLogAndTheRewriteLiveInTmpMute() {
        let id = UUID()
        let mute = FileManager.default.temporaryDirectory.appending(path: "Mute", directoryHint: .isDirectory)
        #expect(MuteLog.directory.standardizedFileURL == mute.standardizedFileURL)
        #expect(MuteLog.url(for: id).standardizedFileURL == mute.appending(path: "\(id.uuidString).json").standardizedFileURL)
        #expect(RecordingMute.rewriteURL(for: id).standardizedFileURL
            == mute.appending(path: "\(id.uuidString).mp4").standardizedFileURL)
    }

    @Test func theLogEncodesAndDecodesWithAnOpenIntervalAndTheLag() throws {
        defer { cleanUp() }
        let url = dir.appending(path: "Mute/\(UUID().uuidString).json")
        let log = MuteLog(intervals: [MuteInterval(start: 1.5, end: 2.25), MuteInterval(start: 4, end: nil)],
                          lag: 0.65, sequence: 3)
        // The folder is made by the write.
        try MuteLog.write(log, to: url)
        #expect(MuteLog.read(url) == .log(log))
        // An open interval is stored as its start only.
        let json = try #require(String(data: Data(contentsOf: url), encoding: .utf8))
        #expect(json.components(separatedBy: "\"end\"").count == 2)

        // A later write replaces the whole file.
        let later = MuteLog(intervals: [MuteInterval(start: 1.5, end: 2.25)], lag: 0.65, sequence: 4)
        try MuteLog.write(later, to: url)
        #expect(MuteLog.read(url) == .log(later))
    }

    @Test func aMissingLogReadsAsNoneAndGarbageAsUnreadable() throws {
        defer { cleanUp() }
        #expect(MuteLog.read(dir.appending(path: "missing.json")) == .none)
        let garbage = dir.appending(path: "garbage.json")
        try Data("{\"intervals\": [".utf8).write(to: garbage)
        #expect(MuteLog.read(garbage) == .unreadable)
    }

    // MARK: The rewrite

    /// The design's `apply` item: same duration, one continuous audio segment as long as the video,
    /// silence inside each segment, the tone outside it, and the video samples untouched.
    @Test func applySilencesEachSegmentAndKeepsEverythingElse() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let output = dir.appending(path: "muted.mp4")
        let segments = closed([(1.0, 1.8), (2.6, 3.0)])
        try await RecordingMute.apply(source, intervals: segments, to: output)

        #expect(abs(try await MovieSamples.duration(of: output) - (try await MovieSamples.duration(of: source))) <= 0.05)
        let asset = AVURLAsset(url: output)
        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let audioSegments = try await audioTrack.load(.segments)
        #expect(!audioSegments.isEmpty)
        #expect(audioSegments.allSatisfy { !$0.isEmpty })
        let audioLength = try await audioTrack.load(.timeRange).duration.seconds
        let videoLength = try await videoTrack.load(.timeRange).duration.seconds
        #expect(abs(audioLength - videoLength) <= 0.05)

        let audio = try #require(try await MovieSamples.audio(of: output))
        // 50 ms at each edge are left for the AAC smear.
        #expect(audio.peak(from: 1.05, to: 1.75) < 0.01)
        #expect(audio.peak(from: 2.65, to: 2.95) < 0.01)
        #expect(audio.peak(from: 0.05, to: 0.95) > 0.5)
        #expect(audio.peak(from: 1.85, to: 2.55) > 0.5)
        #expect(audio.peak(from: 3.05, to: 3.9) > 0.5)

        #expect(try await MovieSamples.videoSamples(of: output) == (try await MovieSamples.videoSamples(of: source)))
    }

    /// The sound keeps its time to the millisecond, at the fixtures' rate and at a recording's: the
    /// tone's starts and ends outside the segment are where the source has them. A decode that kept
    /// the AAC priming (2,112 frames, 48 ms at 44.1 kHz) passes the 50 ms margins above but not this.
    @Test(arguments: [(44_100, 1), (48_000, 2)])
    func theSoundOutsideTheSegmentsKeepsItsTime(sampleRate: Int, channels: Int) async throws {
        defer { cleanUp() }
        let source = try await toneMovie(tone: [0.5...1.5, 2.0...3.5], sampleRate: sampleRate, channels: channels)
        let output = dir.appending(path: "muted.mp4")
        try await RecordingMute.apply(source, intervals: closed([(2.5, 3.0)]), to: output)
        let before = try #require(try await MovieSamples.audio(of: source))
        let after = try #require(try await MovieSamples.audio(of: output))
        #expect(after.sampleRate == Double(sampleRate))
        #expect(after.channels == channels)

        for (edge, last) in [(0.5, false), (1.5, true), (2.0, false), (3.5, true)] {
            let was = try #require(loud(before, from: edge - 0.1, to: edge + 0.1, last: last))
            let now = try #require(loud(after, from: edge - 0.1, to: edge + 0.1, last: last))
            #expect(abs(was - edge) < 0.005, "the source's edge at \(edge) s is at \(was) s")
            #expect(abs(now - was) < 0.001, "the edge at \(edge) s moved from \(was) s to \(now) s")
        }
        #expect(after.peak(from: 2.55, to: 2.95) < 0.01)
    }

    /// The rewrite's sound is exactly as long as the source's: neither the priming nor the padding
    /// after the last frame reaches it, and nothing is dropped.
    @Test(arguments: [(44_100, 1), (48_000, 2)])
    func theRewritesSoundIsAsLongAsTheSources(sampleRate: Int, channels: Int) async throws {
        defer { cleanUp() }
        let source = try await toneMovie(sampleRate: sampleRate, channels: channels)
        let output = dir.appending(path: "muted.mp4")
        try await RecordingMute.apply(source, intervals: closed([(1.0, 2.0)]), to: output)
        let before = try #require(try await MovieSamples.audio(of: source))
        let after = try #require(try await MovieSamples.audio(of: output))
        let frames = before.samples.count / channels
        #expect(frames == Int((4 * Double(sampleRate)).rounded()))
        #expect(after.samples.count / channels == frames)
    }

    /// Sound spoken just before Unmute lands up to the input's latency later; the lag covers it.
    @Test func aToneEndingPastAnIntervalIsSilencedThroughThatEdge() async throws {
        defer { cleanUp() }
        // Muted from 1.0 to 2.0 s; the tone reaches the file until 0.13 s after Unmute.
        let source = try await toneMovie(tone: [1.0...2.13])
        let before = try #require(try await MovieSamples.audio(of: source))
        #expect(before.peak(from: 2.0, to: 2.1) > 0.5)

        let segments = RecordingMute.segments(duration: 4, intervals: closed([(1.0, 2.0)]),
                                              lead: RecordingMute.lead, lag: RecordingMute.defaultLag)
        let output = dir.appending(path: "muted.mp4")
        try await RecordingMute.apply(source, intervals: segments, to: output)
        let after = try #require(try await MovieSamples.audio(of: output))
        #expect(after.peak(from: 0, to: 4) < 0.01)
    }

    @Test func aFileWithNoAudioTrackComesThroughUnchanged() async throws {
        defer { cleanUp() }
        let source = dir.appending(path: "silent.mp4")
        try await VideoFixtures.makeMP4(at: source, width: 320, height: 200, seconds: 2, audio: false)
        let output = dir.appending(path: "muted.mp4")
        try await RecordingMute.apply(source, intervals: closed([(0.5, 1.0)]), to: output)

        #expect(try await MovieSamples.trackCount(of: output, .audio) == 0)
        #expect(try await MovieSamples.trackCount(of: output, .video) == 1)
        #expect(abs(try await MovieSamples.duration(of: output) - 2) <= 0.05)
        #expect(try await MovieSamples.videoSamples(of: output) == (try await MovieSamples.videoSamples(of: source)))
    }

    /// A crash between the replace and the log's removal applies the log again to a muted file.
    @Test func applyOnItsOwnOutputChangesNothingAudible() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let segments = closed([(1.0, 2.0)])
        let once = dir.appending(path: "once.mp4")
        let twice = dir.appending(path: "twice.mp4")
        try await RecordingMute.apply(source, intervals: segments, to: once)
        try await RecordingMute.apply(once, intervals: segments, to: twice)

        let first = try #require(try await MovieSamples.audio(of: once))
        let second = try #require(try await MovieSamples.audio(of: twice))
        #expect(abs(first.duration - second.duration) <= 0.05)
        #expect(second.peak(from: 1.05, to: 1.95) < 0.01)
        // Each 100 ms window peaks at the same level, away from the edges' smear.
        for window in stride(from: 0.0, to: 3.9, by: 0.1) where !(0.9...2.05).contains(window) {
            let difference = abs(first.peak(from: window, to: window + 0.1) - second.peak(from: window, to: window + 0.1))
            #expect(difference < 0.05, "window at \(window) s")
        }
        #expect(try await MovieSamples.videoSamples(of: twice) == (try await MovieSamples.videoSamples(of: source)))
    }

    @Test func applyReplacesAFileAlreadyAtTheOutput() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let output = dir.appending(path: "muted.mp4")
        try Data("stale".utf8).write(to: output)
        try await RecordingMute.apply(source, intervals: closed([(1.0, 2.0)]), to: output)
        let audio = try #require(try await MovieSamples.audio(of: output))
        #expect(audio.peak(from: 1.05, to: 1.95) < 0.01)
    }

    @Test func stripAudioKeepsTheVideoAndDropsTheSound() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let output = dir.appending(path: "silent.mp4")
        try await RecordingMute.stripAudio(source, to: output)

        #expect(try await MovieSamples.trackCount(of: output, .audio) == 0)
        #expect(try await MovieSamples.trackCount(of: output, .video) == 1)
        #expect(abs(try await MovieSamples.duration(of: output) - (try await MovieSamples.duration(of: source))) <= 0.05)
        #expect(try await MovieSamples.videoSamples(of: output) == (try await MovieSamples.videoSamples(of: source)))
    }

    @Test func applyAndStripAudioIntoAFolderThatRefusesWritesThrowAndLeaveNothing() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let locked = dir.appending(path: "locked", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path(percentEncoded: false))
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path(percentEncoded: false))
        }
        let muted = locked.appending(path: "muted.mp4")
        let silent = locked.appending(path: "silent.mp4")

        await #expect(throws: (any Error).self) {
            try await RecordingMute.apply(source, intervals: closed([(1.0, 2.0)]), to: muted)
        }
        await #expect(throws: (any Error).self) {
            try await RecordingMute.stripAudio(source, to: silent)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: locked.path(percentEncoded: false)).isEmpty)
        #expect(exists(source))
    }

    /// A cancel before anything is read.
    @Test func aCancelledApplyThrowsAndLeavesNoOutput() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let output = dir.appending(path: "muted.mp4")
        try Data("stale".utf8).write(to: output)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await RecordingMute.apply(source, intervals: closed([(1.0, 2.0)]), to: output)
        }
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!exists(output))
        #expect(exists(source))
    }

    /// A cancel once the writer has made the output, while it writes.
    @Test func aCancelWhileApplyWritesThrowsAndLeavesNoOutput() async throws {
        defer { cleanUp() }
        let source = try await toneMovie(seconds: 20, tone: [0...20])
        let output = dir.appending(path: "muted.mp4")
        let task = Task { try await RecordingMute.apply(source, intervals: closed([(1.0, 2.0)]), to: output) }
        let deadline = ContinuousClock.now + .seconds(20)
        while !exists(output), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(exists(output))
        task.cancel()
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!exists(output))
        #expect(exists(source))
    }

    @Test func aCancelledStripAudioThrowsAndLeavesNoOutput() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let output = dir.appending(path: "silent.mp4")
        try Data("stale".utf8).write(to: output)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await RecordingMute.stripAudio(source, to: output)
        }
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!exists(output))
        #expect(exists(source))
    }

    /// `tmp/Mute` exists only once a log write has succeeded, and the launch clear removes `tmp/Trim`.
    @Test func applyAndStripAudioMakeAFolderThatDoesNotExistYet() async throws {
        defer { cleanUp() }
        let source = try await toneMovie()
        let muted = dir.appending(path: "Mute/deeper/muted.mp4")
        let silent = dir.appending(path: "Trim/deeper/silent.mp4")
        try await RecordingMute.apply(source, intervals: closed([(1.0, 2.0)]), to: muted)
        try await RecordingMute.stripAudio(source, to: silent)
        #expect(try await MovieSamples.trackCount(of: muted, .audio) == 1)
        #expect(try await MovieSamples.trackCount(of: silent, .video) == 1)
        #expect(try await MovieSamples.trackCount(of: silent, .audio) == 0)
    }

    // MARK: The replace

    @Test func afterApplyAndTheReplaceTmpRecordingHoldsExactlyOneFile() async throws {
        defer { cleanUp() }
        let id = UUID()
        let recordings = dir.appending(path: "Recording", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let original = try await toneMovie("Recording/\(id.uuidString).mp4")
        let rewrite = dir.appending(path: "Mute/\(id.uuidString).mp4")

        try await RecordingMute.apply(original, intervals: closed([(1.0, 2.0)]), to: rewrite)
        try RecordingMute.replaceOriginal(original, with: rewrite)

        #expect(try FileManager.default.contentsOfDirectory(atPath: recordings.path(percentEncoded: false))
            == ["\(id.uuidString).mp4"])
        #expect(!exists(rewrite))
        let audio = try #require(try await MovieSamples.audio(of: original))
        #expect(audio.peak(from: 1.05, to: 1.95) < 0.01)
        #expect(audio.peak(from: 2.05, to: 3.9) > 0.5)
    }

    @Test func aReplaceWithNoOutputThrowsAndKeepsTheOriginal() throws {
        defer { cleanUp() }
        let original = dir.appending(path: "original.mp4")
        try Data("original".utf8).write(to: original)
        #expect(throws: (any Error).self) {
            try RecordingMute.replaceOriginal(original, with: dir.appending(path: "missing.mp4"))
        }
        #expect(try Data(contentsOf: original) == Data("original".utf8))
    }

    @Test func aReplaceOverAMissingOriginalPutsTheOutputInItsPlace() throws {
        defer { cleanUp() }
        let original = dir.appending(path: "original.mp4")
        let output = dir.appending(path: "output.mp4")
        try Data("muted".utf8).write(to: output)
        try RecordingMute.replaceOriginal(original, with: output)
        #expect(try Data(contentsOf: original) == Data("muted".utf8))
        #expect(!exists(output))
    }

    // MARK: The ladder

    /// The ladder's steps over temporary files: `apply` and `stripAudio` write their output, and
    /// `replace` puts it over the file, each failing on request. `events` lists what ran.
    final class Ladder {
        enum Failure: Error, LocalizedError {
            case injected(String)
            var errorDescription: String? {
                if case .injected(let step) = self { "\(step) failed" } else { nil }
            }
        }

        let file: URL
        let output: URL
        var room = true
        var applyFails = false
        var stripFails = false
        /// Which `replace` calls fail, counting from 1.
        var failingReplaces: Set<Int> = []
        private(set) var events: [String] = []
        private(set) var appliedSegments: [MuteInterval]?
        private(set) var roomAskedFor: URL?
        /// Whether `output` existed when `stripAudio` began.
        private(set) var outputExistedAtStrip: Bool?
        private var replaces = 0

        init(dir: URL) throws {
            file = dir.appending(path: "Recording/file.mp4")
            output = dir.appending(path: "Mute/file.mp4")
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("original".utf8).write(to: file)
        }

        var contents: String? {
            (try? Data(contentsOf: file)).flatMap { String(data: $0, encoding: .utf8) }
        }

        func resolve(duration: TimeInterval = 10, intervals: [MuteInterval],
                     lag: TimeInterval = 0.3) async -> RecordingMute.Resolution {
            await RecordingMute.resolve(
                file: file, output: output, duration: duration, intervals: intervals, lag: lag,
                hasRoom: { [unowned self] url in
                    roomAskedFor = url
                    return room
                },
                apply: { [unowned self] source, segments, output in
                    events.append("apply")
                    appliedSegments = segments
                    #expect(source == file)
                    // Partial output, as a failing writer leaves it.
                    try Data("muted".utf8).write(to: output)
                    if applyFails { throw Failure.injected("apply") }
                },
                stripAudio: { [unowned self] source, output in
                    events.append("strip")
                    #expect(source == file)
                    outputExistedAtStrip = FileManager.default.fileExists(atPath: output.path(percentEncoded: false))
                    try Data("stripped".utf8).write(to: output)
                    if stripFails { throw Failure.injected("stripAudio") }
                },
                replace: { [unowned self] original, output in
                    replaces += 1
                    events.append("replace")
                    if failingReplaces.contains(replaces) { throw Failure.injected("replace") }
                    _ = try FileManager.default.replaceItemAt(original, withItemAt: output)
                })
        }
    }

    @Test func applyThenReplaceIsMuted() async throws {
        defer { cleanUp() }
        let ladder = try Ladder(dir: dir)
        let intervals = [MuteInterval(start: 2, end: 5), MuteInterval(start: 8, end: nil)]
        let resolution = await ladder.resolve(duration: 10, intervals: intervals, lag: 0.6)
        #expect(resolution.outcome == .muted)
        let expected = RecordingMute.segments(duration: 10, intervals: intervals, lead: RecordingMute.lead, lag: 0.6)
        #expect(resolution.segments == expected)
        #expect(ladder.appliedSegments == expected)
        #expect(ladder.events == ["apply", "replace"])
        #expect(ladder.roomAskedFor == ladder.file)
        #expect(ladder.contents == "muted")
        #expect(!exists(ladder.output))
    }

    @Test func aFailedApplyRemovesTheSoundInstead() async throws {
        defer { cleanUp() }
        let ladder = try Ladder(dir: dir)
        ladder.applyFails = true
        let resolution = await ladder.resolve(intervals: closed([(2, 5)]))
        #expect(resolution.outcome == .soundRemoved)
        #expect(ladder.events == ["apply", "strip", "replace"])
        // The failed rewrite's partial output is gone before the audio removal writes there.
        #expect(ladder.outputExistedAtStrip == false)
        #expect(ladder.contents == "stripped")
        #expect(!exists(ladder.output))
    }

    @Test func aReplaceThatFailsAfterApplyGoesOnToStripAudio() async throws {
        defer { cleanUp() }
        let ladder = try Ladder(dir: dir)
        ladder.failingReplaces = [1]
        let resolution = await ladder.resolve(intervals: closed([(2, 5)]))
        #expect(resolution.outcome == .soundRemoved)
        #expect(ladder.events == ["apply", "replace", "strip", "replace"])
        #expect(ladder.outputExistedAtStrip == false)
        #expect(ladder.contents == "stripped")
        #expect(!exists(ladder.output))
    }

    @Test func bothStepsFailingIsNotMutedWithTheSegments() async throws {
        defer { cleanUp() }
        let ladder = try Ladder(dir: dir)
        ladder.applyFails = true
        ladder.stripFails = true
        let intervals = closed([(2, 5)])
        let resolution = await ladder.resolve(duration: 10, intervals: intervals, lag: 0.3)
        #expect(resolution.outcome == .notMuted)
        #expect(resolution.segments == RecordingMute.segments(duration: 10, intervals: intervals, lead: 0.1, lag: 0.3))
        #expect(ladder.events == ["apply", "strip"])
        #expect(ladder.contents == "original")
        #expect(!exists(ladder.output))
    }

    @Test func aReplaceThatFailsAfterStripAudioIsNotMuted() async throws {
        defer { cleanUp() }
        let ladder = try Ladder(dir: dir)
        ladder.applyFails = true
        ladder.failingReplaces = [1]
        let resolution = await ladder.resolve(intervals: closed([(2, 5)]))
        #expect(resolution.outcome == .notMuted)
        #expect(ladder.events == ["apply", "strip", "replace"])
        #expect(ladder.contents == "original")
        #expect(!exists(ladder.output))
    }

    @Test func tooLittleRoomIsNotMutedWithoutEitherStep() async throws {
        defer { cleanUp() }
        let ladder = try Ladder(dir: dir)
        ladder.room = false
        // A rewrite a crash left behind goes too.
        try Data("stale".utf8).write(to: ladder.output)
        let resolution = await ladder.resolve(intervals: closed([(2, 5)]))
        #expect(resolution.outcome == .notMuted)
        #expect(resolution.segments == RecordingMute.segments(duration: 10, intervals: closed([(2, 5)]), lead: 0.1, lag: 0.3))
        #expect(ladder.events.isEmpty)
        #expect(ladder.roomAskedFor == ladder.file)
        #expect(ladder.contents == "original")
        #expect(!exists(ladder.output))
    }

    @Test func soundRemovedHasTheDesignsText() {
        #expect(RecordingMute.soundRemovedNotice == RecordingNotice(
            title: "Sound removed", body: "Muting failed, so the recording has no sound."))
    }

    // MARK: Fault injection

    #if DEBUG
    @Test func muteFailureIsReadFromItsArgument() {
        #expect(RecordingMute.MuteFailure(argument: "apply") == .apply)
        #expect(RecordingMute.MuteFailure(argument: "both") == .both)
        #expect(RecordingMute.MuteFailure(argument: nil) == nil)
        #expect(RecordingMute.MuteFailure(argument: "other") == nil)
    }

    /// `apply` makes the rewrite throw, `both` the audio removal too; the replace is never wrapped.
    @Test func muteFailureWrapsTheSteps() async throws {
        defer { cleanUp() }
        let file = dir.appending(path: "file.mp4")
        let output = dir.appending(path: "output.mp4")
        try Data("original".utf8).write(to: file)
        let steps = RecordingMute.Steps(apply: { _, _, _ in }, stripAudio: { _, _ in },
                                        replace: { original, output in
                                            _ = try FileManager.default.replaceItemAt(original, withItemAt: output)
                                        })

        let applyFails = RecordingMute.MuteFailure.apply.wrap(steps)
        await #expect(throws: (any Error).self) { try await applyFails.apply(file, [], output) }
        try await applyFails.stripAudio(file, output)

        let bothFail = RecordingMute.MuteFailure.both.wrap(steps)
        await #expect(throws: (any Error).self) { try await bothFail.apply(file, [], output) }
        await #expect(throws: (any Error).self) { try await bothFail.stripAudio(file, output) }
        try Data("muted".utf8).write(to: output)
        try bothFail.replace(file, output)
        #expect(try Data(contentsOf: file) == Data("muted".utf8))
    }
    #endif
}
