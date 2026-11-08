import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// `GIFMaker` end to end over `VideoFixtures` (design, Conversion), decoded with ImageIO through
/// `GIFBlocks`, and its pure parts.
@Suite(.timeLimit(.minutes(2)))
struct GIFMakerTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "GIFMakerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// A fixture under `dir`, and the GIF's URL beside it.
    func urls() -> (mp4: URL, gif: URL) {
        let id = UUID().uuidString
        return (dir.appending(path: "\(id).mp4"), dir.appending(path: "\(id).gif"))
    }

    func make(_ mp4: URL, _ gif: URL, fps: Int, maxSide: Int = 1280,
              progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> GIFResult {
        try await GIFMaker.make(from: mp4, to: gif, fps: fps, maxSide: maxSide, freeBytes: { nil }, progress: progress)
    }

    func bytes(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    func sides(_ size: (width: Int, height: Int)) -> [Int] {
        [size.width, size.height]
    }

    // MARK: Pure parts

    @Test func theOutputFrameCountRoundsUpAndIsNeverZero() {
        #expect(GIFMaker.outputFrameCount(duration: 10.0, fps: 15) == 150)
        #expect(GIFMaker.outputFrameCount(duration: 10.01, fps: 15) == 151)
        #expect(GIFMaker.outputFrameCount(duration: 0, fps: 15) == 1)
        #expect(GIFMaker.outputFrameCount(duration: 0.3, fps: 10) == 3)
    }

    @Test func thirtyTwoPaletteSamplesSpreadEvenly() {
        let samples = GIFMaker.paletteSampleIndices(frameCount: 155)
        #expect(samples.count == 32)
        #expect(Set(samples).count == 32)
        #expect(samples.first == 0)
        #expect(samples.last == 154)
        #expect(samples == samples.sorted())
        // round(k × 154 / 31)
        #expect(samples[1] == 5)
        #expect(samples[16] == 79)
    }

    @Test func aShortRecordingSamplesEveryOutputFrame() {
        #expect(GIFMaker.paletteSampleIndices(frameCount: 1) == [0])
        #expect(GIFMaker.paletteSampleIndices(frameCount: 20) == Array(0..<20))
        #expect(GIFMaker.paletteSampleIndices(frameCount: 32) == Array(0..<32))
        let thirtyThree = GIFMaker.paletteSampleIndices(frameCount: 33)
        #expect(thirtyThree.count == 32 && Set(thirtyThree).count == 32 && thirtyThree.last == 32)
    }

    @Test func theLongSideGoesToTheMaximumAndTheOtherRoundsToWholePixels() {
        #expect(sides(GIFMaker.outputSize(width: 2560, height: 1664, maxSide: 1280)) == [1280, 832])
        #expect(sides(GIFMaker.outputSize(width: 1664, height: 2560, maxSide: 800)) == [520, 800])
        // 667 × 800 / 1001 = 533.07
        #expect(sides(GIFMaker.outputSize(width: 1001, height: 667, maxSide: 800)) == [800, 533])
        // 1001 × 800 / 1500 = 533.87
        #expect(sides(GIFMaker.outputSize(width: 1001, height: 1500, maxSide: 800)) == [534, 800])
    }

    @Test func aSmallSourceIsNeverUpscaledAndFullSizeKeepsUpTo4096() {
        #expect(sides(GIFMaker.outputSize(width: 640, height: 400, maxSide: 1280)) == [640, 400])
        #expect(sides(GIFMaker.outputSize(width: 1280, height: 832, maxSide: 1280)) == [1280, 832])
        let fullSize = GIFSettings(fps: 15, maxSide: 0).effectiveMaxSide
        #expect(sides(GIFMaker.outputSize(width: 4096, height: 2304, maxSide: fullSize)) == [4096, 2304])
        #expect(sides(GIFMaker.outputSize(width: 2560, height: 1664, maxSide: fullSize)) == [2560, 1664])
    }

    // MARK: Timing and frames

    /// 1.95 s at 15 fps is 30 output frames (29.25 rounded up), 200 cs in all, looping forever.
    @Test func theDelaysSumToTheOutputFramesAndTheGIFLoops() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 1.95, audio: false)
        let result = try await make(mp4, gif, fps: 15)

        let data = try bytes(gif)
        let frameCount = GIFMaker.outputFrameCount(duration: 1.95, fps: 15)
        #expect(frameCount == 30)
        #expect(result.outputFrameCount == frameCount)
        #expect(GIFBlocks.delays(data).reduce(0, +) == GIFTiming.centiseconds(through: frameCount, fps: 15))
        #expect(result.duration == Double(GIFTiming.centiseconds(through: frameCount, fps: 15)) / 100)
        let summary = GIFBlocks.summary(data)
        #expect(summary.type == "com.compuserve.gif")
        #expect(summary.loopCount == 0)
        #expect(summary.frameCount == result.gifFrameCount)
        #expect(result.byteCount == data.count)
        #expect(sides((result.pixelWidth, result.pixelHeight)) == [160, 100])
        try FileManager.default.removeItem(at: dir)
    }

    /// Every other frame of a 30 fps source at 15 fps: each output frame shows a new grey, so
    /// none merges.
    @Test func distinctFramesAtThirtyGiveEveryOutputFrameAtFifteen() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 2, audio: false,
                                        frameTimes: (0..<60).map { Double($0) / 30 })
        let result = try await make(mp4, gif, fps: 15)

        let data = try bytes(gif)
        #expect(result.outputFrameCount == 30)
        #expect(result.gifFrameCount == 30)
        #expect(GIFBlocks.summary(data).frameCount == 30)
        #expect(GIFBlocks.delays(data) == Array(repeating: [7, 6, 7], count: 10).flatMap { $0 })
        try FileManager.default.removeItem(at: dir)
    }

    /// Ten frames, a 2 s gap with no frame, then five: the gap is held as one frame of 200 cs.
    @Test func aGapIsOneFrameWhoseDelaySpansIt() async throws {
        let (mp4, gif) = urls()
        let times = (0..<10).map { Double($0) / 10 } + (0..<5).map { 2.9 + Double($0) / 10 }
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 3.4, audio: false, frameTimes: times)
        let result = try await make(mp4, gif, fps: 10)

        let data = try bytes(gif)
        #expect(result.outputFrameCount == 34)
        #expect(GIFBlocks.delays(data) == Array(repeating: 10, count: 9) + [200] + Array(repeating: 10, count: 5))
        try FileManager.default.removeItem(at: dir)
    }

    /// A source of 6 frames a second never gives more GIF frames than it has.
    @Test func aLowSourceRateGivesAtMostItsOwnFrames() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 2, audio: false,
                                        frameTimes: (0..<12).map { Double($0) / 6 })
        let result = try await make(mp4, gif, fps: 15)

        let data = try bytes(gif)
        #expect(result.outputFrameCount == 30)
        #expect(result.gifFrameCount <= 12)
        #expect(GIFBlocks.summary(data).frameCount == result.gifFrameCount)
        #expect(GIFBlocks.delays(data).reduce(0, +) == GIFTiming.centiseconds(through: 30, fps: 15))
        try FileManager.default.removeItem(at: dir)
    }

    /// Frames at 0 and 700 s at 10 fps: 70,000 cs held, split at the delay field's maximum.
    @Test func aLongHeldStretchIsSplitAtTheMaximumDelay() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 64, height: 48, seconds: 700.5, audio: false, frameTimes: [0, 700])
        let result = try await make(mp4, gif, fps: 10)

        let delays = GIFBlocks.delays(try bytes(gif))
        #expect(result.outputFrameCount == 7005)
        #expect(delays == [GIFTiming.maximumDelay, 70_000 - GIFTiming.maximumDelay, 50])
        #expect(delays.allSatisfy { $0 <= GIFTiming.maximumDelay })
        #expect(delays.reduce(0, +) == GIFTiming.centiseconds(through: 7005, fps: 10))
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: Size

    @Test func theLongSideIsCappedNeverUpscaledAndFullSizeKeepsTheSource() async throws {
        let (mp4, _) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 320, height: 200, seconds: 0.5, audio: false)
        let cases: [(maxSide: Int, size: [Int])] = [
            (160, [160, 100]),
            (1280, [320, 200]),
            (GIFSettings(fps: 15, maxSide: 0).effectiveMaxSide, [320, 200]),
        ]
        for (maxSide, size) in cases {
            let gif = dir.appending(path: "\(maxSide).gif")
            let result = try await make(mp4, gif, fps: 10, maxSide: maxSide)
            let summary = GIFBlocks.summary(try bytes(gif))
            #expect([result.pixelWidth, result.pixelHeight] == size)
            #expect([summary.width ?? 0, summary.height ?? 0] == size)
            let file = try GIFBlocks.parse(Array(try bytes(gif)))
            #expect([file.width, file.height] == size)
        }
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: Reserved colours (R3)

    /// Grey frames with the ring colours reserved: yellow, blue and black lead the global table.
    @Test func reservedRingColoursLeadTheGlobalTable() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 1, audio: false)
        _ = try await GIFMaker.make(from: mp4, to: gif, fps: 10, maxSide: 1280,
                                    reserving: ClickRingColour.reservedGIFColours,
                                    freeBytes: { nil }, progress: { _ in })

        let file = try GIFBlocks.parse(Array(try bytes(gif)))
        #expect(Array(file.globalTable.prefix(3)) == ClickRingColour.reservedGIFColours)
        #expect(file.globalTable.count == file.globalTableEntries)
        try FileManager.default.removeItem(at: dir)
    }

    /// Without `reserving`, the same frames give a table with no yellow or blue.
    @Test func noReservedColoursLeavesTheRingColoursOut() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 1, audio: false)
        _ = try await make(mp4, gif, fps: 10)

        let file = try GIFBlocks.parse(Array(try bytes(gif)))
        #expect(!file.globalTable.contains(ClickRingColour.yellow.gifColour))
        #expect(!file.globalTable.contains(ClickRingColour.blue.gifColour))
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: Progress

    @Test func progressNeverDecreasesReachesThePaletteShareAndEndsAtOne() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 4, audio: false)
        let reported = Mutex<[Double]>([])
        _ = try await make(mp4, gif, fps: 15) { fraction in reported.withLock { $0.append(fraction) } }

        let values = reported.withLock { $0 }
        #expect(!values.isEmpty)
        #expect(values == values.sorted())
        #expect(values.contains(GIFMaker.paletteShare))
        #expect(values.filter { $0 < GIFMaker.paletteShare }.allSatisfy { $0 >= 0 })
        #expect(values.last == 1)
        #expect(values.count { $0 == 1 } == 1)
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: Failures

    @Test func aCorruptMP4ThrowsAndLeavesNoGIF() async throws {
        let (mp4, gif) = urls()
        try VideoFixtures.makeGarbage(at: mp4)
        await #expect(throws: (any Error).self) {
            _ = try await make(mp4, gif, fps: 15)
        }
        #expect(!exists(gif))
        try FileManager.default.removeItem(at: dir)
    }

    /// The first report is pass 1's first palette sample: a cancel there throws before pass 2.
    @Test func aCancelInThePalettePassThrowsAndLeavesNoGIF() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 4, audio: false)
        let firsts = Mutex<[Double]>([])
        let task = Task {
            try await make(mp4, gif, fps: 15) { fraction in
                firsts.withLock { $0.append(fraction) }
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(firsts.withLock { $0 } == [0])
        #expect(!exists(gif))
        try FileManager.default.removeItem(at: dir)
    }

    /// The palette share is reported once the GIF's file is open, so a cancel there lands at pass
    /// 2's first frame, with the file on disk.
    @Test func aCancelInTheEncodePassThrowsAndLeavesNoGIF() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 160, height: 100, seconds: 4, audio: false)
        let fileExistedAtCancel = Mutex<Bool?>(nil)
        let task = Task {
            try await make(mp4, gif, fps: 15) { fraction in
                guard fraction >= GIFMaker.paletteShare else { return }
                fileExistedAtCancel.withLock { $0 = $0 ?? FileManager.default.fileExists(atPath: gif.path(percentEncoded: false)) }
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(fileExistedAtCancel.withLock { $0 } == true)
        #expect(!exists(gif))
        try FileManager.default.removeItem(at: dir)
    }

    // MARK: Sharpness

    /// A 2 px line at column 100 of 640 px, halved exactly: column 50 stays dark, its neighbours
    /// light, and the white well away from it is one colour, with no dither.
    @Test func aLineStaysSharpAfterAnExactHalving() async throws {
        let (mp4, gif) = urls()
        try await VideoFixtures.makeMP4(at: mp4, width: 640, height: 400, seconds: 0.5, audio: false, pattern: 100)
        let result = try await make(mp4, gif, fps: 10, maxSide: 320)
        #expect(sides((result.pixelWidth, result.pixelHeight)) == [320, 200])

        let first = try #require(GIFBlocks.decodedFrames(try bytes(gif)).first)
        try #require(first.count == 320 * 200)
        func luma(_ x: Int, _ y: Int) -> Double {
            let colour = first[y * 320 + x]
            return 0.299 * Double(colour.r) + 0.587 * Double(colour.g) + 0.114 * Double(colour.b)
        }
        for y in [20, 100, 180] {
            #expect(luma(50, y) <= 80)
            #expect(luma(49, y) >= 180)
            #expect(luma(51, y) >= 180)
        }
        var white = Set<GIFColour>()
        for y in 0..<200 {
            for x in 0...40 { white.insert(first[y * 320 + x]) }
        }
        #expect(white.count == 1)
        try FileManager.default.removeItem(at: dir)
    }
}
