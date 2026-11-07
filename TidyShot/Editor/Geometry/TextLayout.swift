import CoreGraphics
import CoreText
import Foundation

/// Where a text annotation's lines sit, in image pixels with a top-left origin. AnnotationDrawing
/// draws committed text from these numbers with CoreText, and CanvasView's NSTextView lays out the
/// text being typed by the same rules, so the text does not move on commit and the export equals
/// the preview:
/// - one font, `font(size:)` at the box's `fontSize`. The text view's bounds are in image pixels
///   and only its frame is zoomed, so TextKit never sees a zoomed point size (the system font
///   tracks differently at different sizes);
/// - lines split at newlines only, never wrapped, so the frame grows with the text;
/// - a fixed line height of ascent + descent + leading, set on the text view as its paragraph
///   style's minimum and maximum line height;
/// - each baseline `round(descent)` above the bottom of its line, which is where TextKit 2 puts it;
/// - `padding` on every side: the text view's `textContainerInset`, with no line fragment padding.
/// Measured on macOS 27: the NSTextView (TextKit 2) and `CTLineDraw` give the same pixels from
/// 25 % to 400 % zoom.
nonisolated enum TextLayout {
    /// The font and the measures that follow from one size, resolved once: a frame, its baselines
    /// and a draw each need them all, and `font(size:)` is a lookup each time.
    struct Metrics {
        let font: CTFont
        /// Space between the frame and the glyphs on every side, a quarter of the size rounded up.
        /// It holds the glyphs' overhang and gives a click on the text some room.
        let padding: CGFloat
        /// The distance between baselines: ascent + descent + leading.
        let lineHeight: CGFloat
        /// From the top of a line to its baseline: TextKit 2 sets the baseline of a fixed-height
        /// line `round(descent)` above the line's bottom.
        let baselineOffset: CGFloat

        init(fontSize: CGFloat) {
            font = TextLayout.font(size: fontSize)
            padding = (fontSize / 4).rounded(.up)
            lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
            baselineOffset = lineHeight - CTFontGetDescent(font).rounded()
        }
    }

    /// The bold system font, so text reads on busy screenshots. CTFont is toll-free bridged to
    /// NSFont, so the text view uses the same font (`as NSFont`).
    static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    static func padding(fontSize: CGFloat) -> CGFloat {
        Metrics(fontSize: fontSize).padding
    }

    static func lineHeight(fontSize: CGFloat) -> CGFloat {
        Metrics(fontSize: fontSize).lineHeight
    }

    static func baselineOffset(fontSize: CGFloat) -> CGFloat {
        Metrics(fontSize: fontSize).baselineOffset
    }

    /// The lines of `string`, split at every newline character (LF, CR, CRLF, U+2028, U+2029). An
    /// empty string, or the end after a trailing newline, is an empty line. U+000B (vertical tab) is
    /// `isNewline` in Swift but TextKit 2 keeps it on its line, so it does not split here.
    static func lines(of string: String) -> [String] {
        string.split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline && $0 != "\u{0B}" }).map(String.init)
    }

    /// One line in `font` and `color`, made on each call and never stored.
    static func line(_ text: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// The typographic width of one line, trailing spaces included, as the caret sees it.
    static func width(of text: String, font: CTFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return CGFloat(CTLineGetTypographicBounds(line(text, font: font, color: CGColor(gray: 0, alpha: 1)), nil, nil, nil))
    }

    /// The box's frame: the widest line and one line height per line, plus `padding` on every side.
    static func frame(for box: TextBox) -> CGRect {
        let metrics = Metrics(fontSize: box.fontSize)
        let lines = lines(of: box.string)
        let widest = lines.map { width(of: $0, font: metrics.font) }.max() ?? 0
        return CGRect(x: box.origin.x, y: box.origin.y, width: widest + 2 * metrics.padding,
                      height: CGFloat(lines.count) * metrics.lineHeight + 2 * metrics.padding)
    }

    /// Where each line starts on its baseline, one per line of `lines(of:)`. `metrics` are the
    /// box's, when the caller already has them.
    static func baselineOrigins(for box: TextBox, metrics: Metrics? = nil) -> [CGPoint] {
        let metrics = metrics ?? Metrics(fontSize: box.fontSize)
        let first = box.origin.y + metrics.padding + metrics.baselineOffset
        return lines(of: box.string).indices.map { index in
            CGPoint(x: box.origin.x + metrics.padding, y: first + CGFloat(index) * metrics.lineHeight)
        }
    }

    /// The origin of a new box clicked at `point`: the middle of its first line under the
    /// pointer, the text starting at the pointer.
    static func origin(forClickAt point: CGPoint, fontSize: CGFloat) -> CGPoint {
        let metrics = Metrics(fontSize: fontSize)
        return CGPoint(x: point.x - metrics.padding, y: point.y - metrics.padding - metrics.lineHeight / 2)
    }

    /// What a commit stores: the typed text without trailing newlines, or nil when nothing but
    /// whitespace was typed. A vertical tab is not a newline here, matching `lines(of:)`.
    static func committedString(_ typed: String) -> String? {
        guard typed.contains(where: { !$0.isWhitespace }) else { return nil }
        var string = typed
        while let last = string.last, last.isNewline, last != "\u{0B}" {
            string.removeLast()
        }
        return string
    }
}
