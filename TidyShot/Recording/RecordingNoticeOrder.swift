import Foundation

/// The notices a recording posts after Stop, in order (plan Gap 2; design, The note posts after
/// Stop): the save step's own notice that replaces `Recording saved` (`GIF not made`), then the
/// recorder's (`Recording stopped`, or `Recording failed` when nothing was kept), then the
/// microphone note. Quit mode posts none of them.
nonisolated enum RecordingNoticeOrder {
    static func afterStop(save: RecordingNotice?, stop: RecordingNotice?, microphone: RecordingNotice?,
                          quitMode: Bool) -> [RecordingNotice] {
        quitMode ? [] : [save, stop, microphone].compactMap { $0 }
    }
}
