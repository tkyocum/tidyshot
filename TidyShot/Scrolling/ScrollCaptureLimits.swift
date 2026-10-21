import CoreGraphics

/// Numbers shared by the scrolling capture code (spec 2.8).
nonisolated enum ScrollCaptureLimits {
    /// The stitched image never grows past this many pixel rows (8,192 pt at 2x). The editor shows a
    /// capture as one texture, and 16,384 is within every Apple GPU's limit.
    static let maxPixelHeight = 16_384
    /// A selected area shorter than this many points is refused.
    static let minimumAreaHeightPoints: CGFloat = 100
    /// The rightmost columns, in points, that matching ignores: overlay scrollbars appear and move.
    static let scrollbarStripPoints: CGFloat = 16
    /// The live preview is at most this many pixels wide.
    static let previewMaxWidth = 360
}
