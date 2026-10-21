import Foundation
import Testing
@testable import TidyShot

struct EditorClipboardTests {
    let id = UUID()

    @Test func replacesWhenStillOriginal() {
        let owner = EditorClipboard.Owner(recordID: id, changeCount: 41)
        #expect(EditorClipboard.shouldReplace(owner: owner, recordID: id, currentChangeCount: 41))
    }

    /// Any write since TidyShot's copy bumps the count: the user's text or a finished upload's URL.
    @Test func leavesWhenUserCopiedSomethingElse() {
        let owner = EditorClipboard.Owner(recordID: id, changeCount: 41)
        #expect(!EditorClipboard.shouldReplace(owner: owner, recordID: id, currentChangeCount: 42))
    }

    @Test func leavesWhenOwnerIsAnotherRecord() {
        let owner = EditorClipboard.Owner(recordID: UUID(), changeCount: 41)
        #expect(!EditorClipboard.shouldReplace(owner: owner, recordID: id, currentChangeCount: 41))
    }

    @Test func leavesWhenNoOwner() {
        #expect(!EditorClipboard.shouldReplace(owner: nil, recordID: id, currentChangeCount: 41))
    }
}
