import Foundation

/// The clipboard rule (spec 2.6): after an edit, the clipboard gets the edited image only while
/// it still holds exactly what TidyShot put there for that capture, so a redacted secret does not
/// linger and nothing the user copied since is lost.
nonisolated enum EditorClipboard {
    /// What TidyShot last put on the clipboard for a capture: the record, and the pasteboard's
    /// `changeCount` read right after that write.
    struct Owner: Equatable, Sendable {
        let recordID: UUID
        let changeCount: Int
    }

    /// True when `owner` is `recordID` and nothing has been written to the clipboard since.
    static func shouldReplace(owner: Owner?, recordID: UUID, currentChangeCount: Int) -> Bool {
        guard let owner else { return false }
        return owner.recordID == recordID && owner.changeCount == currentChangeCount
    }
}
