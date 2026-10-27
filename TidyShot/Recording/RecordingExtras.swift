import AppKit
import AVFoundation

/// Where one recording's bubble, ring overlay and rings go (plan Gap 13), made from the recorded
/// area or display by `make`.
nonisolated struct RecordingExtrasPlace: Equatable, Sendable {
    /// AppKit points: the area, or the display's visible frame for fullscreen. The bubble stays
    /// inside it.
    var bubbleRect: CGRect
    /// AppKit points: the display's whole frame, which the ring overlay covers.
    var screenFrame: CGRect
    /// CG global points: the area within the display, where downs draw rings; nil for fullscreen.
    var ringArea: CGRect?
    /// CG global points: the recorded display's frame.
    var displayFrame: CGRect

    /// An area is cut to the display, and converted to AppKit with the primary display's height,
    /// as `Geometry.appKitRect` converts; fullscreen puts the bubble in the visible frame. So does
    /// an area the display no longer holds (its frame changed during the count-in), whose cut is
    /// null or empty, so the bubble's clamp never sees an infinite rect.
    static func make(cgArea: CGRect?, cgDisplayFrame: CGRect, screenFrame: CGRect, visibleFrame: CGRect,
                     primaryHeight: CGFloat) -> RecordingExtrasPlace {
        let area = cgArea?.intersection(cgDisplayFrame)
        let bubbleRect = area.flatMap {
            $0.isEmpty ? nil : CGRect(x: $0.minX, y: primaryHeight - $0.maxY, width: $0.width, height: $0.height)
        } ?? visibleFrame
        return RecordingExtrasPlace(bubbleRect: bubbleRect, screenFrame: screenFrame, ringArea: area,
                                    displayFrame: cgDisplayFrame)
    }
}

/// R3's windows for one area or fullscreen recording (design, Who owns the bubble, the camera and
/// the rings): the webcam bubble and its camera session, the ring overlay and the click monitors.
/// `record()` makes it before the hand-off and closes it on every exit; the chrome holds it, so the
/// bar's buttons reach it, and closes it on Stop. Window recordings get none.
final class RecordingExtras {
    let options: RecordingOptions
    let camera: CameraStart
    /// Called after every click, drag and size step on the bubble, so the bar goes back above it.
    var onBubbleInteraction: () -> Void = {}

    private let insets: BubbleInsets
    private let clickSource: (_ isFilmedWindow: @escaping (NSWindow) -> Bool) -> any ClickEventSource
    private let elapsed: () -> TimeInterval
    private let storeInsets: (BubbleInsets) -> Void
    private let storeSize: (BubbleSize) -> Void

    private var bubble: WebcamBubblePanel?
    private var overlay: ClickRingOverlay?
    private var highlighter: ClickHighlighter?
    /// The camera's preview layer; nil when the start resolved no usable camera.
    private var preview: AVCaptureVideoPreviewLayer?
    /// Made at the first on, so a bubble that is never turned on never opens the camera.
    private var session: CameraSession?
    private var tracker = CameraLossTracker()
    /// Both features count as filmed until the driver says otherwise.
    private var filmed: Set<FilmedFeature> = Set(FilmedFeature.allCases)
    private var isClosed = false

    init(options: RecordingOptions, camera: CameraStart, insets: BubbleInsets,
         clickSource: @escaping (_ isFilmedWindow: @escaping (NSWindow) -> Bool) -> any ClickEventSource,
         elapsed: @escaping () -> TimeInterval,
         storeInsets: @escaping (BubbleInsets) -> Void,
         storeSize: @escaping (BubbleSize) -> Void) {
        self.options = options
        self.camera = camera
        self.insets = insets
        self.clickSource = clickSource
        self.elapsed = elapsed
        self.storeInsets = storeInsets
        self.storeSize = storeSize
    }

    /// The camera's first loss, or its failed start, for the note after Stop.
    var cameraLoss: CameraLoss? { tracker.loss }

    /// A camera resolved with access, so the bar can turn the bubble on.
    private var cameraIsUsable: Bool {
        camera.camera != nil && camera.access == .authorized
    }

    /// The bubble and the overlay, made and ordered front once per recording, at the start of the
    /// count-in or right after the selection (design, Filming, When they are made). With the toggle
    /// on and a usable camera the bubble shows its picture and the camera starts; otherwise it is on
    /// screen, invisible and click-through. The highlighter waits for `setHighlights`.
    func show(at place: RecordingExtrasPlace) {
        guard !isClosed, bubble == nil else { return }
        let overlay = ClickRingOverlay(screenFrame: place.screenFrame)
        let layer: CALayer
        if cameraIsUsable {
            let preview = AVCaptureVideoPreviewLayer()
            preview.videoGravity = .resizeAspectFill
            self.preview = preview
            layer = preview
        } else {
            layer = CALayer()
        }
        let frame = BubblePlacement.frame(recorded: place.bubbleRect, size: options.bubbleSize, insets: insets)
        let bubble = WebcamBubblePanel(preview: layer, size: options.bubbleSize, frame: frame, recorded: place.bubbleRect)
        bubble.onInteraction = { [weak self] in self?.onBubbleInteraction() }
        bubble.onDragEnded = { [weak self] frame in self?.dragEnded(at: frame) }
        bubble.onSizeStepped = { [weak self] size, _ in self?.sizeStepped(to: size) }
        self.overlay = overlay
        self.bubble = bubble
        highlighter = ClickHighlighter(rule: ClickHighlightRule(displayFrame: place.displayFrame, area: place.ringArea),
                                       source: clickSource { [weak bubble] window in window === bubble },
                                       drawing: overlay)
        let showsPicture = options.webcamBubble && cameraIsUsable
        bubble.setPictureShown(showsPicture)
        overlay.orderFrontRegardless()
        bubble.orderFrontRegardless()
        if showsPicture {
            runCamera(true)
        }
    }

