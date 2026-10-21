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
