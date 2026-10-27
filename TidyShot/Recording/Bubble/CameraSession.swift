import AVFoundation
import Synchronization

/// What the camera session tells the main actor.
nonisolated enum CameraSessionReport: Equatable, Sendable {
    case started
    /// No device, a failed input or a session that did not run; the reason, for the log.
    case couldNotStart(String)
    /// The notification's name.
    case lost(String)
    case back
}

/// The camera's format when the 720p preset cannot be set (plan Gap 15).
nonisolated enum CameraFormat {
    /// The bubble's fixed frame rate (design, Webcam bubble, Format).
    static let frameRate: Double = 30
    static let pixels = 1280 * 720

    struct Candidate: Equatable, Sendable {
        var width: Int
        var height: Int
        var maxFrameRate: Double
    }

    /// The index of the format closest to 1280×720 in pixel count among those that reach 30 fps,
    /// the smaller on a tie; nil when none does.
    static func pick(_ candidates: [Candidate]) -> Int? {
        func area(_ i: Int) -> Int { candidates[i].width * candidates[i].height }
        return candidates.indices
            .filter { candidates[$0].maxFrameRate >= frameRate }
            .min { a, b in
                let (da, db) = (abs(area(a) - pixels), abs(area(b) - pixels))
                return da != db ? da < db : area(a) < area(b)
            }
    }

    /// The frame rate for the log: from the min frame duration when it is a positive number,
    /// else the format's max rate, else 0. Never traps: some cameras report an invalid or zero
    /// duration, and no duration is set when the format does not reach 30 fps.
    static func loggedRate(minFrameDuration: CMTime, formatMax: Double) -> Int {
        let seconds = minFrameDuration.seconds
        let rate = minFrameDuration.isNumeric && seconds.isFinite && seconds > 0 ? 1 / seconds : formatMax
        return rate.isFinite && rate > 0 ? Int(rate.rounded()) : 0
    }
}

