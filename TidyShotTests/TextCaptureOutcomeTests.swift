import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct TextCaptureOutcomeTests {
    private let box = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05)

    private func text(_ string: String, y: CGFloat = 0.5) -> TextPiece {
        TextPiece(text: string, box: CGRect(x: 0.1, y: y, width: 0.2, height: 0.05))
    }

    private func code(_ payload: String, _ symbology: CodeSymbology = .qr) -> CodePiece {
        CodePiece(payload: payload, symbology: symbology, box: box)
    }

    private func decide(pieces: [TextPiece] = [], codes: [CodePiece] = []) -> TextCaptureOutcome {
        TextCaptureOutcome.decide(TextScan(pieces: pieces, codes: codes))
    }

    @Test func codesWinOverText() {
        let outcome = decide(pieces: [text("Scan me")], codes: [code("https://example.com/a")])
        #expect(outcome.clipboard == "https://example.com/a")
    }

    @Test func severalCodesAreJoinedByNewlineInOrder() {
        let outcome = decide(codes: [code("one"), code("two"), code("three")])
        #expect(outcome.clipboard == "one\ntwo\nthree")
    }

    @Test func aDuplicatePayloadIsKeptOnce() {
        let outcome = decide(codes: [code("one"), code("two"), code("one")])
        #expect(outcome.clipboard == "one\ntwo")
        #expect(outcome.title == "2 codes copied")
    }

    @Test func aPayloadRepeatedIsStillASingleCode() {
        let outcome = decide(codes: [code("https://example.com"), code("https://example.com")])
        #expect(outcome.title == "QR code copied")
        #expect(outcome.openURL == URL(string: "https://example.com"))
    }

    @Test func anEmptyPayloadIsIgnored() {
        let outcome = decide(pieces: [text("hello")], codes: [code("")])
        #expect(outcome.clipboard == "hello")
        #expect(outcome.title == "Text copied")
        let mixed = decide(codes: [code(""), code("kept")])
        #expect(mixed.clipboard == "kept")
        #expect(mixed.title == "QR code copied")
    }

    @Test func textOnly() {
        let outcome = decide(pieces: [text("first line", y: 0.8), text("second line", y: 0.7)])
        #expect(outcome.clipboard == "first line\nsecond line")
        #expect(outcome.title == "Text copied")
        #expect(outcome.body == "first line")
        #expect(outcome.openURL == nil)
    }

    @Test func nothing() {
        let outcome = decide()
        #expect(outcome.clipboard == nil)
        #expect(outcome.title == "No text found")
        #expect(outcome.body == "TidyShot found no text or QR code in the selection.")
        #expect(outcome.openURL == nil)
    }

    @Test func textThatTrimsToNothingIsNothing() {
        let outcome = decide(pieces: [text("  "), text("")])
        #expect(outcome.clipboard == nil)
        #expect(outcome.title == "No text found")
    }

    @Test func eachNotificationTitle() {
        #expect(decide(codes: [code("a", .qr)]).title == "QR code copied")
        #expect(decide(codes: [code("a", .microQR)]).title == "QR code copied")
        #expect(decide(codes: [code("a", .aztec)]).title == "Code copied")
        #expect(decide(codes: [code("a", .dataMatrix)]).title == "Code copied")
        #expect(decide(codes: [code("a", .pdf417)]).title == "Code copied")
        #expect(decide(codes: [code("a"), code("b"), code("c")]).title == "3 codes copied")
        #expect(decide(pieces: [text("a")]).title == "Text copied")
    }

    @Test func theBodyOfSeveralCodesIsTheFirstPayload() {
        #expect(decide(codes: [code("first"), code("second")]).body == "first")
    }

    @Test func theBodyIsCutAtEightyCharactersWithAnEllipsis() {
        #expect(TextCaptureOutcome.previewLimit == 80)
        let eighty = String(repeating: "a", count: 80)
        #expect(TextCaptureOutcome.preview(eighty) == eighty)
        #expect(TextCaptureOutcome.preview(eighty + "b") == eighty + "…")
        let outcome = decide(pieces: [text(String(repeating: "x", count: 200))])
        #expect(outcome.body == String(repeating: "x", count: 80) + "…")
    }

    @Test func theBodyIsTheFirstLineOnly() {
        #expect(TextCaptureOutcome.preview("one\ntwo\nthree") == "one")
        #expect(TextCaptureOutcome.preview("one\r\ntwo") == "one")
        #expect(TextCaptureOutcome.preview("\n  lead\nnext") == "lead")
        let longSecond = "short\n" + String(repeating: "y", count: 200)
        #expect(TextCaptureOutcome.preview(longSecond) == "short")
    }

    @Test func theURLToOpenIsOnlyForASingleWebPayloadWithAHost() {
        #expect(decide(codes: [code("https://snap.tky.io/2BkqQ.png")]).openURL == URL(string: "https://snap.tky.io/2BkqQ.png"))
        #expect(decide(codes: [code("http://example.com")]).openURL == URL(string: "http://example.com"))
        #expect(decide(codes: [code("javascript:alert(1)")]).openURL == nil)
        #expect(decide(codes: [code("file:///etc/passwd")]).openURL == nil)
        #expect(decide(codes: [code("mailto:a@example.com")]).openURL == nil)
        #expect(decide(codes: [code("https://")]).openURL == nil)
        #expect(decide(codes: [code("just words")]).openURL == nil)
        #expect(decide(codes: [code("https://a.example"), code("https://b.example")]).openURL == nil)
    }

    @Test func theURLAlsoOpensFromADifferentSymbology() {
        #expect(decide(codes: [code("https://example.com", .dataMatrix)]).openURL == URL(string: "https://example.com"))
    }

    @Test func textThatLooksLikeAURLOpensNothing() {
        #expect(decide(pieces: [text("https://example.com")]).openURL == nil)
    }
}
