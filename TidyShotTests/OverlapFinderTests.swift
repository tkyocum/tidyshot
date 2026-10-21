import Foundation
import Testing
@testable import TidyShot

struct OverlapFinderTests {
    /// The finder's verdict for a viewer scrolled from offset `a` to offset `b`.
    func match(_ page: inout SyntheticPage, from a: Int, to b: Int, predicted: Int? = nil,
               animated: Bool = true) -> OverlapMatch {
        let before = page.frame(at: a, animated: animated)
        let after = page.frame(at: b, animated: animated)
        return page.finder.find(previous: before, current: after, predicted: predicted)
    }

    func dy(of match: OverlapMatch) -> Int? {
        if case .moved(let dy, _, _, _) = match { return dy }
        return nil
    }

    @Test func findsTheExactShiftForStepsFromOneRowToNearlyTheBand() {
        var page = SyntheticPage()
        // 462 is 60 % of the 770 row band, 754 leaves 16 rows of overlap. That overlap has to hold
        // text, which the page does at offset 400 (blank stretches would make the pair lost).
        for step in [1, 3, 40, 462, page.bandHeight - 16] {
            let result = match(&page, from: 400, to: 400 + step)
            #expect(dy(of: result) == step, "step \(step) gave \(result)")
        }
    }

    @Test func identicalFramesAreStill() {
        var page = SyntheticPage()
        #expect(match(&page, from: 800, to: 800, animated: false) == .still)
    }

    /// A spinner, caret or GIF must not read as movement, and must not make the pair lost.
    @Test func framesDifferingOnlyInTheAnimatedSquareAreStill() {
        var page = SyntheticPage()
        #expect(match(&page, from: 800, to: 800, animated: true) == .still)
    }

    @Test func measuresTheStickyHeaderAndFooter() {
        var page = SyntheticPage()
        guard case .moved(let dy, let top, let bandEnd, let score) = match(&page, from: 600, to: 700) else {
            Issue.record("not moved")
            return
        }
        #expect(dy == 100)
        #expect(top == page.header)
        #expect(bandEnd == page.height - page.footer)
        #expect(score >= 0.8)
    }

    @Test func aWideFixedSidebarIsIgnored() {
        var page = SyntheticPage(width: 260, sidebar: 140)
        #expect(dy(of: match(&page, from: 600, to: 640)) == 40)
        #expect(dy(of: match(&page, from: 600, to: 1062)) == 462)
    }

    /// The scrollbar's columns are never hashed, so a thumb that moved with no content change is still.
    @Test func scrollbarThumbMovementIsIgnored() {
        var page = SyntheticPage()
        let before = page.frame(at: 800, animated: false, thumbTop: 40)
        let after = page.frame(at: 800, animated: false, thumbTop: 120)
        #expect(before.gray != after.gray)
        #expect(page.finder.find(previous: before, current: after, predicted: nil) == .still)
    }

    /// Rows that repeat every 230 rows (a 900 row band holds each at most four times): a shift of
    /// 115 matches as +115 and as -115 with equal votes, and the prediction (or, without one, the
    /// forward direction) picks between them.
    @Test func repeatedContentIsResolvedByThePrediction() {
        var page = SyntheticPage(header: 0, footer: 0, sidebar: 0, scrollbar: 0, period: 230)
        #expect(dy(of: match(&page, from: 0, to: 115, predicted: 115, animated: false)) == 115)
        #expect(dy(of: match(&page, from: 0, to: 115, predicted: -115, animated: false)) == -115)
        #expect(dy(of: match(&page, from: 0, to: 115, predicted: nil, animated: false)) == 115)
    }

    @Test func aStepLargerThanTheBandIsLost() {
        var page = SyntheticPage()
        #expect(match(&page, from: 600, to: 1500) == .lost)
    }

    @Test func scrollingBackUpGivesANegativeShift() {
        var page = SyntheticPage()
        #expect(dy(of: match(&page, from: 700, to: 550)) == -150)
    }

    @Test func anAllBlankPairIsStill() {
        let page = SyntheticPage()
        #expect(page.finder.find(previous: page.blankFrame(), current: page.blankFrame(), predicted: nil) == .still)
    }

