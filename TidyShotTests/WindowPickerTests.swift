import CoreGraphics
import Testing
@testable import TidyShot

struct WindowPickerTests {
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)

    @Test func normalOnScreenWindowFromAnotherAppIsPickable() {
        #expect(WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: frame, ownerPID: 100, selfPID: 42))
    }

    @Test func ownWindowsAreNotPickable() {
        #expect(!WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: frame, ownerPID: 42, selfPID: 42))
    }

    @Test func offScreenWindowIsNotPickable() {
        #expect(!WindowPicker.isPickable(isOnScreen: false, layer: 0, frame: frame, ownerPID: 100, selfPID: 42))
    }

    @Test func nonZeroLayerIsNotPickable() {
        #expect(!WindowPicker.isPickable(isOnScreen: true, layer: 25, frame: frame, ownerPID: 100, selfPID: 42))
    }

    @Test func tinyWindowIsNotPickable() {
        let tiny = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(!WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: tiny, ownerPID: 100, selfPID: 42))
    }

    @Test func unknownOwnerIsPickable() {
        #expect(WindowPicker.isPickable(isOnScreen: true, layer: 0, frame: frame, ownerPID: nil, selfPID: 42))
    }

    struct FakeWindow: Equatable {
        let id: CGWindowID
        let name: String
    }

    @Test func orderedSortsByFrontToBackList() {
        let items = [FakeWindow(id: 30, name: "back"), FakeWindow(id: 10, name: "front"), FakeWindow(id: 20, name: "middle")]
        let sorted = WindowPicker.ordered(items, frontToBack: [10, 20, 30]) { $0.id }
        #expect(sorted.map(\.name) == ["front", "middle", "back"])
    }

    @Test func orderedPutsUnlistedWindowsLastInOriginalOrder() {
        let items = [FakeWindow(id: 99, name: "unknownA"), FakeWindow(id: 20, name: "listed"), FakeWindow(id: 98, name: "unknownB")]
        let sorted = WindowPicker.ordered(items, frontToBack: [20]) { $0.id }
        #expect(sorted.map(\.name) == ["listed", "unknownA", "unknownB"])
    }

    @Test func orderedWithEmptyListKeepsOriginalOrder() {
        let items = [FakeWindow(id: 3, name: "a"), FakeWindow(id: 1, name: "b")]
        let sorted = WindowPicker.ordered(items, frontToBack: []) { $0.id }
        #expect(sorted == items)
    }
}
