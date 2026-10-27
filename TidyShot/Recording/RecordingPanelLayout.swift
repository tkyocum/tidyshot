import AppKit

/// The recording bar's layout (design, Mute, Bar; R3 design, Bar). The plain bar is 172 × 44 pt:
/// the time, Stop and Cancel. The mute button, or a GIF recording's `GIF` tag before the time, adds
/// a slot of 36 pt, and an area or fullscreen recording's highlights and bubble buttons add two.
/// Each frame is in the bar's points from its top-left corner, so a time past an hour fits every
/// bar.
enum RecordingPanelLayout {
    nonisolated struct Bar: Equatable, Sendable {
        var showsTag: Bool
        var showsMute: Bool
        /// The highlights and bubble buttons, for every area and fullscreen recording.
        var showsOverlayButtons: Bool

        /// R2's three bars, which a window recording still has. An area or fullscreen bar is one
        /// of them with the overlay buttons, and equals none of them.
        static let plain = Bar(showsTag: false, showsMute: false, showsOverlayButtons: false)
        static let mute = Bar(showsTag: false, showsMute: true, showsOverlayButtons: false)
        static let gif = Bar(showsTag: true, showsMute: false, showsOverlayButtons: false)
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
    private static let plainWidth: CGFloat = 172
    private static let slotWidth: CGFloat = 36

    /// A GIF recording has no sound, so never a mute button.
    static func bar(showsMute: Bool, isGIF: Bool, showsOverlayButtons: Bool = false) -> Bar {
        Bar(showsTag: isGIF, showsMute: showsMute && !isGIF, showsOverlayButtons: showsOverlayButtons)
    }

    /// `172 + 36 × slots`: the tag and the mute button are a slot each, the overlay buttons two.
    static func size(of bar: Bar) -> CGSize {
        let slots = (bar.showsTag ? 1 : 0) + (bar.showsMute ? 1 : 0) + (bar.showsOverlayButtons ? 2 : 0)
        return CGSize(width: plainWidth + slotWidth * CGFloat(slots), height: height)
    }

    /// The `GIF` tag, first, in a button's width; nil without the tag.
    static func tagFrame(of bar: Bar) -> CGRect? {
        bar.showsTag ? slot(at: leading) : nil
    }

    /// From the tag, or the bar's leading inset, to the first button.
    static func timeFrame(of bar: Bar) -> CGRect {
        let start = tagFrame(of: bar).map { $0.maxX + spacing } ?? leading
        let end = (highlightsFrame(of: bar) ?? muteFrame(of: bar) ?? stopFrame(of: bar)).minX - spacing
        return CGRect(x: start, y: (height - buttonSide) / 2, width: end - start, height: buttonSide)
    }

    /// After the time, before the bubble button; nil without the overlay buttons.
    static func highlightsFrame(of bar: Bar) -> CGRect? {
        bubbleFrame(of: bar).map { slot(at: $0.minX - spacing - buttonSide) }
    }

    /// Before the mute button, or Stop; nil without the overlay buttons.
    static func bubbleFrame(of bar: Bar) -> CGRect? {
        guard bar.showsOverlayButtons else { return nil }
        return slot(at: (muteFrame(of: bar) ?? stopFrame(of: bar)).minX - spacing - buttonSide)
    }

    /// Before Stop; nil without the mute button.
    static func muteFrame(of bar: Bar) -> CGRect? {
        bar.showsMute ? slot(at: stopFrame(of: bar).minX - spacing - buttonSide) : nil
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