    /// Sticky chrome is equal in both frames whatever happened, so it must not count towards the
    /// still test: a real 20 row scroll over a sparse band (about 10 informative rows between 80
    /// header and 50 footer rows) is movement, not stillness.
    @Test func aSmallScrollOfASparsePageUnderTallFixedChromeIsNotStill() {
        let width = 40, height = 400, header = 80, footer = 50
        let band = height - header - footer
        // Page rows 60..<70 are the only informative ones; every other page row is blank.
        func page(_ row: Int) -> [UInt8] {
            (0..<width).map { x in
                (60..<70).contains(row) ? UInt8((x * (row - 40) + row * 29) % 200) : 250
            }
        }
        func frame(offset: Int) -> ScrollFrame {
            var bgra = [UInt8]()
            bgra.reserveCapacity(width * height * 4)
            for y in 0..<height {
                let row: [UInt8]
                if y < header { row = (0..<width).map { UInt8(100 + ($0 * 7 + y * 13) % 120) } }
                else if y >= height - footer { row = (0..<width).map { UInt8(60 + ($0 * 11 + y * 5) % 90) } }
                else { row = page(offset + y - header) }
                for v in row { bgra += [v, v, v, 255] }
            }
            return ScrollFrame(bgra: Data(bgra), width: width, height: height, bytesPerRow: width * 4)
        }
        #expect(band == 270)
        let finder = OverlapFinder(scrollbarColumns: 0)
        let result = finder.find(previous: frame(offset: 40), current: frame(offset: 60), predicted: nil)
        #expect(dy(of: result) == 20, "gave \(result)")
        #expect(finder.find(previous: frame(offset: 40), current: frame(offset: 40), predicted: nil) == .still)
    }

    /// A column of text no wider than two stripes is all that moves: the rest of the band is blank.
    /// That is a scroll, not an animation, at any step; a noise spinner elsewhere changes nothing.
    @Test func aScrollOfANarrowColumnIsNotStill() {
        let width = 320, height = 300, header = 30, footer = 20, column = 0..<70
        func pageRow(_ r: Int) -> [UInt8] {
            (0..<width).map { x in
                column.contains(x) && r % 24 > 4 && r % 24 < 18 ? UInt8((x * 3 + r * 29 + r / 24 * 7) % 200) : 250
            }
        }
        func frame(offset: Int, spinner seed: UInt64? = nil) -> ScrollFrame {
            var noise = SyntheticPage.LCG(seed: seed ?? 0)
            var bgra = [UInt8]()
            bgra.reserveCapacity(width * height * 4)
            for y in 0..<height {
                var row = y < header ? (0..<width).map { UInt8(100 + ($0 * 7 + y * 13) % 120) }
                    : y >= height - footer ? (0..<width).map { UInt8(60 + ($0 * 11 + y * 5) % 90) }
                    : pageRow(offset + y - header)
                if seed != nil, (120..<160).contains(y) {
                    for x in 200..<224 { row[x] = UInt8(truncatingIfNeeded: noise.next()) }
                }
                for v in row { bgra += [v, v, v, 255] }
            }
            return ScrollFrame(bgra: Data(bgra), width: width, height: height, bytesPerRow: width * 4)
        }
        let finder = OverlapFinder(scrollbarColumns: 0)
        for step in [3, 20, 90] {
            let result = finder.find(previous: frame(offset: 100), current: frame(offset: 100 + step), predicted: nil)
            #expect(dy(of: result) == step, "step \(step) gave \(result)")
        }
        for step in [3, 20] {
            let result = finder.find(previous: frame(offset: 100, spinner: 1),
                                     current: frame(offset: 100 + step, spinner: 2), predicted: nil)
            #expect(dy(of: result) == step, "step \(step) with a spinner gave \(result)")
        }
        #expect(finder.find(previous: frame(offset: 100), current: frame(offset: 100), predicted: nil) == .still)
        #expect(finder.find(previous: frame(offset: 100, spinner: 1), current: frame(offset: 100, spinner: 2),
                            predicted: nil) == .still)
    }

    @Test func framesOfDifferentSizesAreLost() {
        var page = SyntheticPage()
        var other = SyntheticPage(height: 880)
        let result = page.finder.find(previous: page.frame(at: 0), current: other.frame(at: 0), predicted: nil)
        #expect(result == .lost)
    }

    @Test func scaleSetsTheScrollbarStrip() {
        #expect(OverlapFinder(scale: 2).scrollbarColumns == 32)
        #expect(OverlapFinder(scale: 1).scrollbarColumns == 16)
    }
}
