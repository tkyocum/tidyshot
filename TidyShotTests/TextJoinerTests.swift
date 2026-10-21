import CoreGraphics
import Testing
@testable import TidyShot

struct TextJoinerTests {
    private func piece(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 0.2, height: CGFloat = 0.05) -> TextPiece {
        TextPiece(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func twoPiecesOnOneLineAreJoinedBySpace() {
        let pieces = [piece("Column A", x: 0.1, y: 0.5), piece("Column B", x: 0.5, y: 0.5)]
        #expect(TextJoiner.join(pieces) == "Column A Column B")
    }

    @Test func linesAreJoinedByNewline() {
        let pieces = [piece("first", x: 0.1, y: 0.8), piece("second", x: 0.1, y: 0.7), piece("third", x: 0.1, y: 0.6)]
        #expect(TextJoiner.join(pieces) == "first\nsecond\nthird")
    }

    @Test func aPieceLeftOfThePreviousOneOnAnOverlappingBandStartsANewLine() {
        let pieces = [piece("right", x: 0.5, y: 0.5), piece("left", x: 0.1, y: 0.5)]
        #expect(TextJoiner.join(pieces) == "right\nleft")
    }

    @Test func emptyPiecesAreSkipped() {
        let pieces = [piece("one", x: 0.1, y: 0.8), piece("  \n", x: 0.1, y: 0.7), piece("", x: 0.5, y: 0.8), piece("two", x: 0.1, y: 0.6)]
        #expect(TextJoiner.join(pieces) == "one\ntwo")
    }

    @Test func aSkippedPieceDoesNotBreakALine() {
        let pieces = [piece("a", x: 0.1, y: 0.5), piece(" ", x: 0.3, y: 0.5), piece("b", x: 0.5, y: 0.5)]
        #expect(TextJoiner.join(pieces) == "a b")
    }

    @Test func theResultIsTrimmed() {
        let pieces = [piece("  padded \n", x: 0.1, y: 0.5)]
        #expect(TextJoiner.join(pieces) == "padded")
    }

    @Test func aSinglePiece() {
        #expect(TextJoiner.join([piece("alone", x: 0.1, y: 0.5)]) == "alone")
    }

    @Test func noPiecesGiveAnEmptyString() {
        #expect(TextJoiner.join([]) == "")
    }

    @Test func verticalOverlapOfExactlyHalfContinuesTheLine() {
        // Both boxes are 0.25 high; the second overlaps the first by 0.125, exactly half.
        let pieces = [
            TextPiece(text: "a", box: CGRect(x: 0.0, y: 0.5, width: 0.25, height: 0.25)),
            TextPiece(text: "b", box: CGRect(x: 0.5, y: 0.625, width: 0.25, height: 0.25)),
        ]
        #expect(TextJoiner.join(pieces) == "a b")
    }

    @Test func verticalOverlapJustUnderHalfStartsANewLine() {
        let pieces = [
            TextPiece(text: "a", box: CGRect(x: 0.0, y: 0.5, width: 0.25, height: 0.25)),
            TextPiece(text: "b", box: CGRect(x: 0.5, y: 0.640625, width: 0.25, height: 0.25)),
        ]
        #expect(TextJoiner.join(pieces) == "a\nb")
    }

    @Test func overlapIsMeasuredAgainstTheSmallerHeight() {
        // The short piece sits wholly inside the tall one: overlap 0.05 is all of the smaller height.
        let pieces = [
            TextPiece(text: "tall", box: CGRect(x: 0.0, y: 0.5, width: 0.25, height: 0.5)),
            TextPiece(text: "short", box: CGRect(x: 0.5, y: 0.6, width: 0.25, height: 0.05)),
        ]
        #expect(TextJoiner.join(pieces) == "tall short")
    }

    @Test func aLeftEdgeExactlyPointZeroOneLeftOfThePreviousRightEdgeContinuesTheLine() {
        let pieces = [
            TextPiece(text: "a", box: CGRect(x: 0.25, y: 0.5, width: 0.25, height: 0.05)),
            TextPiece(text: "b", box: CGRect(x: 0.5 - 0.01, y: 0.5, width: 0.25, height: 0.05)),
        ]
        #expect(TextJoiner.join(pieces) == "a b")
    }

    @Test func aLeftEdgeMoreThanPointZeroOneLeftStartsANewLine() {
        let pieces = [
            TextPiece(text: "a", box: CGRect(x: 0.25, y: 0.5, width: 0.25, height: 0.05)),
            TextPiece(text: "b", box: CGRect(x: 0.5 - 0.011, y: 0.5, width: 0.25, height: 0.05)),
        ]
        #expect(TextJoiner.join(pieces) == "a\nb")
    }
}
