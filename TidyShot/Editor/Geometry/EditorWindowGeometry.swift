import CoreGraphics

/// The editor window's first size and where it goes. Pure, so it is tested without windows.
/// Frames are AppKit screen rects (origin bottom left).
nonisolated enum EditorWindowGeometry {
    /// Space around the image at its natural size, in points; also the `inset` passed to
    /// `CanvasTransform.fitting`.
    static let inset: CGFloat = 24
    /// The smallest content size the editor opens at, in points. The width is a floor: the
    /// toolbar's own width (`toolbarWidth`) raises it through `minimumContentWidth`.
    static let minimumContentSize = CGSize(width: 640, height: 420)
    /// The largest share of the visible frame the window's frame opens at.
    static let screenFraction: CGFloat = 0.9

    /// The content size for an image of `imagePixels` at `scale`: its natural point size plus
    /// `inset` on every side, rounded up to whole points, at least `minimumContentSize`, and
    /// small enough that the frame (content plus `chrome`, the title bar and toolbar) fits in
    /// 90 % of `visibleFrame`. On a screen too small for the minimum, the 90 % cap wins.
    /// `minimumWidth` replaces the 640 pt floor with the toolbar's `minimumContentWidth`.
    static func initialContentSize(imagePixels: CGSize, scale: CGFloat, chrome: CGSize,
                                   visibleFrame: CGRect, minimumWidth: CGFloat = minimumContentSize.width) -> CGSize {
        let scale = scale > 0 ? scale : 1
        let wantedWidth = (imagePixels.width / scale + 2 * inset).rounded(.up)
        let wantedHeight = (imagePixels.height / scale + 2 * inset).rounded(.up)
        let largestWidth = (visibleFrame.width * screenFraction - chrome.width).rounded(.down)
        let largestHeight = (visibleFrame.height * screenFraction - chrome.height).rounded(.down)
        return CGSize(width: min(max(wantedWidth, minimumWidth), largestWidth),
                      height: min(max(wantedHeight, minimumContentSize.height), largestHeight))
    }

    /// A window frame of `size`: centred in `visibleFrame` when there is no `previous` editor,
    /// otherwise `offset` points right of and below `previous` (its top edge `offset` lower).
    /// Clamped inside `visibleFrame`; a frame larger than it keeps its top-left corner on screen
    /// so the title bar can be reached. The origin is rounded to whole points.
    static func cascaded(from previous: CGRect?, size: CGSize, visibleFrame: CGRect,
                         offset: CGFloat = 22) -> CGRect {
        let origin = previous.map { CGPoint(x: $0.minX + offset, y: $0.maxY - offset - size.height) }
            ?? CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        let x = max(min(origin.x, visibleFrame.maxX - size.width), visibleFrame.minX)
        let y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    /// macOS 26 (Liquid Glass) toolbar metrics for items AppKit draws itself, whose size it does
    /// not report. Rounded up, so the estimate errs towards a wider window, never an overflow
    /// chevron.
    enum ToolbarMetrics {
        /// The window buttons' trailing edge, for a window whose buttons are not laid out yet.
        static let windowButtons: CGFloat = 76
        static let segment: CGFloat = 36
        static let groupPadding: CGFloat = 8
        static let button: CGFloat = 36
        static let prominentButton: CGFloat = 44
        /// Glass around an item with its own view, such as the zoom pop-up.
        static let viewPadding: CGFloat = 16
        static let itemGap: CGFloat = 10
        static let fixedSpace: CGFloat = 16
        /// Space on each side of the title.
        static let titleGap: CGFloat = 12
        /// The most of the title counted: a unified toolbar truncates its title before it moves
        /// items into the overflow menu.
        static let titleAllowance: CGFloat = 96
        static let trailingInset: CGFloat = 16
    }

    /// The width the editor toolbar needs to show every item, in points: the window buttons'
    /// trailing edge and the title (both measured), the tool group's segments, the plain and
    /// prominent buttons, the items with their own views (measured), one gap between neighbouring
    /// items, and fixed spaces. A flexible space can shrink to nothing.
    static func toolbarWidth(windowButtonsMaxX: CGFloat, titleWidth: CGFloat, toolSegments: Int, buttons: Int,
                             prominentButtons: Int, viewWidths: [CGFloat], fixedSpaces: Int) -> CGFloat {
        typealias M = ToolbarMetrics
        let leading = windowButtonsMaxX + 2 * M.titleGap + min(max(titleWidth, 0), M.titleAllowance)
        let tools = toolSegments > 0 ? CGFloat(toolSegments) * M.segment + M.groupPadding : 0
        let plain = CGFloat(buttons) * M.button + CGFloat(prominentButtons) * M.prominentButton
        let views = viewWidths.reduce(0) { $0 + $1 + M.viewPadding }
        let itemCount = (toolSegments > 0 ? 1 : 0) + buttons + prominentButtons + viewWidths.count
        let gaps = CGFloat(max(itemCount - 1, 0)) * M.itemGap
        return leading + tools + plain + views + gaps + CGFloat(fixedSpaces) * M.fixedSpace + M.trailingInset
    }

    /// The window's `contentMinSize` width: the toolbar's width in whole points, at least the
    /// 640 pt floor.
    static func minimumContentWidth(toolbarWidth: CGFloat) -> CGFloat {
        max(minimumContentSize.width, toolbarWidth.rounded(.up))
    }
}
