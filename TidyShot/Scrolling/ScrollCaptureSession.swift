import CoreGraphics
import Foundation
import Observation

/// How the page moves during a capture: the user scrolls, or TidyShot posts wheel events.
nonisolated enum ScrollMode: Equatable, Sendable {
    case manual
    case auto
}

/// Where a scrolling capture is. `.finishing` stitches the last frame; `.ended` has an outcome.
nonisolated enum ScrollCapturePhase: Equatable, Sendable {
    case ready
    case capturing(ScrollMode)
    case finishing
    case ended
}

/// What a scrolling capture gave (spec 2.8, Session model).
nonisolated enum ScrollCaptureOutcome: Sendable {
    case image(ScaledImage)
    case cancelled
    /// The stream failed. `partial` is what was stitched before, when a first frame had arrived.
    case failed(String, partial: ScaledImage?)

    /// What `AppCoordinator.save(_:)` gets: the stitched image, or the partial one.
    var imageToSave: ScaledImage? {
        switch self {
        case .image(let image): image
        case .failed(_, let partial): partial
        case .cancelled: nil
        }
    }

    /// The failure notification (spec 2.8, Exact strings), or nil when there is none.
    var failureNotice: (title: String, body: String)? {
        switch self {
        case .image, .cancelled:
            nil
        case .failed(let reason, .some):
            (title: "Scrolling capture stopped", body: "The capture stopped early: \(reason) TidyShot saved what it had.")
        case .failed(let reason, .none):
            (title: "Scrolling capture failed", body: reason)
        }
    }
}

/// One scrolling capture, from Start to Done or Cancel (spec 2.8, Session model). It reads the
/// frame source, feeds the stitch engine, and keeps what the panel shows: the phase, the size
/// readout, the status line and the live preview. It is built with a `FrameSource` and a clock,
/// so its tests run on synthetic frames.
@Observable
final class ScrollCaptureSession {
    /// How long an end line (the height limit, and in auto mode "Reached the end.") shows before
    /// the session finishes.
    static let endLineDelay: Duration = .milliseconds(400)
    /// The live preview is rebuilt at most this often (4 times a second).
    static let previewInterval: Duration = .milliseconds(250)
    /// The reason when the stream stops by itself without an error.
    static let streamStoppedReason = "The screen recording stream stopped."

    /// The captured area in CoreGraphics global points.
    let area: CGRect
    /// Pixels per point of the area's display.
    let scale: CGFloat
    let widthPixels: Int
    let clock: any ScrollClock

    private(set) var phase: ScrollCapturePhase = .ready
    /// What Done would give now, in pixels, for the size readout. The area's height before the
    /// first frame.
    private(set) var heightPixels: Int
    private(set) var status: ScrollCaptureStatus = .readyManual
    /// The first frame, at full size, until rows are stitched; then the stitched rows, at most
    /// `ScrollCaptureLimits.previewMaxWidth` pixels wide.
    private(set) var preview: CGImage?
    /// True once the first frame has arrived. Done waits for it.
    private(set) var hasFirstFrame = false
    private(set) var outcome: ScrollCaptureOutcome?
    /// Frame events read so far, for the tests.
    @ObservationIgnored private(set) var framesRead = 0
    /// The newest frame read, when the session read it (frames carry no time, so the session
    /// stamps them with its clock), and a count that changes with each one. The auto-scroll
    /// driver (Task 6) settles on them through `FrameSettler`.
    @ObservationIgnored private(set) var latestFrame: ScrollFrame?
    @ObservationIgnored private(set) var latestFrameAt: ContinuousClock.Instant?
    @ObservationIgnored private(set) var frameSerial = 0
    /// The serial of the last frame handed to the engine. In auto mode the newest frame read can
    /// be newer, until the driver integrates it; Done and a stream stop add it before finishing.
    @ObservationIgnored private var addedSerial = 0
    /// Called once, when the session ends.
    @ObservationIgnored var onEnd: ((ScrollCaptureOutcome) -> Void)?
    /// The Scroll automatically checkbox (`AppSettings.scrollingAutoScroll`). It takes effect
    /// only while `isAutoScrollPermitted`; a change is reported through `onAutoScrollChanged`.
    var autoScroll: Bool {
        didSet {
            if phase == .ready { status = .ready(autoScroll: usesAutoScroll) }
            onAutoScrollChanged?(autoScroll)
        }
    }
    /// The PostEvent grant as last checked; always false without an environment.
    private(set) var isAutoScrollPermitted: Bool
    @ObservationIgnored var onAutoScrollChanged: ((Bool) -> Void)?
    /// Start begins in auto mode.
    var usesAutoScroll: Bool { autoScroll && isAutoScrollPermitted }

