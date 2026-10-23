import AppKit

/// The editor's tool segments. `setToolTip(_:forSegment:)` places each tip by the control's own
/// segment widths, which in the macOS 26 toolbar are narrower than the segments the toolbar draws,
/// so a tip showed a tool two places along. Every segment gets the same width here, the toolbar
/// then draws them evenly, and each tip is a tool tip rect over its share of the bounds.
final class ToolSegmentedControl: NSSegmentedControl {
    /// One tip per segment, in segment order.
    var segmentToolTips: [String] = [] {
        didSet { installToolTips() }
    }

    /// The owners `addToolTip` reads; NSView does not retain them.
    private var toolTipOwners: [NSString] = []

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        installToolTips()
    }

    private func installToolTips() {
        removeAllToolTips()
        toolTipOwners = segmentToolTips.map { $0 as NSString }
        for (rect, owner) in zip(Self.segmentRects(in: bounds, count: toolTipOwners.count), toolTipOwners) {
            addToolTip(rect, owner: owner, userData: nil)
        }
    }

    /// `bounds` split into `count` equal columns, left to right.
    nonisolated static func segmentRects(in bounds: CGRect, count: Int) -> [CGRect] {
        guard count > 0, bounds.width > 0 else { return [] }
        let width = bounds.width / CGFloat(count)
        return (0..<count).map { index in
            CGRect(x: bounds.minX + CGFloat(index) * width, y: bounds.minY, width: width, height: bounds.height)
        }
    }
}