    /// The place from fresh shareable content, before the driver starts: the bubble is clamped into
    /// the new rect without storing it, the overlay covers the display's fresh frame, and the rings
    /// follow the fresh area.
    func place(at place: RecordingExtrasPlace) {
        guard !isClosed else { return }
        bubble?.reclamp(into: place.bubbleRect)
        overlay?.setScreenFrame(place.screenFrame)
        highlighter?.setRule(ClickHighlightRule(displayFrame: place.displayFrame, area: place.ringArea))
    }

    /// Each window's number while it is on screen, for the filter to film.
    var windowNumbers: [FilmedFeature: CGWindowID] {
        var numbers: [FilmedFeature: CGWindowID] = [:]
        let windows: [(FilmedFeature, NSWindow?)] = [(.bubble, bubble), (.highlights, overlay)]
        for case let (feature, window?) in windows where window.isVisible && window.windowNumber > 0 {
            numbers[feature] = CGWindowID(window.windowNumber)
        }
        return numbers
    }

    /// The features the filter films. A missing bubble hides its picture and its camera stops for
    /// good; missing highlights are never started, and stopped if they were.
    func setFilmed(_ features: Set<FilmedFeature>) {
        guard !isClosed else { return }
        filmed = features
        if !features.contains(.bubble) {
            hidePicture()
        }
        if !features.contains(.highlights) {
            highlighter?.stop()
        }
    }

    /// The bar's bubble button, while the bubble is filmed and has a usable camera: on starts the
    /// camera and shows the picture; off hides the picture at once, then stops the camera. The
    /// window stays on screen for the filter either way.
    func setBubble(_ on: Bool) {
        guard !isClosed, filmed.contains(.bubble), cameraIsUsable, let bubble else { return }
        if on {
            bubble.setPictureShown(true)
            runCamera(true)
        } else {
            hidePicture()
        }
    }

    /// Installs or removes the click monitors, while highlights are filmed.
    func setHighlights(monitoring: Bool) {
        guard !isClosed, let highlighter else { return }
        if monitoring && filmed.contains(.highlights) {
            highlighter.start()
        } else {
            highlighter.stop()
        }
    }

    /// Once: the tracker keeps what it has, both windows go off screen at once, the monitors and
    /// every ring go, the session's observers go and its stop is queued, then both windows close.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        tracker.close()
        onBubbleInteraction = {}
        bubble?.orderOut(nil)
        overlay?.orderOut(nil)
        highlighter?.close()
        session?.close()
        bubble?.onInteraction = {}
        bubble?.onDragEnded = { _ in }
        bubble?.onSizeStepped = { _, _ in }
        bubble?.close()
        overlay?.close()
    }

    // MARK: The camera

    /// Makes the session at the first on, then asks it to run or stop.
    private func runCamera(_ on: Bool) {
        if on, session == nil, let preview, let id = camera.camera?.uniqueID {
            session = CameraSession(deviceID: id, preview: preview) { [weak self] report in
                self?.received(report)
            }
        }
        session?.run(on)
    }

    /// The picture goes before the camera stops, so no frame after "off" is filmed.
    private func hidePicture() {
        bubble?.setPictureShown(false)
        runCamera(false)
    }

    /// The session's reports. One that arrives after `close` is dropped, so the loss `record()`
    /// reads does not change. The bubble's place never changes on a loss.
    private func received(_ report: CameraSessionReport) {
        guard !isClosed else { return }
        switch report {
        case .couldNotStart(let reason):
            RecordingLog.note("Recording: camera could not be started: \(reason)")
            tracker.couldNotStart()
            bubble?.setLost(true)
        case .lost(let name):
            let time = elapsed()
            bubble?.setLost(true)
            RecordingLog.note("Recording: camera lost at \(RecordingClock.format(time)): \(name)")
            tracker.lost(at: time)
        case .back, .started:
            // A start after a loss is a return too: turning the bubble off and on again clears the
            // run state's loss, so that start brings no `.back`.
            cameraBack()
        }
    }

    /// The picture is back after a loss; once, as a rebuild's start can bring both reports.
    private func cameraBack() {
        guard let bubble, bubble.isLost else { return }
        let time = elapsed()
        bubble.setLost(false)
        RecordingLog.note("Recording: camera back at \(RecordingClock.format(time))")
        tracker.back(at: time)
    }

    // MARK: The bubble's moves

    /// A drag's end is remembered, from where the user left the bubble.
    private func dragEnded(at frame: CGRect) {
        remember(.dragEnded, frame: frame)
        onBubbleInteraction()
    }

    /// A double-click's size is remembered, and only the size (design, Where it starts, and memory).
    private func sizeStepped(to size: BubbleSize) {
        storeSize(size)
        RecordingLog.note("Recording: bubble size \(size.rawValue)")
        onBubbleInteraction()
    }

    private func remember(_ move: BubblePlacement.Move, frame: CGRect) {
        guard let bubble,
              let stored = BubblePlacement.storedInsets(after: move, frame: frame, recorded: bubble.recorded)
        else { return }
        storeInsets(stored)
    }
}
