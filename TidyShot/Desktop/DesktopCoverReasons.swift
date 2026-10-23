/// Why the desktop covers are up. They show while any reason is active, so a capture that ends
/// leaves a persistent cover in place, and turning the persistent cover off during a capture
/// keeps the covers until the capture ends.
nonisolated struct DesktopCoverReasons: Equatable, Sendable {
    enum Reason: Hashable, Sendable {
        /// A capture flow is running with `Hide desktop icons while capturing` on.
        case capture
        /// `Hide Desktop Icons` is on until turned off.
        case persistent
    }

    private(set) var active: Set<Reason> = []

    mutating func insert(_ reason: Reason) {
        active.insert(reason)
    }

    mutating func remove(_ reason: Reason) {
        active.remove(reason)
    }

    var showsCovers: Bool { !active.isEmpty }
}
