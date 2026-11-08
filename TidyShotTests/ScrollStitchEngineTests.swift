import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The engine actor end to end: synthetic BGRA frames in, a CGImage out, through the PNG
/// encoder and decoder every capture goes through.
struct ScrollStitchEngineTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The plain scenario's viewer (no spinner, no scrollbar thumb, so every pixel is known):
    /// the frame at offset 0, then one per step of 500 rows, clamped to the page.
    func plainFrames(_ page: inout SyntheticPage, steps: Int) -> (frames: [ScrollFrame], reached: Int) {
        var offset = 0
        var frames = [page.frame(at: 0, animated: false, scrollbarVisible: false)]
        for _ in 0..<steps {
            offset = min(page.maxOffset, offset + 500)
            frames.append(page.frame(at: offset, animated: false, scrollbarVisible: false))
        }
        return (frames, offset)
    }

    /// `image` drawn into a BGRA bitmap in its own colour space, so no colour conversion happens:
    /// `width * height * 4` bytes, blue first, the fourth byte undefined.
    func bgra(of image: CGImage) throws -> Data {
        let space = try #require(image.colorSpace)
        var data = Data(count: image.width * image.height * 4)
        try data.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    @Test func stitchesThroughTheActorToAnExactPNGAtScale2() async throws {
        var page = SyntheticPage()
        let (frames, reached) = plainFrames(&page, steps: 18)
        let engine = ScrollStitchEngine(finder: page.finder)
        await engine.begin(first: frames[0])
        var last: StitchProgress?
        var committed = 0
        var previewRows = 0
        for frame in frames.dropFirst() {
            let progress = await engine.add(frame)
            #expect(progress.step.match != .lost)
            committed += progress.step.committedRows
            previewRows += progress.previewDelta.height
            last = progress
        }
        // The preview is 160 px wide, under 360, so its strips are the committed rows one to one.
        #expect(previewRows == committed)

        let scaled = try #require(await engine.finish(scale: 2, colorSpace: sRGB))
        let expectedHeight = page.header + reached + page.bandHeight + page.footer
        #expect(scaled.scale == 2)
        #expect(scaled.image.width == page.width)
        #expect(scaled.image.height == expectedHeight)
        #expect(last?.heightPixels == expectedHeight)

        // The same frames straight through a stitcher: the reference for every column.
        var stitcher = ScrollStitcher(first: frames[0], finder: page.finder)
        for frame in frames.dropFirst() { _ = stitcher.add(frame) }
        let reference = stitcher.finish()

        let png = try ImageEncoder.pngData(from: scaled.image, scale: scaled.scale)
        let decoded = try #require(ImageEncoder.decode(png))
        #expect(decoded.scale == 2)
        #expect(decoded.image.width == reference.width)
        #expect(decoded.image.height == reference.height)
        let pixels = try bgra(of: decoded.image)
        var mismatched = 0
        for i in stride(from: 0, to: reference.bgra.count, by: 4)
        where pixels[i] != reference.bgra[i] || pixels[i + 1] != reference.bgra[i + 1] || pixels[i + 2] != reference.bgra[i + 2] {
            mismatched += 1
        }
        #expect(mismatched == 0)
        // And the page's columns are the ideal page: header, every page row reached, footer.
        let comparison = page.compare(StitchedImage(width: reference.width, height: reference.height, bgra: pixels),
                                      reached: reached)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    @Test func theCapEndsTheStitchAtExactlyTheLimit() async throws {
        var page = SyntheticPage()
        let engine = ScrollStitchEngine(finder: page.finder, maxPixelHeight: 2000)
        await engine.begin(first: page.frame(at: 0, animated: false))
        var offset = 0
        var full: StitchProgress?
        while full == nil, offset < page.maxOffset {
            offset = min(page.maxOffset, offset + 400)
            let progress = await engine.add(page.frame(at: offset, animated: false))
            #expect(progress.heightPixels <= 2000)
            if progress.step.isFull { full = progress }
        }
        #expect(full?.heightPixels == 2000)
        // Frames after the cap change nothing.
        let after = await engine.add(page.frame(at: offset + 300, animated: false))
        #expect(after.step == StitchStep(match: .still, committedRows: 0, isFull: true))
        #expect(after.previewDelta.isEmpty)
        let image = try #require(await engine.finish(scale: 2, colorSpace: sRGB))
        #expect(image.image.height == 2000)
    }

    /// Done with no movement gives the first frame alone; nothing before `begin` and nothing
    /// after `finish`.
    @Test func aLoneFrameFinishesAsItselfAndTheEngineEmpties() async throws {
        var page = SyntheticPage()
        let engine = ScrollStitchEngine(finder: page.finder)
        let before = await engine.finish(scale: 2, colorSpace: sRGB)
        #expect(before == nil)

        let first = page.frame(at: 300, animated: false)
        await engine.begin(first: first)
        let image = try #require(await engine.finish(scale: 1, colorSpace: sRGB))
        #expect(image.scale == 1)
        #expect(image.image.width == page.width)
        #expect(image.image.height == page.height)
        #expect(image.image.colorSpace?.name == CGColorSpace.sRGB)
        let pixels = try bgra(of: image.image)
        #expect(stride(from: 0, to: first.bgra.count, by: 4).allSatisfy { pixels[$0] == first.bgra[$0] })
        let again = await engine.finish(scale: 1, colorSpace: sRGB)
        #expect(again == nil)
    }
}
