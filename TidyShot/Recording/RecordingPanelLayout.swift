import AppKit

/// The recording bar's layout (design, Mute, Bar). The plain bar is 172 × 44 pt: the time, Stop
/// and Cancel. With the mute button it is 208 × 44, and a GIF recording's bar is 208 × 44 too,
/// with the `GIF` tag before the time in the mute button's width. Each frame is in the bar's
/// points from its top-left corner, so a time past an hour fits every bar.
enum RecordingPanelLayout {
    nonisolated enum Bar: Equatable, Sendable {
        case plain
        case mute
        case gif
    }

    /// The elapsed time's font: 15 pt medium with monospaced digits.
    static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .medium)
    /// The `GIF` tag's font, and the space each side of its label inside its border.
    static let tagFont = NSFont.systemFont(ofSize: 10, weight: .bold)
    static let tagPadding: CGFloat = 3

    private static let height: CGFloat = 44
    private static let buttonSide: CGFloat = 28
    private static let spacing: CGFloat = 6
    private static let leading: CGFloat = 16
    private static let trailing: CGFloat = 8

    /// A GIF recording has no sound, so never a mute button.
    static func bar(showsMute: Bool, isGIF: Bool) -> Bar {
        if isGIF { return .gif }
        return showsMute ? .mute : .plain
    }

    static func size(of bar: Bar) -> CGSize {
        CGSize(width: bar == .plain ? 172 : 208, height: height)
    }

    /// The `GIF` tag, first, in a button's width; nil but for the GIF bar.
    static func tagFrame(of bar: Bar) -> CGRect? {
        bar == .gif ? slot(at: leading) : nil
    }

    /// From the tag, or the bar's leading inset, to the first button.
    static func timeFrame(of bar: Bar) -> CGRect {
        let start = tagFrame(of: bar).map { $0.maxX + spacing } ?? leading
        let end = (muteFrame(of: bar) ?? stopFrame(of: bar)).minX - spacing
        return CGRect(x: start, y: (height - buttonSide) / 2, width: end - start, height: buttonSide)
    }

    /// Before Stop; nil but for the mute bar.
    static func muteFrame(of bar: Bar) -> CGRect? {
        bar == .mute ? slot(at: stopFrame(of: bar).minX - spacing - buttonSide) : nil
    }

    static func stopFrame(of bar: Bar) -> CGRect {
        slot(at: cancelFrame(of: bar).minX - spacing - buttonSide)
    }

    static func cancelFrame(of bar: Bar) -> CGRect {
        slot(at: size(of: bar).width - trailing - buttonSide)
    }

    /// A button's square, centred top to bottom.
    private static func slot(at x: CGFloat) -> CGRect {
        CGRect(x: x, y: (height - buttonSide) / 2, width: buttonSide, height: buttonSide)
    }
}
