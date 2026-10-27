import Foundation

/// Capture → Recording → `Camera` (design, Webcam bubble, Settings and Permission): the stored
/// choice, the pop-up's entries, the access note, and which camera a recording starts with. Pure:
/// the devices and the access come in as values.
nonisolated enum CameraChoice {
    /// What `recordingCamera` and `recordingCameraName` hold. There is no Off: the toggle is the
    /// switch.
    enum Stored: Equatable, Sendable {
        case systemDefault
        /// A camera by `uniqueID`, with the name it had when it was last listed (may be empty).
        case device(id: String, name: String)

        /// `value` is `default` (or empty) for System Default, otherwise the camera's `uniqueID`.
        init(value: String, name: String) {
            switch value {
            case "", CameraChoice.systemDefaultValue: self = .systemDefault
            default: self = .device(id: value, name: name)
            }
        }

        /// What `recordingCamera` stores for it.
        var value: String {
            switch self {
            case .systemDefault: CameraChoice.systemDefaultValue
            case .device(let id, _): id
            }
        }

        /// What `recordingCameraName` stores for it: empty for System Default.
        var name: String {
            if case .device(_, let name) = self { name } else { "" }
        }
    }

    /// A pop-up item: `tag` is the value `recordingCamera` stores for it.
    struct Entry: Equatable, Sendable {
        var tag: String
        var title: String
    }

    static let systemDefaultValue = "default"
    static let systemDefaultTitle = "System Default"
    static let unknownName = "Unknown camera"
    static let recordedWithoutTitle = "Recorded without the webcam bubble"
    static let accessOffText = "Camera access is off for TidyShot."
    static let noCameraText = "No camera is connected."
    static let couldNotStartText = "The camera could not be started."
    static let notFilmedText = "The bubble could not be filmed."
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!

    static func recordedWithTitle(_ name: String) -> String {
        "Recorded with \(name)"
    }

    /// `Unknown camera is not connected.` when no name was stored.
    static func notConnectedText(_ name: String) -> String {
        "\(displayName(name)) is not connected."
    }

    /// `System Default`, each camera by name, then a stored camera that is not listed, which stays
    /// the selection: `<name> (not connected)`.
    static func entries(stored: Stored, devices: [CameraDevice]) -> [Entry] {
        var entries = [Entry(tag: systemDefaultValue, title: systemDefaultTitle)]
        entries += devices.map { Entry(tag: $0.uniqueID, title: $0.name) }
        if case .device(let id, let name) = stored, !devices.contains(where: { $0.uniqueID == id }) {
            entries.append(Entry(tag: id, title: "\(displayName(name)) (not connected)"))
        }
        return entries
    }

    /// What a pick in the pop-up stores: the camera's listed name, or the stored name when the
    /// `(not connected)` entry is picked again.
    static func pick(tag: String, devices: [CameraDevice], stored: Stored) -> Stored {
        if tag == systemDefaultValue { return .systemDefault }
        if let device = devices.first(where: { $0.uniqueID == tag }) {
            return .device(id: tag, name: device.name)
        }
        if case .device(let id, let name) = stored, id == tag {
            return .device(id: id, name: name)
        }
        return .device(id: tag, name: "")
    }

    /// The name to write to `recordingCameraName` when the list shows the stored camera under
    /// another name; nil when there is nothing to write.
    static func refreshedName(stored: Stored, devices: [CameraDevice]) -> String? {
        guard case .device(let id, let name) = stored,
              let device = devices.first(where: { $0.uniqueID == id }), device.name != name else { return nil }
        return device.name
    }

    /// Whether the system prompt shows: the toggle on and access not yet determined, whatever the
    /// format, since the bubble applies to GIF.
    static func asksForAccess(bubble: Bool, access: CameraAccess) -> Bool {
        bubble && access == .notDetermined
    }

    /// `Camera access is off for TidyShot.` and `Privacy Settings…` show while the toggle is on and
    /// access is denied or restricted.
    static func showsAccessNote(bubble: Bool, access: CameraAccess) -> Bool {
        bubble && (access == .denied || access == .restricted)
    }

    /// The start's camera, under the capture lock, for every start whatever the toggle (plan Gap 1).
    /// The access is read first; without it no camera is listed and the note says so. System
    /// Default is the preferred camera, read once here. A stored camera that is not listed gives the
    /// preferred camera and a note naming both. With no camera at all, none, with a note.
    static func resolveAtStart(stored: Stored, access: () -> CameraAccess, devices: () -> [CameraDevice],
                               preferred: () -> CameraDevice?) -> CameraStart {
        let access = access()
        guard access == .authorized else {
            return CameraStart(camera: nil, access: access,
                               note: RecordingNotice(title: recordedWithoutTitle, body: accessOffText))
        }
        guard case .device(let id, let name) = stored else {
            guard let camera = preferred() else {
                return CameraStart(camera: nil, access: access,
                                   note: RecordingNotice(title: recordedWithoutTitle, body: noCameraText))
            }
            return CameraStart(camera: camera, access: access, note: nil)
        }
        if let camera = devices().first(where: { $0.uniqueID == id }) {
            return CameraStart(camera: camera, access: access, note: nil)
        }
        let fallback = preferred()
        // The preferred camera counts as present even if the discovery session leaves it out.
        if let fallback, fallback.uniqueID == id {
            return CameraStart(camera: fallback, access: access, note: nil)
        }
        let missing = notConnectedText(name)
        guard let fallback else {
            return CameraStart(camera: nil, access: access, note: RecordingNotice(title: recordedWithoutTitle, body: missing))
        }
        return CameraStart(camera: fallback, access: access,
                           note: RecordingNotice(title: recordedWithTitle(fallback.name), body: missing))
    }

    /// The start as the recording takes it (plan Gap 2): a window recording has no bubble, so it
    /// drops the camera and its note. A GIF keeps both.
    static func forRecording(_ start: CameraStart, source: RecordingSource) -> CameraStart {
        guard case .window = source else { return start }
        return CameraStart(camera: nil, access: start.access, note: nil)
    }

    /// A stored name, or `Unknown camera` when none was stored.
    private static func displayName(_ name: String) -> String {
        name.isEmpty ? unknownName : name
    }
}

