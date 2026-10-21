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
/// frame with `await`; matching and committing (about 24 ms for a 2560 x 1800 pair) run on the
/// actor's executor, never on the main actor. Everything that crosses in or out is a Sendable
/// value: `ScrollFrame`, `StitchProgress`, `ScaledImage`.
actor ScrollStitchEngine {
    private let finder: OverlapFinder
    private let maxPixelHeight: Int
    private var stitcher: ScrollStitcher?
    /// Content row of the last accepted frame's row 0, advanced exactly as the stitcher advances
    /// its own (a forward `.moved`), and that frame's height, for `heightPixels`.
    private var offset = 0
    private var frameHeight = 0

    /// `finder` carries the scrollbar strip for the display's scale: `OverlapFinder(scale:)`.
    init(finder: OverlapFinder = OverlapFinder(), maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight) {
        self.finder = finder
        self.maxPixelHeight = maxPixelHeight
    }

    /// Starts a stitch with the first frame, the page as the user arranged it. Starting again
    /// discards what was stitched before.
    func begin(first: ScrollFrame) {
        stitcher = ScrollStitcher(first: first, maxPixelHeight: maxPixelHeight, finder: finder)
        offset = 0
        frameHeight = first.height
    }

    /// Matches `frame` against the last accepted frame and commits what it newly shows.
    /// `predicted` is auto mode's posted step in pixels; manual mode passes nil and the stitcher
    /// uses the previous shift. A frame before `begin` begins the stitch and reports `.still`.
    func add(_ frame: ScrollFrame, predicted: Int? = nil) -> StitchProgress {
        guard stitcher != nil else {
            begin(first: frame)
            return progress(StitchStep(match: .still, committedRows: 0, isFull: false))
        }
        let step = stitcher!.add(frame, predicted: predicted)
        if case .moved(let dy, _, _, _) = step.match, dy > 0 {
            offset += dy
        }
        return progress(step)
    }

    /// Commits the last frame, footer included, and wraps the rows in a CGImage at native pixels
    /// without copying them: `bitsPerComponent` 8, `bytesPerRow` width x 4, BGRA in memory
    /// (`byteOrder32Little | noneSkipFirst`), tagged with `colorSpace`, the space the stream
    /// delivered the frames in. Returns it with `scale`, the display's. Nil before `begin`; the
    /// engine is empty afterwards, so a second call is nil too.
    func finish(scale: CGFloat, colorSpace: CGColorSpace) -> ScaledImage? {
        guard var stitcher else { return nil }
        self.stitcher = nil
        let stitched = stitcher.finish()
        guard stitched.width > 0, stitched.height > 0,
              let provider = CGDataProvider(data: stitched.bgra as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(width: stitched.width, height: stitched.height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: stitched.width * 4, space: colorSpace,
                                  bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return ScaledImage(image: image, scale: scale)
    }

    private func progress(_ step: StitchStep) -> StitchProgress {
        StitchProgress(heightPixels: min(offset + frameHeight, maxPixelHeight), step: step,
                       previewDelta: stitcher!.previewRows())
    }
}