/// The bubble's camera (design, Webcam bubble, The camera session): one `AVCaptureSession` with
/// the device's input and the preview layer as its only output, no audio and no file. One serial
/// queue configures, starts, stops and rebuilds it, and reads its notifications against
/// `CameraRunState`; the main actor only asks and never waits.
nonisolated final class CameraSession: @unchecked Sendable {
    static let queueLabel = "io.tky.tidyshot.camera"

    /// For the preview layer. Configured, started and stopped only on the queue.
    let session: AVCaptureSession

    private let deviceID: String
    private let report: @MainActor @Sendable (CameraSessionReport) -> Void
    private let queue = DispatchQueue(label: CameraSession.queueLabel, qos: .userInitiated)
    /// Requests come from the main actor, notifications on the queue.
    private let state = Mutex(CameraRunState())

    // The queue's own.
    private var device: AVCaptureDevice?
    /// The 720p preset could be set; else the format is `CameraFormat.pick`'s.
    private var usesPreset = true
    private var observers: [any NSObjectProtocol] = []
    private var isClosed = false

    /// On the main actor, before any work goes to the queue: from here on the queue touches the
    /// session and never the layer.
    @MainActor init(deviceID: String, preview: AVCaptureVideoPreviewLayer,
                    report: @escaping @MainActor @Sendable (CameraSessionReport) -> Void) {
        self.deviceID = deviceID
        self.report = report
        session = AVCaptureSession()
        preview.session = session
        observers = observe()
    }

    /// Records the request and returns at once; the queue starts or stops the session.
    func run(_ on: Bool) {
        let request = state.withLock { $0.request(on) }
        queue.async { [self] in
            if on {
                start(generation: request.generation, rebuild: request.rebuild)
            } else {
                stopIfRunning()
            }
        }
    }

    /// On the queue: the observers go, then the session stops. A report already on its way to the
    /// main actor can still arrive.
    func close() {
        queue.async { [self] in
            isClosed = true
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
        }
        run(false)
    }

    // MARK: On the queue

    /// Builds the session on the first start and on a rebuild, starts it, and stops it again when
    /// a later request overtook this one. A rebuild drops the device first, so one an overtaken
    /// start carries still reaches the next start, which then never runs on a replugged camera's
    /// dead input.
    private func start(generation: Int, rebuild: Bool) {
        if rebuild { device = nil }
        guard !isClosed, !stopsAfterStart(generation) else { return }
        if device == nil {
            stopIfRunning()
            guard build(generation: generation) else { return }
        }
        guard let device, !session.isRunning else { return }

        // Locked through startRunning, so the session keeps the format and the frame rate.
        let locked = (try? device.lockForConfiguration()) != nil
        if locked { configure(device) }
        mirror()
        let began = ContinuousClock.now
        session.startRunning()
        let took = Int(((ContinuousClock.now - began) / .milliseconds(1)).rounded())
        if locked { device.unlockForConfiguration() }

        guard session.isRunning else { return couldNotStart("the session did not run", generation: generation) }
        if stopsAfterStart(generation) {
            stopIfRunning()
            return
        }
        let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let fps = CameraFormat.loggedRate(
            minFrameDuration: device.activeVideoMinFrameDuration,
            formatMax: device.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
        RecordingLog.note("Recording: camera \(device.localizedName), \(size.width)×\(size.height) at \(fps) fps, started in \(took) ms")
        send(.started)
    }

    /// The device's input in the session, at 720p where the preset allows it.
    private func build(generation: Int) -> Bool {
        device = nil
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs { session.removeInput(input) }
        guard let found = AVCaptureDevice(uniqueID: deviceID) else {
            couldNotStart("no camera with its ID", generation: generation)
            return false
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: found)
        } catch {
            couldNotStart(error.localizedDescription, generation: generation)
            return false
        }
        guard session.canAddInput(input) else {
            couldNotStart("the session took no input", generation: generation)
            return false
        }
        session.addInput(input)
        usesPreset = session.canSetSessionPreset(.hd1280x720)
        if usesPreset { session.sessionPreset = .hd1280x720 }
        device = found
        return true
    }

    /// Under the device's lock: the picked format when the preset could not be set, and 30 fps
    /// when the format reaches it, else the format's own rate.
    private func configure(_ device: AVCaptureDevice) {
        if !usesPreset {
            let candidates = device.formats.map { format in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                return CameraFormat.Candidate(
                    width: Int(size.width), height: Int(size.height),
                    maxFrameRate: format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
            }
            if let index = CameraFormat.pick(candidates) { device.activeFormat = device.formats[index] }
        }
        let reaches = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= CameraFormat.frameRate && CameraFormat.frameRate <= $0.maxFrameRate
        }
        guard reaches else { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(CameraFormat.frameRate))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    /// The preview's connections, mirrored before the first frame. The preview layer is the
    /// session's only output, so these are its connections.
    private func mirror() {
        for connection in session.connections where connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    /// Every stop TidyShot asks of a running session is counted first, so its notification is no
    /// loss.
    private func stopIfRunning() {
        guard session.isRunning else { return }
        state.withLock { $0.willStop() }
        session.stopRunning()
    }

    /// A start that failed counts as a loss, so the runtime error it may post is not a second one
    /// and a later start brings the picture back. One a later request overtook fails quietly: no
    /// loss and no report for a start nobody wants.
    private func couldNotStart(_ reason: String, generation: Int) {
        let wanted = state.withLock { state in
            guard !state.stopsAfterStart(generation: generation) else { return false }
            _ = state.handle(.runtimeError)
            return true
        }
        if wanted { send(.couldNotStart(reason)) }
    }

    private func stopsAfterStart(_ generation: Int) -> Bool {
        state.withLock { $0.stopsAfterStart(generation: generation) }
    }

    /// Every error, interruption and stop is a loss until C2 says otherwise (G4), except the
    /// stops TidyShot asked for.
    private func handle(_ event: CameraRunState.Event, name: String) {
        switch state.withLock({ $0.handle(event) }) {
        case .none: break
        case .lost: send(.lost(name))
        case .back: send(.back)
        case .rebuild:
            start(generation: state.withLock { $0.generation }, rebuild: true)
        }
    }

    /// On the poster's thread: the event goes to the queue.
    private func notified(_ event: CameraRunState.Event, name: Notification.Name) {
        queue.async { [self] in handle(event, name: name.rawValue) }
    }

    private func send(_ message: CameraSessionReport) {
        let report = report
        DispatchQueue.main.async {
            MainActor.assumeIsolated { report(message) }
        }
    }

    // MARK: Notifications

    /// The session's notifications, and the device's by its `uniqueID`, each handled on the queue.
    private func observe() -> [any NSObjectProtocol] {
        let centre = NotificationCenter.default
        let sessionEvents: [(Notification.Name, CameraRunState.Event)] = [
            (AVCaptureSession.runtimeErrorNotification, .runtimeError),
            (AVCaptureSession.wasInterruptedNotification, .wasInterrupted),
            (AVCaptureSession.interruptionEndedNotification, .interruptionEnded),
            (AVCaptureSession.didStartRunningNotification, .didStartRunning),
            (AVCaptureSession.didStopRunningNotification, .didStopRunning),
        ]
        let deviceEvents: [(Notification.Name, CameraRunState.Event)] = [
            (AVCaptureDevice.wasDisconnectedNotification, .deviceDisconnected),
            (AVCaptureDevice.wasConnectedNotification, .deviceConnected),
        ]
        let sessionObservers = sessionEvents.map { name, event in
            centre.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                self?.notified(event, name: name)
            }
        }
        let deviceObservers = deviceEvents.map { name, event in
            centre.addObserver(forName: name, object: nil, queue: nil) { [weak self, deviceID] note in
                guard (note.object as? AVCaptureDevice)?.uniqueID == deviceID else { return }
                self?.notified(event, name: name)
            }
        }
        return sessionObservers + deviceObservers
    }
}