    private let source: any FrameSource
    private let engine: ScrollStitchEngine
    private let colorSpace: CGColorSpace
    private let autoScrollEnvironment: AutoScrollEnvironment?
    /// False without an environment: the session is manual only, and the panel says so.
    var isAutoScrollAvailable: Bool { autoScrollEnvironment != nil }
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var driverTask: Task<Void, Never>?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewRows = PreviewRows()
    @ObservationIgnored private var lastPreviewAt: ContinuousClock.Instant?

    /// `area` is in CoreGraphics global points on one display of backing scale `scale`;
    /// `colorSpace` is the space the source delivers frames in. Without `autoScrollEnvironment`
    /// the session is manual only.
    init(source: any FrameSource, engine: ScrollStitchEngine, area: CGRect, scale: CGFloat, colorSpace: CGColorSpace,
         clock: any ScrollClock = SystemScrollClock(), autoScrollEnvironment: AutoScrollEnvironment? = nil,
         prefersAutoScroll: Bool = false) {
        self.source = source
        self.engine = engine
        self.area = area
        self.scale = scale
        self.colorSpace = colorSpace
        self.clock = clock
        self.autoScrollEnvironment = autoScrollEnvironment
        let pixels = Geometry.pixelSize(points: area.size, scale: scale)
        widthPixels = pixels.width
        heightPixels = pixels.height
        let permitted = autoScrollEnvironment?.isPermitted() ?? false
        autoScroll = prefersAutoScroll
        isAutoScrollPermitted = permitted
        status = .ready(autoScroll: prefersAutoScroll && permitted)
    }

    /// A URL command's session (spec 2.9) not started within this cancels itself.
    static let readyTimeout: Duration = .seconds(60)
    @ObservationIgnored private var readyTimeoutTask: Task<Void, Never>?

    // MARK: Commands

    /// Cancels the session, as Cancel does, when it is still `.ready` after `timeout` on the
    /// session's clock. Start or the end of the session stops the wait.
    func cancelIfNotStarted(within timeout: Duration) {
        readyTimeoutTask?.cancel()
        readyTimeoutTask = Task { [weak self, clock] in
            do { try await clock.sleep(for: timeout) } catch { return }
            guard let self, phase == .ready else { return }
            await cancel()
        }
    }

    /// Starts the stream. The first frame is the page as the user arranged it.
    func start() async {
        guard phase == .ready else { return }
        readyTimeoutTask?.cancel()
        let mode: ScrollMode = usesAutoScroll ? .auto : .manual
        phase = .capturing(mode)
        // Auto mode waits for the pointer over the area.
        status = mode == .auto ? .autoPaused : .manualCapturing
        do {
            let events = try await source.start()
            // Cancelled while the stream was starting: stop it again.
            guard phase != .ended else {
                await source.stop()
                return
            }
            readTask = Task { await self.read(events) }
            if mode == .auto, let autoScrollEnvironment {
                let driver = AutoScrollDriver(environment: autoScrollEnvironment, clock: clock)
                driverTask = Task { await driver.run(session: self) }
            }
        } catch {
            guard phase != .ended else { return }
            end(.failed(error.localizedDescription, partial: nil))
        }
    }

    /// Stops the stream, stitches what is still buffered, and ends with the image. Ignored
    /// before the first frame and outside `.capturing`.
    func done() async {
        guard case .capturing = phase, hasFirstFrame else { return }
        driverTask?.cancel()
        phase = .finishing
        status = .finishing
        await source.stop()
        // `stop()` finishes the events after the frame still buffered; the read loop takes it.
        await readTask?.value
        guard phase != .ended else { return }
        await addLatestFrame()
        let image = await engine.finish(scale: scale, colorSpace: colorSpace)
        end(image.map(ScrollCaptureOutcome.image) ?? .failed(CaptureError.noImage.localizedDescription, partial: nil))
    }

