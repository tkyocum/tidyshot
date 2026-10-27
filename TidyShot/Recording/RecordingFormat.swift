import Foundation

/// Capture → Recording → `Format`, stored as `recordingFormat`. A GIF records an MP4 first and is
/// made from it after Stop.
nonisolated enum RecordingFormat: String, Codable, Sendable {
    case mp4
    case gif
}

/// `GIF frame rate` and `GIF size`. `maxSide` is the output's longer side, 0 for `Full size`.
nonisolated struct GIFSettings: Equatable, Sendable {
    var fps: Int
    var maxSide: Int

    /// The longer side the GIF is scaled to at most: `Full size` keeps the recording's own cap.
    var effectiveMaxSide: Int {
        maxSide == 0 ? RecordingConfiguration.maximumSide : maxSide
    }
}

/// Which Recording rows the Capture tab shows and enables for a format. A GIF has its own frame
/// rate and size and no sound, so it hides `Frame rate` and disables the audio rows.
nonisolated struct RecordingSettingsLayout: Equatable, Sendable {
    let showsFrameRate: Bool
    /// `GIF frame rate` and `GIF size`, with `fullSizeCaption` under them.
    let showsGIFRows: Bool
    /// `Record system audio` and `Microphone`.
    let audioRowsEnabled: Bool
    /// `gifCaption`, under the audio rows.
    let showsGIFCaption: Bool
    /// `Camera` and `Bubble size`: enabled with `Show webcam bubble`, for either format.
    let cameraRowsEnabled: Bool
    /// `bubbleGIFCaption`, under `Bubble size`: a GIF with the bubble on.
    let showsBubbleGIFCaption: Bool
    /// `overlayCaption`, last: either toggle on.
    let showsOverlayCaption: Bool

    static let gifCaption = "GIFs have no sound. Sound settings apply to MP4 recordings."
    static let fullSizeCaption = "Full size GIFs can be very large."
    static let bubbleGIFCaption = "A webcam bubble makes GIFs larger, because its picture changes in every frame."
    static let overlayCaption = "Click highlights and the webcam bubble apply to area and fullscreen recordings."

    init(format: RecordingFormat, clickHighlights: Bool = false, webcamBubble: Bool = false) {
        let isGIF = format == .gif
        showsFrameRate = !isGIF
        showsGIFRows = isGIF
        audioRowsEnabled = !isGIF
        showsGIFCaption = isGIF
        cameraRowsEnabled = webcamBubble
        showsBubbleGIFCaption = isGIF && webcamBubble
        showsOverlayCaption = clickHighlights || webcamBubble
    }
}