/// The camera a recording starts with, the access read for it, and the note that posts after
/// Stop when the bubble was wanted (`CameraNote`).
nonisolated struct CameraStart: Equatable, Sendable {
    var camera: CameraDevice?
    var access: CameraAccess
    var note: RecordingNotice?
}

/// The bar's bubble button (design, Webcam bubble, The bar's button): enabled only when the start
/// resolved a camera, access was authorized and the bubble's window is filmed, so a press
/// mid-recording can never raise the system prompt.
nonisolated struct BubbleButtonState: Equatable, Sendable {
    var isEnabled: Bool
    var disabledToolTip: String?

    static let allowInSettingsText = "Turn on Show webcam bubble in Settings to allow the camera."
    /// Also the highlights button's tool tip when its window is not filmed.
    static let notAvailableText = "Not available for this recording"

    static func make(camera: CameraDevice?, access: CameraAccess, filmed: Bool) -> BubbleButtonState {
        let toolTip: String? = switch access {
        case .notDetermined: allowInSettingsText
        case .denied, .restricted: CameraChoice.accessOffText
        case .authorized: camera == nil ? CameraChoice.noCameraText : filmed ? nil : notAvailableText
        }
        return BubbleButtonState(isEnabled: toolTip == nil, disabledToolTip: toolTip)
    }
}

/// How the camera failed during a recording: it never started, or it stopped and perhaps came back.
nonisolated enum CameraLoss: Equatable, Sendable {
    case couldNotStart
    case stopped(at: TimeInterval, backAt: TimeInterval?)
}

/// The first loss of a recording and the camera's first return after it (design, The loss note:
/// one note, for the first loss). `RecordingExtras` keeps one and closes it at its own close.
nonisolated struct CameraLossTracker: Equatable, Sendable {
    private(set) var loss: CameraLoss?
    private(set) var isClosed = false

    /// The session failed to start, unless a loss is already kept.
    mutating func couldNotStart() {
        guard !isClosed, loss == nil else { return }
        loss = .couldNotStart
    }

    /// The camera stopped, unless a loss is already kept.
    mutating func lost(at time: TimeInterval) {
        guard !isClosed, loss == nil else { return }
        loss = .stopped(at: time, backAt: nil)
    }

    /// The picture came back after the first stop; only the first return counts.
    mutating func back(at time: TimeInterval) {
        guard !isClosed, case .stopped(let at, nil) = loss else { return }
        loss = .stopped(at: at, backAt: time)
    }

    /// Nothing changes after this.
    mutating func close() {
        isClosed = true
    }
}

/// The one camera note after Stop (design, Notices and R2).
nonisolated enum CameraNote {
    static let lostTitle = "Camera lost"

    static func lostBody(at: TimeInterval, backAt: TimeInterval?) -> String {
        let stopped = "The camera stopped at \(RecordingClock.format(at))."
        guard let backAt else { return stopped + " The bubble had no picture from there." }
        return stopped + " It came back at \(RecordingClock.format(backAt))."
    }

    /// Nothing unless the bubble was wanted (the toggle on at the start, or the bar turned it on).
    /// Then the start's note, else the lookup miss's, else the first loss's, so a recording never
    /// ends with two camera banners.
    static func afterStop(start: RecordingNotice?, wanted: Bool, missed: Bool, loss: CameraLoss?) -> RecordingNotice? {
        guard wanted else { return nil }
        if let start { return start }
        if missed { return RecordingNotice(title: CameraChoice.recordedWithoutTitle, body: CameraChoice.notFilmedText) }
        switch loss {
        case nil: return nil
        case .couldNotStart:
            return RecordingNotice(title: CameraChoice.recordedWithoutTitle, body: CameraChoice.couldNotStartText)
        case .stopped(let at, let backAt):
            return RecordingNotice(title: lostTitle, body: lostBody(at: at, backAt: backAt))
        }
    }
}
