import CoreGraphics

/// What a mouse-up in the selection overlay means, for each mode. Pure, so it is tested
/// without a window. The overlay keeps converting the rect to screen coordinates.
enum SelectionOutcome: Equatable {
    /// A dragged area, in the overlay view's coordinates.
    case area(CGRect)
    /// The window under the pointer, the one the overlay highlighted.
    case window
    case cancel

    /// A drag smaller than this in either side is a click.
    static let minimumDragSide: CGFloat = 2

    /// `.area`, `.scrolling`, `.allInOne` and `.selfTimer` take a dragged rect of at least 2 by 2; a click (no
    /// drag, or a tiny one) picks the highlighted window when there is one; `.window` ignores drags
    /// and only picks the highlight. With neither, the selection is cancelled. All-in-One asks
    /// only for a press that does not start on its rect.
    static func resolve(mode: SelectionMode, dragRect: CGRect?, hasHighlight: Bool) -> SelectionOutcome {
        if mode != .window, let rect = dragRect,
           rect.width >= minimumDragSide, rect.height >= minimumDragSide {
            return .area(rect)
        }
        return hasHighlight ? .window : .cancel
    }
}