    /// Discards everything at once. Works in every phase but `.ended`.
    func cancel() async {
        guard phase != .ended else { return }
        end(.cancelled)
        readTask?.cancel()
        await source.stop()
    }

    /// The panel's default button and the Capture Scrolling shortcut: Start, then Done.
    func advance() async {
        switch phase {
        case .ready: await start()
        case .capturing: await done()
        case .finishing, .ended: break
        }
    }

    /// Shows `line` for `endLineDelay`, then finishes as Done does, in a task of the session's own,
    /// once, so the caller returns at once. The driver ends this way: Done cancels the driver's
    /// task, which must not be the one finishing.
    func finishSoon(showing line: ScrollCaptureStatus) {
        guard case .capturing = phase, endTask == nil else { return }
        endTask = Task {
            guard case .capturing = phase else { return }
            status = line
            try? await clock.sleep(for: Self.endLineDelay)
            await done()
        }
    }

    // MARK: Auto-scroll

    /// Checks the PostEvent grant again; the panel does once a second before Start.
    func refreshAutoScrollPermission() {
        let permitted = autoScrollEnvironment?.isPermitted() ?? false
        guard permitted != isAutoScrollPermitted else { return }
        isAutoScrollPermitted = permitted
        if phase == .ready { status = .ready(autoScroll: usesAutoScroll) }
    }

    /// Auto mode: stitches a settled frame, `predicted` being the posted step in pixels. Nil once
    /// the session has left auto mode.
    func integrate(_ frame: ScrollFrame, predicted: Int) async -> StitchProgress? {
        guard phase == .capturing(.auto) else { return nil }
        addedSerial = frame.serial
        let progress = await engine.add(frame, predicted: predicted)
        apply(progress)
        return phase == .capturing(.auto) ? progress : nil
    }

    /// Auto-scroll gives up: the user scrolls from here, and frames go to the engine again.
    func handOver() {
        guard phase == .capturing(.auto) else { return }
        ScrollDiag.log("session hand over to manual at serial=\(frameSerial)")
        phase = .capturing(.manual)
        status = .autoHandedOver
    }

    /// The driver's line while it scrolls or waits for the pointer.
    func showAutoStatus(_ line: ScrollCaptureStatus) {
        guard phase == .capturing(.auto), status != line else { return }
        status = line
    }

    // MARK: Frames

    private func read(_ events: AsyncStream<FrameEvent>) async {
        for await event in events {
            guard phase != .ended else { return }
            switch event {
            case .frame(let frame):
                framesRead += 1
                await take(frame)
            case .idle:
                break
            }
        }
        // Done and Cancel leave `.capturing` before they stop the source; events that end while
        // capturing mean the stream stopped by itself, and the source knows why.
        await streamStopped(source.stopError)
    }

    private func take(_ frame: ScrollFrame) async {
        var frame = frame
        frameSerial += 1
        frame.serial = frameSerial
        ScrollDiag.log("session take serial=\(frame.serial) \(frame.width)x\(frame.height) phase=\(phase) sincePrevious=\(latestFrameAt.map { ScrollDiag.ms(clock.now - $0) } ?? "-")ms")
        latestFrame = frame
        latestFrameAt = clock.now
        // The first frame begins the stitch and is the preview: its rows reach `previewDelta`
        // only once a move commits them.
        guard hasFirstFrame else {
            addedSerial = frame.serial
            await engine.begin(first: frame)
            hasFirstFrame = true
            heightPixels = frame.height
            preview = ScrollFrame.cgImage(bgra: frame.bgra, width: frame.width, height: frame.height,
                                          colorSpace: colorSpace, interpolate: true)
            return
        }
        // In auto mode the driver stitches the settled frames itself (`integrate`).
        guard phase != .capturing(.auto) else { return }
        addedSerial = frame.serial
        let progress = await engine.add(frame)
        ScrollDiag.log("manual result serial=\(frame.serial) status=\(status) -> \(ScrollDiag.describe(progress.step.match)) committed=\(progress.step.committedRows) height=\(progress.heightPixels) status=\(status)")
        apply(progress)
    }

