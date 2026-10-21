import Foundation
import Testing
@testable import TidyShot

struct ScrollStitcherTests {
    struct Run {
        var image: StitchedImage
        var reached: Int
        var frames: Int
        var moved = 0, still = 0, lost = 0, backwards = 0
    }

    /// Drives a viewer through `steps` (rows scrolled between frames, clamped to the page) and
    /// finishes. The viewer starts at offset 0.
    func run(_ page: inout SyntheticPage, steps: [Int], animated: Bool = true, scrollbarVisible: Bool = true,
             maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight) -> Run {
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: animated, scrollbarVisible: scrollbarVisible),
                                      maxPixelHeight: maxPixelHeight, finder: page.finder)
        var offset = 0
        var counts = (moved: 0, still: 0, lost: 0, backwards: 0)
        for step in steps {
            offset = max(0, min(page.maxOffset, offset + step))
            let result = stitcher.add(page.frame(at: offset, animated: animated, scrollbarVisible: scrollbarVisible))
            switch result.match {
            case .still: counts.still += 1
            case .lost: counts.lost += 1
            case .moved(let dy, _, _, _): if dy > 0 { counts.moved += 1 } else { counts.backwards += 1 }
            }
        }
        let image = stitcher.finish()
        return Run(image: image, reached: offset, frames: steps.count + 1, moved: counts.moved, still: counts.still,
                   lost: counts.lost, backwards: counts.backwards)
    }

    /// The stitched image equals header + page + footer, apart from the animated square.
    func expectExact(_ run: Run, _ page: SyntheticPage, animated: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        let comparison = page.compare(run.image, reached: run.reached)
        #expect(comparison.actualHeight == comparison.expectedHeight, sourceLocation: sourceLocation)
        #expect(comparison.mismatchedOutsideSpinner == 0, sourceLocation: sourceLocation)
        let allowed = animated ? page.spinnerWidth * page.spinnerHeight * run.frames : 0
        #expect(comparison.mismatched <= allowed, "\(comparison.mismatched) mismatched", sourceLocation: sourceLocation)
    }

    // MARK: The probe's five scenarios, with the probe's steps

    /// Auto mode: 60 % of the band per step down to the end, then still frames.
    @Test func autoSixtyPercentStepsToTheEnd() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 462, count: 20) + [0, 0])
        #expect(result.reached == page.maxOffset)
        #expect(result.lost == 0)
        #expect(result.still >= 2)
        expectExact(result, page, animated: true)
    }

    /// Manual mode: irregular small and large steps, a scroll back up and a momentum tail.
    @Test func manualIrregularStepsWithAScrollBack() {
        var page = SyntheticPage()
        let steps = [12, 40, 90, 180, 300, 420, 500, 380, 200, 90, 30, 6, 2, 0, -150, 60, 200, 400, 600, 640, 300, 100, 20, 0]
        let result = run(&page, steps: steps)
        #expect(result.lost == 0)
        #expect(result.backwards >= 1)
        expectExact(result, page, animated: true)
    }

    /// One jump larger than the band loses the place; scrolling back into overlap recovers against
    /// the last accepted frame and nothing is missing.
    @Test func tooFastThenRecover() {
        var page = SyntheticPage()
        let result = run(&page, steps: [300, 300, 900, -500, 200, 300])
        #expect(result.lost == 1)
        #expect(result.reached == 1500)
        expectExact(result, page, animated: true)
    }

    @Test func plainPageWithNoScrollbarAndNoSpinner() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 500, count: 18), animated: false, scrollbarVisible: false)
        #expect(result.lost == 0)
        expectExact(result, page, animated: false)
    }

    /// Smooth scrolling caught mid-animation: thirty steps of 1 row and thirty of 3.
    @Test func tinySteps() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 1, count: 30) + Array(repeating: 3, count: 30))
        #expect(result.lost == 0)
        #expect(result.reached == 120)
        expectExact(result, page, animated: true)
    }

    // MARK: Edge cases

    @Test func aSingleFrameFinishesAsItself() {
        var page = SyntheticPage()
        let first = page.frame(at: 400, animated: false)
        var stitcher = ScrollStitcher(first: first, finder: page.finder)
        #expect(stitcher.committedHeight == 0)
        let image = stitcher.finish()
        #expect(image.width == page.width)
        #expect(image.height == page.height)
        #expect(image.bgra == first.bgra)
        #expect(stitcher.committedHeight == page.height)
    }

    @Test func stillAndLostFramesCommitNothing() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), finder: page.finder)
        let still = stitcher.add(page.frame(at: 0, animated: false))
        #expect(still == StitchStep(match: .still, committedRows: 0, isFull: false))
        let lost = stitcher.add(page.frame(at: 2100, animated: false))
        #expect(lost == StitchStep(match: .lost, committedRows: 0, isFull: false))
        #expect(stitcher.committedHeight == 0)
        // Back inside the overlap: the first forward move commits the first frame's rows to its band end.
        let moved = stitcher.add(page.frame(at: 300, animated: false))
        #expect(moved.committedRows == page.height - page.footer)
        #expect(stitcher.committedHeight == page.height - page.footer)
    }

    /// The footer is the last frame's and appears once, at the very end.
    @Test func theFooterAppearsOnce() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 462, count: 20), animated: false)
        let image = result.image
        func rowMatchesFooter(_ y: Int, footerRow k: Int) -> Bool {
            (page.sidebar..<(page.width - page.scrollbar)).allSatisfy {
                SyntheticPage.value(image, $0, y) == page.footerPixel($0, page.height - page.footer + k)
            }
        }
        let firstFooterRow = image.height - page.footer
        for k in 0..<page.footer { #expect(rowMatchesFooter(firstFooterRow + k, footerRow: k)) }
        // No row above the footer is a footer row, so no pair committed one in the middle.
        #expect((0..<firstFooterRow).allSatisfy { !rowMatchesFooter($0, footerRow: 0) })
    }

    @Test func outputStopsAtTheCapExactly() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), maxPixelHeight: 2000, finder: page.finder)
        var offset = 0
        var fullAt: Int?
        for i in 0..<12 {
            offset += 462
            let step = stitcher.add(page.frame(at: offset, animated: false))
            #expect(stitcher.committedHeight <= 2000)
            if step.isFull, fullAt == nil { fullAt = i }
        }
        #expect(stitcher.isFull)
        #expect(stitcher.committedHeight == 2000)
        #expect(fullAt != nil)
        // Frames after the cap are ignored.
        let after = stitcher.add(page.frame(at: offset + 462, animated: false))
        #expect(after == StitchStep(match: .still, committedRows: 0, isFull: true))
        let image = stitcher.finish()
        #expect(image.height == 2000)
        #expect(image.bgra.count == 2000 * page.width * 4)
        // The 2000 rows are the top of the ideal image.
        let comparison = page.compare(image, reached: 2000)
        #expect(comparison.mismatched == 0)
    }

    @Test func aCapShorterThanTheFirstFrameCutsIt() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), maxPixelHeight: 100, finder: page.finder)
        let image = stitcher.finish()
        #expect(image.height == 100)
        #expect(stitcher.isFull)
    }

    // MARK: Preview

    @Test func previewRowsAreTheBoxAverageOfWhatWasCommittedSinceTheLastCall() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), finder: page.finder)
        #expect(stitcher.previewRows(maxWidth: 40).isEmpty)
        _ = stitcher.add(page.frame(at: 462, animated: false))
        let first = stitcher.previewRows(maxWidth: 40)
        #expect(first.width == 40)
        #expect(first.height == stitcher.committedHeight / 4)
        #expect(stitcher.previewRows(maxWidth: 40).isEmpty)
        _ = stitcher.add(page.frame(at: 924, animated: false))
        let second = stitcher.previewRows(maxWidth: 40)
        let committed = stitcher.committedHeight
        #expect(first.height + second.height == committed / 4)

        // Compare with the average of the same 4 by 4 boxes of the finished image.
        var copy = stitcher
        let image = copy.finish()
        func average(_ ox: Int, _ oy: Int, channel: Int) -> UInt8 {
            var sum = 0
            for fy in 0..<4 { for fx in 0..<4 { sum += Int(image.bgra[((oy * 4 + fy) * image.width + ox * 4 + fx) * 4 + channel]) } }
            return UInt8((sum + 8) / 16)
        }
        for (ox, oy) in [(0, 0), (37, 5), (39, first.height - 1)] {
            for channel in 0..<4 {
                #expect(first.bgra[(oy * first.width + ox) * 4 + channel] == average(ox, oy, channel: channel))
            }
        }
        for (ox, oy) in [(0, 0), (20, second.height - 1)] {
            for channel in 0..<4 {
                #expect(second.bgra[(oy * second.width + ox) * 4 + channel] == average(ox, first.height + oy, channel: channel))
            }
        }
    }

    @Test func previewIsACopyWhenTheFrameIsNarrow() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), finder: page.finder)
        let strip = stitcher.previewRows(maxWidth: page.width)
        #expect(strip.isEmpty)
        #expect(strip.width == page.width)
        _ = stitcher.add(page.frame(at: 100, animated: false))
        let rows = stitcher.previewRows(maxWidth: page.width)
        #expect(rows.width == page.width)
        #expect(rows.height == stitcher.committedHeight)
    }
}
