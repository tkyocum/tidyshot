import Testing
@testable import TidyShot

/// The two General toggles against every command (spec 2.9, URL security).
struct URLCommandGateTests {
    let area = URLCommand.Area(x: 0, y: 0, width: 10, height: 10)
    let off = "URL commands are off. Turn them on in Settings > General."
    let refusal = " captures without a selection. Allow it in Settings > General > URL commands."

    /// Every command, and with a rect where one is taken: 9 kinds, 4 of them with a rect too.
    var everyCommand: [URLCommand] {
        URLCommand.Kind.allCases.flatMap { kind in
            kind.takesArea ? [URLCommand(kind: kind), URLCommand(kind: kind, area: area)] : [URLCommand(kind: kind)]
        }
    }

    @Test func withURLCommandsOffEveryCommandIsRefused() {
        #expect(everyCommand.count == 13)
        #expect(URLCommandGate.disabledMessage == off)
        for command in everyCommand {
            for allowSilent in [false, true] {
                #expect(URLCommandGate.decision(for: command, enabled: false, allowSilent: allowSilent, sender: "Raycast")
                        == .refuse(off))
            }
        }
    }

    @Test func capturesWithoutASelectionNeedTheSecondToggle() {
        let silent = [URLCommand(kind: .captureFullscreen), URLCommand(kind: .capturePreviousArea),
                      URLCommand(kind: .captureArea, area: area), URLCommand(kind: .captureText, area: area)]
        #expect(everyCommand.filter(\.capturesWithoutSelection).count == silent.count)
        for command in silent {
            #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false)
                    == .refuse(command.kind.rawValue + refusal))
            #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: true) == .run)
        }
    }

    @Test func theRefusalNamesTheSenderWhenItIsKnown() {
        let command = URLCommand(kind: .captureArea, area: area)
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "Keyboard Maestro")
                == .refuse("capture-area from Keyboard Maestro" + refusal))
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: nil)
                == .refuse("capture-area" + refusal))
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "")
                == .refuse("capture-area" + refusal))
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "Evil\u{202E}ppA")
                == .refuse("capture-area from EvilppA" + refusal))
    }

    /// A selection, a window click, All-in-One (a rect only preselects), the self-timer (it selects
    /// first), scrolling (the session waits for Start) and Capture Text without a rect all wait for
    /// the user.
    @Test func commandsThatWaitForTheUserRunWithTheSecondToggleOff() {
        let waiting = everyCommand.filter { !$0.capturesWithoutSelection }
        #expect(waiting.count == 9)
        #expect(waiting.contains(URLCommand(kind: .captureText)))
        for command in waiting {
            #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "Raycast") == .run)
        }
    }

    @Test func restoreRecentlyClosedRunsWheneverURLCommandsAreOn() {
        let restore = URLCommand(kind: .restoreRecentlyClosed)
        #expect(URLCommandGate.decision(for: restore, enabled: true, allowSilent: false) == .run)
        #expect(URLCommandGate.decision(for: restore, enabled: true, allowSilent: true) == .run)
        #expect(URLCommandGate.decision(for: restore, enabled: false, allowSilent: true) == .refuse(off))
    }

    /// No separate switch for uploads (decision 4): the action never changes the decision.
    @Test func theActionDoesNotChangeTheDecision() {
        for action in URLCommand.Action.allCases {
            #expect(URLCommandGate.decision(for: URLCommand(kind: .captureFullscreen, action: action), enabled: true, allowSilent: false)
                    == .refuse("capture-fullscreen" + refusal))
            #expect(URLCommandGate.decision(for: URLCommand(kind: .captureWindow, action: action), enabled: true, allowSilent: false)
                    == .run)
        }
    }
}
