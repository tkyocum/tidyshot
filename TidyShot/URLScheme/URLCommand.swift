import Foundation

/// One `tidyshot://` command, parsed (spec 2.9, URL scheme). Pure. `parse` checks everything a
/// sender controls, so the gate, the geometry and the coordinator only see well-formed values.
nonisolated struct URLCommand: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case captureArea = "capture-area"
        case captureWindow = "capture-window"
        case captureFullscreen = "capture-fullscreen"
        case capturePreviousArea = "capture-previous-area"
        case allInOne = "all-in-one"
        case selfTimer = "self-timer"
        case captureScrolling = "capture-scrolling"
        case captureText = "capture-text"
        case recordScreen = "record-screen"
        case stopRecording = "stop-recording"
        case restoreRecentlyClosed = "restore-recently-closed"
        case hideDesktopIcons = "hide-desktop-icons"
        case showDesktopIcons = "show-desktop-icons"
        case toggleDesktopIcons = "toggle-desktop-icons"

        /// CleanShot's names that mean the same command.
        static let aliases: [String: Kind] = ["scrolling-capture": .captureScrolling]

        /// Dropped while a capture runs. Stop Recording, Restore and the desktop-icon commands capture
        /// nothing.
        var isCapture: Bool {
            switch self {
            case .stopRecording, .restoreRecentlyClosed, .hideDesktopIcons, .showDesktopIcons, .toggleDesktopIcons: false
            default: true
            }
        }
        /// Takes `action`. Capture Text always copies its result, and the others capture nothing.
        var takesAction: Bool { isCapture && self != .captureText }
        /// Takes `x`, `y`, `width`, `height` and `display`.
        var takesArea: Bool {
            self == .captureArea || self == .allInOne || self == .captureScrolling || self == .captureText
                || self == .recordScreen
        }
        /// The values of `action` the command takes. A recording is saved or uploaded, never copied,
        /// annotated or pinned.
        var actions: [Action] {
            guard takesAction else { return [] }
            return self == .recordScreen ? [.upload, .save] : Action.allCases
        }
    }

    enum Action: String, CaseIterable, Sendable {
        case upload, save, copy, annotate, pin
    }

    /// The rect as sent: points, origin at the bottom-left corner of the display.
    struct Area: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    var kind: Kind
    var action: Action?
    var area: Area?
    /// 1-based, 1 the main display. Used only together with `area`.
    var display: Int?

    /// Captures with no drag or click by the user (spec 2.9, URL security). Only these need
    /// Allow URL commands that capture without a selection.
    var capturesWithoutSelection: Bool {
        switch kind {
        case .captureFullscreen, .capturePreviousArea: true
        case .captureArea, .captureText: area != nil
        case .captureWindow, .allInOne, .selfTimer, .captureScrolling, .recordScreen, .stopRecording,
             .restoreRecentlyClosed, .hideDesktopIcons, .showDesktopIcons, .toggleDesktopIcons: false
        }
    }

    /// No arrangement of displays reaches this many points from a display's corner.
    static let coordinateLimit: Double = 100_000
    /// The longest number accepted, in characters.
    static let numberLengthLimit = 16
    /// The longest value a message quotes, in characters.
    static let displayLimit = 40
    private static let rectNames = ["x", "y", "width", "height"]

    /// The command is the host (`tidyshot://capture-area`) or the first path component
    /// (`tidyshot:capture-area`, `tidyshot:///capture-area`). `URLComponents` percent-decodes the
    /// host, the path and every query name and value; names and actions are then matched ignoring
    /// case. A parameter the command does not take is ignored; one it takes may appear once.
    static func parse(_ url: URL) -> Result<URLCommand, URLCommandError> {
        guard url.scheme?.lowercased() == "tidyshot",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.unknownCommand(url.absoluteString))
        }
        let host = components.host.flatMap { $0.isEmpty ? nil : $0 }
        let name = host ?? components.path.split(separator: "/").first.map(String.init) ?? ""
        guard let kind = Kind(rawValue: name.lowercased()) ?? Kind.aliases[name.lowercased()] else {
            return .failure(.unknownCommand(name))
        }

        var taken: Set<String> = kind.takesAction ? ["action"] : []
        if kind.takesArea {
            taken.formUnion(rectNames + ["display"])
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            let key = item.name.lowercased()
            guard taken.contains(key) else { continue }
            guard values[key] == nil else { return .failure(.repeatedParameter(key)) }
            values[key] = item.value ?? ""
        }

        var command = URLCommand(kind: kind)
        if let raw = values["action"] {
            guard let action = Action(rawValue: raw.lowercased()) else { return .failure(.unknownAction(raw)) }
            guard kind.actions.contains(action) else {
                return .failure(.unknownActionForKind(value: raw, command: kind.rawValue))
            }
            command.action = action
        }
        let rect = rectNames.map { values[$0] }
        if rect.contains(where: { $0 != nil }) {
            let numbers = rect.map { $0.flatMap { number($0) } }
            guard let x = numbers[0], let y = numbers[1], let width = numbers[2], let height = numbers[3],
                  width > 0, height > 0 else { return .failure(.badArea) }
            command.area = Area(x: x, y: y, width: width, height: height)
        }
        if let raw = values["display"] {
            guard let display = displayNumber(raw) else { return .failure(.noDisplay(raw)) }
            command.display = display
        }
        return .success(command)
    }

    /// A plain decimal: an optional `-`, digits, and at most one `.` followed by digits; at most
    /// `numberLengthLimit` characters and `coordinateLimit` in size. `Double(_:)` alone would also
    /// take `nan`, `inf`, `1e3`, `0x10` and `+5`.
    static func number(_ text: String) -> Double? {
        guard !text.isEmpty, text.utf8.count <= numberLengthLimit else { return nil }
        let unsigned = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ part in !part.isEmpty && part.unicodeScalars.allSatisfy { (48...57).contains($0.value) } }),
              let value = Double(text), value.isFinite, abs(value) <= coordinateLimit else { return nil }
        return value
    }

    /// `display`: 1 to 99, ASCII digits only.
    static func displayNumber(_ text: String) -> Int? {
        guard (1...2).contains(text.utf8.count),
              text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let value = Int(text), value >= 1 else { return nil }
        return value
    }

    /// A value from the URL (or a sender's name) as a message shows it: control and format
    /// characters (a NUL, a newline, a right-to-left override) and line separators removed, and
    /// at most `displayLimit` characters, then `…`.
    static func displayed(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: false
            default: true
            }
        }
        let text = String(kept)
        return text.count > displayLimit ? String(text.prefix(displayLimit)) + "…" : text
    }
}

/// Why a URL was not run. `message` is the notification body (spec 2.9, Errors and refusals; the
/// repeated-parameter text is this plan's).
nonisolated enum URLCommandError: Error, Equatable, Sendable {
    case unknownCommand(String)
    case unknownAction(String)
    /// A real action the command does not take.
    case unknownActionForKind(value: String, command: String)
    case badArea
    case noDisplay(String)
    case repeatedParameter(String)

    var message: String {
        switch self {
        case .unknownCommand(let name):
            "Unknown command “\(URLCommand.displayed(name))”."
        case .unknownAction(let value):
            "Unknown action “\(URLCommand.displayed(value))”. Use upload, save, copy, annotate or pin."
        case .unknownActionForKind(let value, let command):
            "Unknown action “\(URLCommand.displayed(value))” for \(command). Use upload or save."
        case .badArea:
            "x, y, width and height must be given together, as numbers, with width and height above 0."
        case .noDisplay(let value):
            "There is no display \(URLCommand.displayed(value))."
        case .repeatedParameter(let name):
            "“\(URLCommand.displayed(name))” is given more than once."
        }
    }
}