    /// The readout, the preview, the manual status line and the cap, from one stitched frame.
    private func apply(_ progress: StitchProgress) {
        guard phase != .ended else { return }
        heightPixels = progress.heightPixels
        if !progress.previewDelta.isEmpty {
            previewRows.append(progress.previewDelta)
            showPreview()
        }
        guard phase == .capturing(.manual) else { return }
        switch progress.step.match {
        // After a hand-over the hand-over line stays until the user finds the overlap again.
        case .lost: if status != .autoHandedOver { status = .manualLost }
        case .moved: status = .manualCapturing
        case .still: break
        }
        if progress.step.isFull { finishSoon(showing: .heightLimit) }
    }

    /// The stream stopped by itself: keep what was stitched, if anything, and say why.
    private func streamStopped(_ error: (any Error)?) async {
        guard case .capturing = phase else { return }
        phase = .finishing
        status = .finishing
        await source.stop()
        let reason = error?.localizedDescription ?? Self.streamStoppedReason
        var partial: ScaledImage?
        if hasFirstFrame {
            // No wait on `readTask`: this runs inside it.
            await addLatestFrame()
            partial = await engine.finish(scale: scale, colorSpace: colorSpace)
        }
        end(.failed(reason, partial: partial))
    }

    /// Auto mode: the newest frame read, when the driver had not integrated it yet, so the image
    /// ends where the screen did. A lost or still result commits nothing.
    private func addLatestFrame() async {
        guard let latestFrame, latestFrame.serial > addedSerial else { return }
        addedSerial = latestFrame.serial
        _ = await engine.add(latestFrame)
    }

    private func end(_ outcome: ScrollCaptureOutcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        phase = .ended
        driverTask?.cancel()
        endTask?.cancel()
        previewTask?.cancel()
        readyTimeoutTask?.cancel()
        onEnd?(outcome)
    }

    // MARK: Preview

    /// Rebuilds the preview from the stitched rows, at most every `previewInterval`; rows that
    /// come sooner show when the interval has passed.
    private func showPreview() {
        guard !previewRows.isEmpty, phase != .ended else { return }
        let now = clock.now
        if let lastPreviewAt, now - lastPreviewAt < Self.previewInterval {
            guard previewTask == nil else { return }
            let wait = Self.previewInterval - (now - lastPreviewAt)
            previewTask = Task {
                try? await clock.sleep(for: wait)
                previewTask = nil
                showPreview()
            }
            return
        }
        preview = previewRows.image(colorSpace: colorSpace)
        lastPreviewAt = now
    }
}

/// The preview's newest rows: each `PreviewStrip` appended below the last. The image is the newest
/// `maxRows` of them; the panel shows the bottom of the preview, and a preview as tall as a narrow
/// 65,536 px capture would exceed a GPU texture. Older rows are dropped once twice that many are
/// held, so a drop copies at most `maxRows` rows.
nonisolated struct PreviewRows {
    let maxRows: Int
    private(set) var width = 0
    /// Rows held, at most `2 * maxRows`.
    private(set) var height = 0
    private var bgra = Data()

    init(maxRows: Int = ScrollCaptureLimits.previewMaxRows) {
        self.maxRows = max(1, maxRows)
    }

    var isEmpty: Bool { height == 0 }

    mutating func append(_ strip: PreviewStrip) {
        guard !strip.isEmpty else { return }
        if width == 0 { width = strip.width }
        guard strip.width == width else { return }
        bgra.append(strip.bgra)
        height += strip.height
        if height > 2 * maxRows {
            bgra = Data(bgra.suffix(maxRows * width * 4))
            height = maxRows
        }
    }

    /// The newest `maxRows` rows. The bytes are copied, so a later `append` never copies the held
    /// rows because this image still shares them.
    func image(colorSpace: CGColorSpace) -> CGImage? {
        let rows = min(height, maxRows)
        return ScrollFrame.cgImage(bgra: Data(bgra.suffix(rows * width * 4)), width: width, height: rows,
                                   colorSpace: colorSpace, interpolate: true)
    }
}
