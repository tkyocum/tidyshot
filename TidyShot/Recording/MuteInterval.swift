import Foundation

/// A muted stretch of a recording, in seconds on the recording's clock. A nil `end` is an open
/// interval, as a mute log stores its last press; it closes at the recording's end.
nonisolated struct MuteInterval: Codable, Equatable, Sendable {
    var start: TimeInterval
    var end: TimeInterval?
}
