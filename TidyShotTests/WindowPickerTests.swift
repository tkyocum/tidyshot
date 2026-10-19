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
}
