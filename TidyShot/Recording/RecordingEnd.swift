import Foundation

/// A notification's title and body.
nonisolated struct RecordingNotice: Equatable, Sendable {
    var title: String
    var body: String
}

/// What ended a recording. Whichever comes first wins.
nonisolated enum RecordingEndKind: Equatable, Sendable {
    /// The user's Stop: the panel, a shortcut, the menu, `Save` in the discard alert, or a quit.
    case stop
    /// A Cancel under 5 s, or `Discard` in the alert.
    case discardingCancel
    case diskFull
    case sleep
    case userSwitch
    case windowClosed
    /// A stream or output error, with its description.
    case failed(String)

    /// The body of `Recording stopped` for a kept file, and of `Recording failed` for a removed
    /// one. Nil for the user's own Stop and Cancel.
    var reason: String? {
        switch self {
        case .stop, .discardingCancel: nil
        case .diskFull: RecordingLimits.diskFullText
        case .sleep: "Your Mac went to sleep."
        case .userSwitch: "Another user took over the screen."
        case .windowClosed: "The recorded window closed."
        case .failed(let description): description
        }
    }
}

nonisolated enum RecordingEndDecision: Equatable, Sendable {
    case keep(notice: RecordingNotice?)
    case remove(notice: RecordingNotice?)
}

/// The end rule and the notices of a recording's end. Pure: it runs after the stop wait, on
/// `VideoValidation`'s facts.
nonisolated enum RecordingEnd {
    static let stoppedTitle = "Recording stopped"
    static let failedTitle = "Recording failed"
    /// The title of every refusal to start (disk, area size, a window or display that went).
    static let refusalTitle = "Screen recording"
    static let tooShortText = "The recording is too short."
    static let discardQuestion = "Discard this recording?"

    static func discardDetail(elapsed: TimeInterval) -> String {
        "\(RecordingClock.format(elapsed)) of recording will be deleted."
    }

    /// A discarding Cancel removes the file whatever it holds, and posts nothing. Otherwise a
    /// playable file with a video track of at least 0.5 s is kept: silently after the user's
    /// Stop, as `Recording stopped` with the reason after any other end. Anything else is removed
    /// as `Recording failed`: too short after a Stop, the reason otherwise. `waitTimedOut` changes
    /// nothing: the timeout never deletes a playable file, and an unplayable one goes either way.
    static func decide(_ kind: RecordingEndKind, facts: VideoFacts, waitTimedOut: Bool) -> RecordingEndDecision {
        if kind == .discardingCancel { return .remove(notice: nil) }
        let reason = kind.reason
        if facts.meetsMinimum {
            return .keep(notice: reason.map { RecordingNotice(title: stoppedTitle, body: $0) })
        }
        return .remove(notice: RecordingNotice(title: failedTitle, body: reason ?? tooShortText))
    }

    /// `startCapture` threw, or the output failed before the first frame: no file is kept.
    static func startFailure(_ description: String) -> RecordingNotice {
        RecordingNotice(title: failedTitle, body: description)
    }
}
