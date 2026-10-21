import Foundation

/// The ids of recently closed Quick Access cards, newest first, at most `limit`, each once.
/// In memory only: it empties at quit, and Recent Captures is the long-term way back.
nonisolated struct ClosedOverlays: Equatable, Sendable {
    static let limit = 10

    private(set) var ids: [UUID] = []

    /// A restorable close puts `id` at the front; any other takes it off the list.
    mutating func didClose(_ id: UUID, reason: QuickAccessCloseReason) {
        ids.removeAll { $0 == id }
        guard reason.isRestorable else { return }
        ids.insert(id, at: 0)
        if ids.count > Self.limit {
            ids.removeLast(ids.count - Self.limit)
        }
    }

    /// A card pushed out by a restore goes to the back of the list, as the oldest, so the next
    /// restore does not cycle through the cards on screen.
    mutating func didCloseBehind(_ id: UUID) {
        ids.removeAll { $0 == id }
        ids.append(id)
        if ids.count > Self.limit {
            ids.removeLast(ids.count - Self.limit)
        }
    }

    /// Removes and returns the newest id that `exists` (still has a history record) and is not
    /// `shown`. Ids without a record are dropped on the way; shown ones stay.
    mutating func popRestorable(exists: (UUID) -> Bool, shown: Set<UUID>) -> UUID? {
        ids.removeAll { !exists($0) }
        guard let index = ids.firstIndex(where: { !shown.contains($0) }) else { return nil }
        return ids.remove(at: index)
    }

    /// Whether `popRestorable` would return an id, without changing the list.
    func hasRestorable(exists: (UUID) -> Bool, shown: Set<UUID>) -> Bool {
        ids.contains { exists($0) && !shown.contains($0) }
    }
}
