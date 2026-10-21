import Foundation
import Testing
@testable import TidyShot

/// The recently closed cards that Restore Closed Overlay walks back through (spec 2.9).
struct ClosedOverlaysTests {
    let a = UUID()
    let b = UUID()
    let c = UUID()

    @Test func newestFirst() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .autoClose)
        closed.didClose(b, reason: .user)
        closed.didClose(c, reason: .pushedOut)
        #expect(closed.ids == [c, b, a])
    }

    @Test func keepsTheTenNewest() {
        var closed = ClosedOverlays()
        let ids = (0..<12).map { _ in UUID() }
        for id in ids {
            closed.didClose(id, reason: .autoClose)
        }
        #expect(ClosedOverlays.limit == 10)
        #expect(closed.ids == Array(ids.reversed().prefix(10)))
    }

    /// A card closed, restored and closed again is listed once, at the front.
    @Test func aSecondCloseMovesTheIdToTheFront() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .user)
        closed.didClose(b, reason: .autoClose)
        closed.didClose(a, reason: .draggedOut)
        #expect(closed.ids == [a, b])
    }

    /// Deleted captures and captures now in the editor are not restorable, and leave the list.
    @Test func onlyUserAutoPushedAndDraggedClosesAreRestorable() {
        let restorable: [QuickAccessCloseReason] = [.user, .autoClose, .pushedOut, .draggedOut]
        #expect(restorable.allSatisfy { $0.isRestorable })
        #expect(!QuickAccessCloseReason.deleted.isRestorable)
        #expect(!QuickAccessCloseReason.editorOpened.isRestorable)

        var closed = ClosedOverlays()
        closed.didClose(a, reason: .deleted)
        closed.didClose(b, reason: .editorOpened)
        #expect(closed.ids.isEmpty)
        closed.didClose(a, reason: .user)
        closed.didClose(c, reason: .autoClose)
        closed.didClose(a, reason: .editorOpened)
        #expect(closed.ids == [c])
    }

    /// The newest id with a record that is not on screen. Ids without a record are dropped for
    /// good; a shown one stays for later.
    @Test func popSkipsDeletedAndShownIds() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .user)
        closed.didClose(b, reason: .user)
        closed.didClose(c, reason: .user)
        let deleted = c
        #expect(closed.popRestorable(exists: { $0 != deleted }, shown: [b]) == a)
        #expect(closed.ids == [b])
        #expect(closed.popRestorable(exists: { _ in true }, shown: [b]) == nil)
        #expect(closed.ids == [b])
        #expect(closed.popRestorable(exists: { _ in true }, shown: []) == b)
        #expect(closed.ids.isEmpty)
    }

    @Test func repeatedRestoresWalkBack() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .autoClose)
        closed.didClose(b, reason: .pushedOut)
        closed.didClose(c, reason: .user)
        var restored: [UUID] = []
        while let id = closed.popRestorable(exists: { _ in true }, shown: []) {
            restored.append(id)
        }
        #expect(restored == [c, b, a])
    }

    /// What the menu item's enabled state reads; it changes nothing.
    @Test func hasRestorableMatchesPop() {
        var closed = ClosedOverlays()
        #expect(!closed.hasRestorable(exists: { _ in true }, shown: []))
        closed.didClose(a, reason: .user)
        #expect(closed.hasRestorable(exists: { _ in true }, shown: []))
        #expect(!closed.hasRestorable(exists: { _ in false }, shown: []))
        #expect(!closed.hasRestorable(exists: { _ in true }, shown: [a]))
        #expect(closed.ids == [a])
    }
}
