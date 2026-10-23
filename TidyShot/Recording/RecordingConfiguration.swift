import CoreGraphics
import CoreMedia

/// A display as a recording sees it. `frame` is in CoreGraphics global points.
nonisolated struct RecordingDisplay: Equatable, Sendable {
    var id: CGDirectDisplayID
    var frame: CGRect
    var scale: CGFloat
}

/// What to record: an area (CoreGraphics global points) on a display, a whole display, or a
/// window by id with its frame and its display's scale.
nonisolated enum RecordingSource: Equatable, Sendable {
    case area(CGRect, on: RecordingDisplay)
    case display(RecordingDisplay)
    case window(id: CGWindowID, frame: CGRect, scale: CGFloat)
}

/// The content filter to build from fresh shareable content. `sourceRect` is display-local points.
nonisolated enum RecordingFilterPlan: Equatable, Sendable {
    case area(displayID: CGDirectDisplayID, sourceRect: CGRect)
    case display(displayID: CGDirectDisplayID)
    case window(windowID: CGWindowID)
}

/// The Capture tab's recording settings.
nonisolated struct RecordingOptions: Equatable, Sendable {
    var framesPerSecond: Int
    var retina: Bool
    var systemAudio: Bool
    var showsCursor: Bool
    var format: RecordingFormat = .mp4
    /// Read for a GIF recording only.
    var gif = GIFSettings(fps: 15, maxSide: 1280)
}

/// Everything the stream needs, decided without a screen: the filter plan, the output size with
/// the 4096 px cap and even sides, the frame rate, the cursor and audio.
nonisolated struct RecordingConfiguration: Equatable, Sendable {
    var filter: RecordingFilterPlan
    var pixelWidth: Int
    var pixelHeight: Int
    var framesPerSecond: Int
    var showsCursor: Bool
    var capturesAudio: Bool
    /// TidyShot's own sounds never go into a recording.
    var excludesCurrentProcessAudio: Bool
    /// A window is sized from its frame, so its shadow stays out.
    var ignoresShadowsSingleWindow: Bool
    /// A window resized during the recording is scaled to fit the starting size, letterboxed.
    var scalesToFit: Bool
    var preservesAspectRatio: Bool

    /// The longer output side's cap: Clop returns an empty reply for 5120×2880 H.264, and many
    /// players cannot play H.264 that large.
    static let maximumSide = 4096
    /// A GIF recording's MP4 rate, whatever `Frame rate` says: the GIF's own rate is at most 20.
    static let gifFramesPerSecond = 30
    /// An area under 32×32 pt is refused.
    static let minimumAreaSide: CGFloat = 32

    var minimumFrameInterval: CMTime {
        CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
    }

    static func make(_ source: RecordingSource, options: RecordingOptions) -> RecordingConfiguration {
        let filter: RecordingFilterPlan
        let size: (width: Int, height: Int)
        let isWindow: Bool
        switch source {
        case .area(let rect, let display):
            let scale = options.retina ? display.scale : 1
            var clamped = rect.intersection(display.frame)
            if clamped.isNull { clamped = CGRect(origin: display.frame.origin, size: .zero) }
            size = outputSize(points: clamped.size, scale: scale)
            let source = shrunk(clamped, to: size, scale: scale)
                .offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            filter = .area(displayID: display.id, sourceRect: source)
            isWindow = false
        case .display(let display):
            size = outputSize(points: display.frame.size, scale: options.retina ? display.scale : 1)
            filter = .display(displayID: display.id)
            isWindow = false
        case .window(let id, let frame, let scale):
            size = outputSize(points: frame.size, scale: options.retina ? scale : 1)
            filter = .window(windowID: id)
            isWindow = true
        }
        // A GIF has no sound, so its MP4 records none.
        let isGIF = options.format == .gif
        return RecordingConfiguration(filter: filter, pixelWidth: size.width, pixelHeight: size.height,
                                      framesPerSecond: isGIF ? gifFramesPerSecond : options.framesPerSecond,
                                      showsCursor: options.showsCursor,
                                      capturesAudio: !isGIF && options.systemAudio, excludesCurrentProcessAudio: true,
                                      ignoresShadowsSingleWindow: isWindow, scalesToFit: isWindow,
                                      preservesAspectRatio: true)
    }

    /// Points times scale, rounded to whole pixels. If either side is then over 4096, both are
    /// scaled down by one factor so the longer is 4096. Each side is then rounded down to even
    /// pixels, which H.264 needs; a side of one pixel becomes two rather than nothing.
    static func outputSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        var width = Int((points.width * scale).rounded())
        var height = Int((points.height * scale).rounded())
        let longer = max(width, height)
        if longer > maximumSide {
            // Integer maths, so 5120×2880 gives exactly 4096×2304.
            width = width * maximumSide / longer
            height = height * maximumSide / longer
        }
        return (even(width), even(height))
    }

    static func isLargeEnough(_ rect: CGRect) -> Bool {
        rect.width >= minimumAreaSide && rect.height >= minimumAreaSide
    }

    private static func even(_ side: Int) -> Int {
        side <= 0 ? 0 : max(2, side - side % 2)
    }

    /// `rect` made smaller, centred, by what the cap and the even rounding took off each side, so
    /// the output keeps the source's aspect and nothing is letterboxed.
    private static func shrunk(_ rect: CGRect, to size: (width: Int, height: Int), scale: CGFloat) -> CGRect {
        let longerPoints = max(rect.width, rect.height)
        let capped = Int((longerPoints * scale).rounded()) > maximumSide
        // Points per output pixel: the longer side maps onto 4096 px when capped.
        let pointsPerPixel = capped ? longerPoints / CGFloat(maximumSide) : 1 / scale
        let width = min(rect.width, CGFloat(size.width) * pointsPerPixel)
        let height = min(rect.height, CGFloat(size.height) * pointsPerPixel)
        return CGRect(x: rect.minX + (rect.width - width) / 2, y: rect.minY + (rect.height - height) / 2,
                      width: width, height: height)
    }
}
