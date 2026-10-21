import Testing
@testable import TidyShot

struct AllInOneChoiceTests {
    /// Left to right after the size fields and the lock, with the symbols and help of spec 2.9.
    @Test func toolbarButtonsInOrderWithTheirSymbolsAndHelp() {
        #expect(AllInOneAction.allCases == [.capture, .window, .fullscreen, .scrolling, .timer, .cancel])
        #expect(AllInOneAction.allCases.map(\.symbolName) == ["camera", "macwindow", "display", "scroll", "timer", "xmark"])
        #expect(AllInOneAction.allCases.map(\.title) == ["Capture", "Window", "Fullscreen", "Scrolling", "Timer", "Cancel"])
        #expect(AllInOneAction.allCases.map { $0.help(timerSeconds: 5) } == [
            "Capture area (Return)",
            "Capture the window with transparent corners",
            "Capture this display",
            "Scrolling capture of this area",
            "Capture this area after 5 seconds",
            "Cancel (Escape)",
        ])
        #expect(AllInOneAction.timer.help(timerSeconds: 10) == "Capture this area after 10 seconds")
    }

    /// Window needs a rect that came from a window click; every other button is always enabled.
    @Test func windowIsEnabledOnlyAfterAWindowClick() {
        #expect(!AllInOneAction.window.isEnabled(hasWindow: false))
        #expect(AllInOneAction.window.isEnabled(hasWindow: true))
        for action in AllInOneAction.allCases where action != .window {
            #expect(action.isEnabled(hasWindow: false))
        }
    }

    @Test func theLockButtonsSymbolFollowsItsState() {
        #expect(AllInOneLock.help == "Lock aspect ratio")
        #expect(AllInOneLock.symbolName(locked: true) == "lock")
        #expect(AllInOneLock.symbolName(locked: false) == "lock.open")
    }
}
