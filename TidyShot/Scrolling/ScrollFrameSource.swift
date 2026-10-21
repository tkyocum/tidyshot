import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Synchronization

/// What a frame source reports to the scrolling-capture session.
nonisolated enum FrameEvent: Sendable {
    /// A complete frame whose pixels changed, copied out of the stream's buffer.
    case frame(ScrollFrame)
    /// The display did not change since the last frame (`SCFrameStatus.idle`).
    case idle(ContinuousClock.Instant)
}

/// Where a session's frames come from: the stream in the app, synthetic frames in tests. One
/// source serves one run: `start()` once, then `stop()`, both from the main actor.
protocol FrameSource: AnyObject {
    /// Starts capturing. Frames are buffered newest-first, one deep, so a busy consumer gets the
    /// newest frame and the older ones are dropped; an idle never pushes out a pending frame.
    func start() async throws -> AsyncStream<FrameEvent>
    /// Stops capturing and finishes the events. A frame already buffered is still delivered, then
    /// the sequence ends. Safe to call more than once, and before `start()`.
    func stop() async
    /// Why the stream stopped by itself, when ScreenCaptureKit gave a reason. A stream that stops
    /// by itself records this and finishes the events as `stop()` does, after any frame still
    /// buffered (an event of its own could push that frame out of the one-deep buffer), so the
    /// session asks for it when its events end without Done or Cancel.
    var stopError: (any Error)? { get }
}

