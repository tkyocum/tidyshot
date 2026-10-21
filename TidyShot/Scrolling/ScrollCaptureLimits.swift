import CoreGraphics

/// Numbers shared by the scrolling capture code (spec 2.8).
nonisolated enum ScrollCaptureLimits {
    /// The stitched image never grows past this many pixel rows (32,768 pt at 2x). At 3094 px wide
    /// that is about 811 MB of pixels. The editor shows a taller image than a GPU texture takes as
    /// stacked layers (`ImageTiling`), and the clipboard gets no TIFF above 16,384 px
    /// (`Pasteboard.includesTIFF`).
    static let maxPixelHeight = 65_536
    /// A selected area shorter than this many points is refused.
    static let minimumAreaHeightPoints: CGFloat = 100
    /// The rightmost columns, in points, that matching ignores: overlay scrollbars appear and move.
    static let scrollbarStripPoints: CGFloat = 16
    /// The live preview is at most this many pixels wide.
    static let previewMaxWidth = 360
    /// The live preview keeps at most this many of its newest rows. The panel shows at most 440 pt
    /// of a preview 216 pt wide, under 800 rows of one 360 wide, and a preview as tall as the
    /// capture would exceed a GPU texture for a narrow area.
    static let previewMaxRows = 2048
}
