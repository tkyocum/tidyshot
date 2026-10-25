import Foundation

/// Whether a notice posts now or waits (R2 design, Decided 2026-10-24, 8). While a recording runs,
/// every notice is held, whoever asks for it, because a banner is not a TidyShot window and would be
/// filmed; once it stops they post in the order they were asked for, before that recording's own
/// notices after Stop. Outside a hold a notice posts at once. `Notifier` keeps one.
nonisolated struct NoticeHold<Notice> {
    /// From `hold()` to `release()`.
    private(set) var isHolding = false
    /// The notices asked for during the hold, oldest first.
    private(set) var held: [Notice] = []

    /// The notice to post now: `notice` itself, or nil during a hold, when it waits instead.
    mutating func post(_ notice: Notice) -> Notice? {
        guard isHolding else { return notice }
        held.append(notice)
        return nil
    }

    /// Every notice from here waits. A hold already on keeps what waits.
    mutating func hold() {
        isHolding = true
    }

    /// Ends the hold. The notices that waited, in the order they were asked for, to post now; none
    /// when nothing waited or nothing held.
    mutating func release() -> [Notice] {
        isHolding = false
        let released = held
        held = []
        return released
    }
}