/// One `SCStream` of a rect of one display for a scrolling capture, with all of TidyShot
/// excluded. Setup and teardown run on the main actor; each sample is copied out of its
/// `CVPixelBuffer` on `queue` before the callback returns, so the stream's buffer pool never
/// starves and no pixel buffer outlives its callback.
nonisolated final class ScrollFrameSource: NSObject, FrameSource, SCStreamOutput, SCStreamDelegate {
    /// Pixels per point of the display: the stream's output and the stitched image's scale.
    let scale: CGFloat
    /// What the frames' pixels are in: the display's own colour space when it has a name the
    /// stream can take, otherwise sRGB. The stitched CGImage is tagged with it.
    let colorSpace: CGColorSpace
    /// Output size in pixels.
    let pixelWidth: Int
    let pixelHeight: Int

    private let rect: CGRect
    private let display: SCDisplay
    private let engine: CaptureEngine
    private let events: AsyncStream<FrameEvent>
    private let continuation: AsyncStream<FrameEvent>.Continuation
    private let queue = DispatchQueue(label: "io.tky.tidyshot.scrolling-frames", qos: .userInitiated)
    /// Written on ScreenCaptureKit's queue, read on the main actor.
    private let stopReason = Mutex<(any Error)?>(nil)
    @MainActor private var stream: SCStream?
    @MainActor private var started = false
    @MainActor private var stopped = false

    /// `rect` is in CoreGraphics global points and lies on `display` (the selection clips it).
    @MainActor init(rect: CGRect, display: SCDisplay, engine: CaptureEngine) {
        self.rect = rect
        self.display = display
        self.engine = engine
        scale = CaptureEngine.scale(forDisplayID: display.displayID)
        let pixels = Geometry.pixelSize(points: rect.size, scale: scale)
        pixelWidth = pixels.width
        pixelHeight = pixels.height
        colorSpace = Self.streamColorSpace(forDisplayID: display.displayID)
        (events, continuation) = AsyncStream.makeStream(of: FrameEvent.self, bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    /// The display's colour space when it is named (the stream takes a name, not a space),
    /// otherwise sRGB.
    static func streamColorSpace(forDisplayID id: CGDirectDisplayID) -> CGColorSpace {
        let display = CGDisplayCopyColorSpace(id)
        if display.name != nil { return display }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    /// A source is not restartable: after a throw (or a `stop()`) it stays spent, and the session
    /// makes a new one. A `stop()` that runs while this is suspended wins: the capture it was
    /// about to start is stopped again before this returns.
    @MainActor func start() async throws -> AsyncStream<FrameEvent> {
        guard !started else { return events }
        started = true
        let filter = try await makeFilter()
        if stopped { return events }
        let config = SCStreamConfiguration()
        config.sourceRect = Geometry.displayLocal(rect, in: display.frame)
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 4
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = colorSpace.name ?? CGColorSpace.sRGB
        ScrollDiag.beginSession()
        ScrollDiag.log("source start rect=\(rect) display=\(display.displayID) displayFrame=\(display.frame) sourceRect=\(config.sourceRect) out=\(pixelWidth)x\(pixelHeight) scale=\(scale) colorSpace=\(colorSpace.name.map { $0 as String } ?? "nil") streamColorSpaceName=\(config.colorSpaceName as String) tmp=\(NSTemporaryDirectory())")

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        if stopped {
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
            return events
        }
        self.stream = stream
        return events
    }

    @MainActor func stop() async {
        stopped = true
        if let stream {
            self.stream = nil
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
        }
        continuation.finish()
    }

    /// Everything of TidyShot excluded, by application: the panel, the area frame, the Quick
    /// Access overlay and any editor. When this process is not in the list, our on-screen windows
    /// by number instead.
    @MainActor private func makeFilter() async throws -> SCContentFilter {
        let content = try await engine.shareableContent()
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        if !own.isEmpty {
            return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }
        let numbers = Set(NSApp.windows.compactMap { window in
            window.isVisible && window.windowNumber > 0 ? CGWindowID(window.windowNumber) : nil
        })
        let windows = await OverlayWindowLookup.windows(numbers: numbers, engine: engine)
        return SCContentFilter(display: display, excludingWindows: windows)
    }

    // MARK: SCStreamOutput and SCStreamDelegate (on `queue` and ScreenCaptureKit's queue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        let copyStart = ContinuousClock.now
        var latency = 0.0
        if ScrollDiag.enabled {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            latency = CMTimeGetSeconds(CMTimeSubtract(CMClockGetTime(CMClockGetHostTimeClock()), pts)) * 1000
        }
        switch status {
        case .complete:
            guard let buffer = sampleBuffer.imageBuffer, let frame = Self.copyFrame(from: buffer) else {
                ScrollDiag.log("source complete frame NOT copied (format \(sampleBuffer.imageBuffer.map { CVPixelBufferGetPixelFormatType($0) } ?? 0))")
                return
            }
            if ScrollDiag.enabled, let buffer = sampleBuffer.imageBuffer {
                ScrollDiag.log("source frame \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer)) bytesPerRow=\(CVPixelBufferGetBytesPerRow(buffer)) captureToHandler=\(String(format: "%.1f", latency))ms copy=\(ScrollDiag.ms(since: copyStart))ms")
            }
            Self.send(.frame(frame), to: continuation)
        case .idle:
            Self.send(.idle(.now), to: continuation)
        default:
            ScrollDiag.log("source status \(raw)")
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Self.stopped(by: error, recordingIn: stopReason, finishing: continuation)
    }

    var stopError: (any Error)? {
        stopReason.withLock { $0 }
    }

    /// Records why the stream stopped, then finishes the events: a frame still buffered is
    /// delivered first, and the reason is there when the consumer sees the end.
    static func stopped(by error: any Error, recordingIn reason: borrowing Mutex<(any Error)?>,
                        finishing continuation: AsyncStream<FrameEvent>.Continuation) {
        reason.withLock { $0 = error }
        continuation.finish()
    }

    /// Copies a BGRA pixel buffer into a `ScrollFrame` while it is locked. Nil for any other
    /// pixel format or a buffer without a base address.
    static func copyFrame(from buffer: CVPixelBuffer) -> ScrollFrame? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        return ScrollFrame(bgra: UnsafeRawPointer(base), width: width, height: height, bytesPerRow: bytesPerRow)
    }

    /// Yields `event`. The buffer holds one event; when an idle pushes out a frame the consumer
    /// has not read yet, the frame goes back in and the idle is the one dropped, so the last frame
    /// before the page goes still is never lost.
    static func send(_ event: FrameEvent, to continuation: AsyncStream<FrameEvent>.Continuation) {
        let result = continuation.yield(event)
        if case .dropped(let old) = result {
            ScrollDiag.log("source buffer dropped \(old.diagName) for \(event.diagName)")
        }
        guard case .dropped(let old) = result, case .frame = old, case .idle = event else { return }
        continuation.yield(old)
    }
}

nonisolated extension FrameEvent {
    var diagName: String {
        switch self {
        case .frame: "frame"
        case .idle: "idle"
        }
    }
}
