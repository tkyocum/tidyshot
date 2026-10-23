import Foundation

/// Capture → Recording → `Microphone` (design, Microphone): the stored choice, the pop-up's
/// entries, the access note, and which input a recording takes at the start. Pure: the devices
/// and the access come in as values.
nonisolated enum MicrophoneChoice {
    /// What `recordingMicrophone` and `recordingMicrophoneName` hold.
    enum Stored: Equatable, Sendable {
        case off
        case systemDefault
        /// A device by `uniqueID`, with the name it had when it was last listed (may be empty).
        case device(id: String, name: String)

        /// `value` is empty for Off, `default` for System Default, otherwise the device's `uniqueID`.
        init(value: String, name: String) {
            switch value {
            case "": self = .off
            case MicrophoneChoice.systemDefaultValue: self = .systemDefault
            default: self = .device(id: value, name: name)
            }
        }
    }

    /// The input a recording takes, if any, and the note that posts after Stop.
    struct Resolution: Equatable, Sendable {
        var device: MicrophoneDevice?
        var note: RecordingNotice?
    }

    /// A pop-up item: `tag` is the value `recordingMicrophone` stores for it.
    struct Entry: Equatable, Sendable {
        var tag: String
        var title: String
    }

    static let systemDefaultValue = "default"
    static let recordedWithoutTitle = "Recorded without the microphone"
    static let accessOffText = "Microphone access is off for TidyShot."
    static let noInputText = "No microphone is connected."
    /// The `Recording stopped` body when the recorded input went during the recording.
    static let disconnectedText = "The microphone was disconnected."
    static let unknownName = "Unknown microphone"
    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!

    static func recordedWithTitle(_ name: String) -> String {
        "Recorded with \(name)"
    }

    static func notConnectedText(_ name: String) -> String {
        "\(name) is not connected."
    }

    /// The input a recording takes (design, At the start), with access read after any prompt:
    /// none for Off; none, with the access note, unless access is authorized; the default input
    /// for System Default; a listed device itself; for a device that is not listed, the default
    /// input with a note naming both. With no input at all, none, with a note.
    static func resolve(stored: Stored, devices: [MicrophoneDevice], defaultDevice: MicrophoneDevice?,
                        access: MicrophoneAccess) -> Resolution {
        if stored == .off { return Resolution(device: nil, note: nil) }
        guard access == .authorized else {
            return Resolution(device: nil, note: RecordingNotice(title: recordedWithoutTitle, body: accessOffText))
        }
        guard case .device(let id, let name) = stored else {
            // System Default.
            guard let defaultDevice else {
                return Resolution(device: nil, note: RecordingNotice(title: recordedWithoutTitle, body: noInputText))
            }
            return Resolution(device: defaultDevice, note: nil)
        }
        // The default input counts as present even if the discovery session leaves it out.
        if let device = devices.first(where: { $0.uniqueID == id })
            ?? (defaultDevice?.uniqueID == id ? defaultDevice : nil) {
            return Resolution(device: device, note: nil)
        }
        let missing = notConnectedText(displayName(name))
        guard let defaultDevice else {
            return Resolution(device: nil, note: RecordingNotice(title: recordedWithoutTitle, body: missing))
        }
        return Resolution(device: defaultDevice,
                          note: RecordingNotice(title: recordedWithTitle(defaultDevice.name), body: missing))
    }

    /// `Off`, `System Default`, each input by name, then a stored device that is not listed,
    /// which stays the selection: `<name> (not connected)`.
    static func entries(stored: Stored, devices: [MicrophoneDevice]) -> [Entry] {
        var entries = [Entry(tag: "", title: "Off"), Entry(tag: systemDefaultValue, title: "System Default")]
        entries += devices.map { Entry(tag: $0.uniqueID, title: $0.name) }
        if case .device(let id, let name) = stored, !devices.contains(where: { $0.uniqueID == id }) {
            entries.append(Entry(tag: id, title: "\(displayName(name)) (not connected)"))
        }
        return entries
    }

    /// `Microphone access is off for TidyShot.` and `Privacy Settings…` show while a microphone
    /// is set and access is denied or restricted.
    static func showsAccessNote(stored: Stored, access: MicrophoneAccess) -> Bool {
        stored != .off && (access == .denied || access == .restricted)
    }

    /// The choice a recording starts with: a GIF has no sound, so it treats any microphone as Off,
    /// and never prompts or posts a microphone note.
    static func forRecording(_ stored: Stored, format: RecordingFormat) -> Stored {
        format == .gif ? .off : stored
    }

    /// Whether the start asks for access before the capture lock.
    static func asksForAccess(_ stored: Stored, format: RecordingFormat, access: MicrophoneAccess) -> Bool {
        forRecording(stored, format: format) != .off && access == .notDetermined
    }

    /// A stored name, or `Unknown microphone` when none was stored.
    private static func displayName(_ name: String) -> String {
        name.isEmpty ? unknownName : name
    }
}
