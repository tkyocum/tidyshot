import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import TidyShot

/// Text geometry in image pixels (spec 2.6, Phase 4b). The metrics come from the system font, so
/// the expectations are written in TextLayout's own terms rather than in fixed numbers.
struct TextLayoutTests {
    func box(_ string: String, size: CGFloat = 40) -> TextBox {
        TextBox(id: UUID(), string: string, origin: CGPoint(x: 10, y: 20), fontSize: size,
                color: RGBA(red: 1, green: 0, blue: 0))
    }

    /// A vertical tab stays on its line in `lines(of:)`, so the commit keeps it too.
    @Test func committedStringTrimsNewlinesButNotVerticalTab() {
        #expect(TextLayout.committedString("Hi\n\r\n") == "Hi")
        #expect(TextLayout.committedString("Hi\u{2028}") == "Hi")
        #expect(TextLayout.committedString("Hi\u{0B}") == "Hi\u{0B}")
        #expect(TextLayout.committedString("Hi\u{0B}\n") == "Hi\u{0B}")
        #expect(TextLayout.lines(of: "Hi\u{0B}") == ["Hi\u{0B}"])
        #expect(TextLayout.committedString(" \n") == nil)
    }

    @Test func textFrameGrowsWithLines() {
        let font = TextLayout.font(size: 40)
        let lineHeight = TextLayout.lineHeight(fontSize: 40)
        let padding = TextLayout.padding(fontSize: 40)
        #expect(padding == 10)
        #expect(TextLayout.padding(fontSize: 13) == 4)
        #expect(lineHeight > 40)
        // The line height scales with the size, so text looks the same at every capture scale.
        #expect(abs(lineHeight - 2 * TextLayout.lineHeight(fontSize: 20)) < 0.001)

        let one = TextLayout.frame(for: box("Hi"))
        #expect(one == CGRect(x: 10, y: 20, width: TextLayout.width(of: "Hi", font: font) + 2 * padding,
                              height: lineHeight + 2 * padding))
        let two = TextLayout.frame(for: box("Hi\nthere"))
        #expect(two.origin == one.origin)
        #expect(two.height == 2 * lineHeight + 2 * padding)
        #expect(two.width == TextLayout.width(of: "there", font: font) + 2 * padding)
        #expect(two.width > one.width)
        // Empty lines count, the one after a trailing newline too, as in the text view.
        let trailing = TextLayout.frame(for: box("Hi\n\n"))
        #expect(trailing.height == 3 * lineHeight + 2 * padding)
        #expect(trailing.width == one.width)
        // An empty box still has one line, so the caret has somewhere to go.
        #expect(TextLayout.frame(for: box("")) == CGRect(x: 10, y: 20, width: 2 * padding, height: lineHeight + 2 * padding))
        // Every kind of line break the text view accepts splits a line; nothing wraps.
        #expect(TextLayout.lines(of: "a\r\nb\u{2028}c") == ["a", "b", "c"])
        #expect(TextLayout.lines(of: "a\u{0B}b").count == 1)

        // One baseline per line, a line height apart, round(descent) above the bottom of its line.
        let baselines = TextLayout.baselineOrigins(for: box("Hi\nthere\n"))
        #expect(baselines.count == 3)
        #expect(baselines.allSatisfy { $0.x == 10 + padding })
        let first = 20 + padding + lineHeight - CTFontGetDescent(font).rounded()
        #expect(abs(baselines[0].y - first) < 0.0001)
        #expect(abs(baselines[1].y - baselines[0].y - lineHeight) < 0.0001)
        #expect(abs(baselines[2].y - baselines[1].y - lineHeight) < 0.0001)

        // A click puts the middle of the first line under the pointer, one padding in from the left.
        #expect(TextLayout.origin(forClickAt: CGPoint(x: 50, y: 60), fontSize: 40)
                == CGPoint(x: 50 - padding, y: 60 - padding - lineHeight / 2))
    }
}
