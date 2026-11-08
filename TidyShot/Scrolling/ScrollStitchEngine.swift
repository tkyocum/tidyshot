import CoreGraphics
import Foundation

/// What one frame did to the stitch, for the session's readout, status line and live preview.
nonisolated struct StitchProgress: Sendable {
    /// The height in pixels that Done would give now: the last accepted frame's content offset
    /// plus its height, at most the cap. Before any movement, the first frame's height.
    let heightPixels: Int
    /// The stitcher's verdict on the frame; `step.isFull` reports the cap.
    let step: StitchStep
    /// Rows committed since the last call, downscaled for the preview. Empty when none were.
    let previewDelta: PreviewStrip
}

/// Owns the `ScrollStitcher` off the main actor (spec 2.8, Stitcher). The session hands it each
/// frame with `await`; matching and committing (about 31 ms for a 2560 x 1800 pair) run on the
/// actor's executor, never on the main actor. Everything that crosses in or out is a Sendable
/// value: `ScrollFrame`, `StitchProgress`, `ScaledImage`.
actor ScrollStitchEngine {
    private let finder: OverlapFinder
    private let maxPixelHeight: Int
    private var stitcher: ScrollStitcher?

    /// `finder` carries the scrollbar strip for the display's scale: `OverlapFinder(scale:)`.
    init(finder: OverlapFinder = OverlapFinder(), maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight) {
        self.finder = finder
        self.maxPixelHeight = maxPixelHeight
    }

    /// Starts a stitch with the first frame, the page as the user arranged it. Starting again
    /// discards what was stitched before.
    func begin(first: ScrollFrame) {
        stitcher = ScrollStitcher(first: first, maxPixelHeight: maxPixelHeight, finder: finder)
    }

    /// Matches `frame` against the last accepted frame and commits what it newly shows.
    /// `predicted` is auto mode's posted step in pixels; manual mode passes nil and the stitcher
    /// uses the previous shift. `begin` has run: the session begins with its first frame.
    func add(_ frame: ScrollFrame, predicted: Int? = nil) -> StitchProgress {
        let step = stitcher!.add(frame, predicted: predicted)
        return StitchProgress(heightPixels: stitcher!.heightPixels, step: step, previewDelta: stitcher!.previewRows())
    }

    /// Commits the last frame, footer included, and wraps the rows in a CGImage at native pixels
    /// without copying them (`ScrollFrame.cgImage`), tagged with `colorSpace`, the space the stream
    /// delivered the frames in. Returns it with `scale`, the display's. Nil before `begin`; the
    /// engine is empty afterwards, so a second call is nil too.
    func finish(scale: CGFloat, colorSpace: CGColorSpace) -> ScaledImage? {
        guard var stitcher else { return nil }
        self.stitcher = nil
        let stitched = stitcher.finish()
        return ScrollFrame.cgImage(bgra: stitched.bgra, width: stitched.width, height: stitched.height,
                                   colorSpace: colorSpace, interpolate: false).map { ScaledImage(image: $0, scale: scale) }
    }
}
