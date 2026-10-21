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
    /// The bold system font, so text reads on busy screenshots. CTFont is toll-free bridged to
    /// NSFont, so the text view uses the same font (`as NSFont`).
    static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    /// Space between the frame and the glyphs on every side, a quarter of the size rounded up.
    /// It holds the glyphs' overhang and gives a click on the text some room.
    static func padding(fontSize: CGFloat) -> CGFloat {
        (fontSize / 4).rounded(.up)
    }

    /// The distance between baselines.
    static func lineHeight(fontSize: CGFloat) -> CGFloat {
        let font = font(size: fontSize)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// From the top of a line to its baseline: TextKit 2 sets the baseline of a fixed-height line
    /// `round(descent)` above the line's bottom.
    static func baselineOffset(fontSize: CGFloat) -> CGFloat {
        lineHeight(fontSize: fontSize) - CTFontGetDescent(font(size: fontSize)).rounded()
    }

    /// The lines of `string`, split at every newline character (LF, CR, CRLF, U+2028, U+2029). An
    /// empty string, or the end after a trailing newline, is an empty line.
    static func lines(of string: String) -> [String] {
        string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
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
        let font = font(size: box.fontSize)
        let lines = lines(of: box.string)
        let widest = lines.map { width(of: $0, font: font) }.max() ?? 0
        let padding = padding(fontSize: box.fontSize)
        return CGRect(x: box.origin.x, y: box.origin.y, width: widest + 2 * padding,
                      height: CGFloat(lines.count) * lineHeight(fontSize: box.fontSize) + 2 * padding)
    }

    /// Where each line starts on its baseline, one per line of `lines(of:)`.
    static func baselineOrigins(for box: TextBox) -> [CGPoint] {
        let padding = padding(fontSize: box.fontSize)
        let lineHeight = lineHeight(fontSize: box.fontSize)
        let first = box.origin.y + padding + baselineOffset(fontSize: box.fontSize)
        return lines(of: box.string).indices.map { index in
            CGPoint(x: box.origin.x + padding, y: first + CGFloat(index) * lineHeight)
        }
    }

    /// The origin of a new box clicked at `point`: the middle of its first line under the
    /// pointer, the text starting at the pointer.
    static func origin(forClickAt point: CGPoint, fontSize: CGFloat) -> CGPoint {
        let padding = padding(fontSize: fontSize)
        return CGPoint(x: point.x - padding, y: point.y - padding - lineHeight(fontSize: fontSize) / 2)
    }

    /// What a commit stores: the typed text without trailing newlines, or nil when nothing but
    /// whitespace was typed.
    static func committedString(_ typed: String) -> String? {
        guard typed.contains(where: { !$0.isWhitespace }) else { return nil }
        var string = typed
        while let last = string.last, last.isNewline {
            string.removeLast()
        }
        return string
    }
}
