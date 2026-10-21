import Foundation
import Testing
@testable import TidyShot

/// Parsing and validating `tidyshot://` URLs (spec 2.9, URL scheme). Everything here is input any
/// process on the Mac controls.
struct URLCommandTests {
    func parse(_ string: String) throws -> Result<URLCommand, URLCommandError> {
        URLCommand.parse(try #require(URL(string: string)))
    }

    /// `tidyshot://<command>` with these query items, percent-encoded by Foundation.
    func url(_ command: String, _ items: [(String, String)]) throws -> URL {
        var components = URLComponents()
        components.scheme = "tidyshot"
        components.host = command
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return try #require(components.url)
    }

    @Test func everyCommandParsesFromTheHost() throws {
        #expect(URLCommand.Kind.allCases.count == 12)
        for kind in URLCommand.Kind.allCases {
            #expect(try parse("tidyshot://\(kind.rawValue)") == .success(URLCommand(kind: kind)))
        }
    }

    @Test func everyCommandParsesFromThePath() throws {
        for kind in URLCommand.Kind.allCases {
            #expect(try parse("tidyshot:\(kind.rawValue)") == .success(URLCommand(kind: kind)))
            #expect(try parse("tidyshot:///\(kind.rawValue)") == .success(URLCommand(kind: kind)))
        }
        #expect(try parse("tidyshot:capture-area?action=copy") == .success(URLCommand(kind: .captureArea, action: .copy)))
        // The host names the command; a path after it is ignored.
        #expect(try parse("tidyshot://capture-area/") == .success(URLCommand(kind: .captureArea)))
        #expect(try parse("tidyshot://capture-area/capture-fullscreen") == .success(URLCommand(kind: .captureArea)))
    }

    @Test func scrollingCaptureIsCleanShotsNameForCaptureScrolling() throws {
        #expect(try parse("tidyshot://scrolling-capture?x=0&y=0&width=400&height=600")
                == .success(URLCommand(kind: .captureScrolling, area: .init(x: 0, y: 0, width: 400, height: 600))))
        #expect(URLCommand.Kind.aliases == ["scrolling-capture": .captureScrolling])
    }

    @Test func theSchemeTheCommandAndTheNamesIgnoreCase() throws {
        #expect(try parse("tidyshot://CAPTURE-Area") == .success(URLCommand(kind: .captureArea)))
        #expect(try parse("TIDYSHOT://capture-area") == .success(URLCommand(kind: .captureArea)))
        #expect(try parse("TidyShot:Capture-Window?Action=COPY") == .success(URLCommand(kind: .captureWindow, action: .copy)))
        #expect(try parse("tidyshot://capture-area?X=1&Y=2&WIDTH=3&Height=4")
                == .success(URLCommand(kind: .captureArea, area: .init(x: 1, y: 2, width: 3, height: 4))))
    }

    @Test func percentEncodingIsDecodedBeforeMatching() throws {
        #expect(try parse("tidyshot://capture%2Dfullscreen?action=%75pload")
                == .success(URLCommand(kind: .captureFullscreen, action: .upload)))
        #expect(try parse("tidyshot://capture-fullscreen?%61ction=copy")
                == .success(URLCommand(kind: .captureFullscreen, action: .copy)))
        #expect(try parse("tidyshot://capture-area?x=%31&y=%30&width=%31%30&height=%31%30")
                == .success(URLCommand(kind: .captureArea, area: .init(x: 1, y: 0, width: 10, height: 10))))
        // An encoded & and = stay inside the one value: no second parameter appears.
        #expect(try parse("tidyshot://capture-fullscreen?action=upload%26action%3Dcopy")
                == .failure(.unknownAction("upload&action=copy")))
    }

    @Test func everyActionParsesOnEveryCaptureCommand() throws {
        #expect(URLCommand.Action.allCases.map(\.rawValue) == ["upload", "save", "copy", "annotate", "pin"])
        for kind in URLCommand.Kind.allCases where kind.takesAction {
            for action in URLCommand.Action.allCases {
                #expect(try parse("tidyshot://\(kind.rawValue)?action=\(action.rawValue)")
                        == .success(URLCommand(kind: kind, action: action)))
            }
        }
        #expect(try parse("tidyshot://capture-area?action=UPLOAD") == .success(URLCommand(kind: .captureArea, action: .upload)))
    }

    @Test func noActionLeavesItToTheAfterCaptureSetting() throws {
        #expect(try parse("tidyshot://capture-window").get().action == nil)
        #expect(try parse("tidyshot://capture-window?foo=upload").get().action == nil)
    }

    @Test func anUnknownCommandIsAnError() throws {
        #expect(try parse("tidyshot://capture-everything") == .failure(.unknownCommand("capture-everything")))
        #expect(try parse("tidyshot://Capture-Everything") == .failure(.unknownCommand("Capture-Everything")))
        #expect(try parse("tidyshot://") == .failure(.unknownCommand("")))
        #expect(try parse("tidyshot:") == .failure(.unknownCommand("")))
        // CleanShot commands that take a file path, open other windows or record are not offered.
        for name in ["pin", "open-annotate", "add-quick-access-overlay", "open-settings", "open-history", "record-screen"] {
            #expect(try parse("tidyshot://\(name)?filepath=/tmp/x.png") == .failure(.unknownCommand(name)))
        }
        #expect(try parse("https://capture-area") == .failure(.unknownCommand("https://capture-area")))
    }

    @Test func anUnknownOrEmptyActionIsAnError() throws {
        #expect(try parse("tidyshot://capture-area?action=print") == .failure(.unknownAction("print")))
        #expect(try parse("tidyshot://capture-area?action=") == .failure(.unknownAction("")))
        #expect(try parse("tidyshot://capture-area?action") == .failure(.unknownAction("")))
        #expect(try parse("tidyshot://capture-area?action=upload%20") == .failure(.unknownAction("upload ")))
    }

    /// Capture Text (spec 2.10) takes a rect and a display, like capture-area, and no action.
    @Test func captureTextParsesWithAndWithoutARect() throws {
        #expect(try parse("tidyshot://capture-text") == .success(URLCommand(kind: .captureText)))
        #expect(try parse("tidyshot://capture-text?x=10&y=20&width=300&height=40&display=2")
                == .success(URLCommand(kind: .captureText, area: .init(x: 10, y: 20, width: 300, height: 40), display: 2)))
        #expect(try parse("tidyshot://capture-text?x=10&y=20") == .failure(.badArea))
        #expect(try parse("tidyshot://capture-text?display=0") == .failure(.noDisplay("0")))
    }

    /// Capture Text is a capture, so a running capture drops it, but it takes no action: its
    /// result always goes to the clipboard. Restore and the desktop-icon commands capture nothing
    /// and take no action.
    @Test func everyCaptureButCaptureTextTakesAnAction() {
        let capturesNothing: [URLCommand.Kind] = [.restoreRecentlyClosed, .hideDesktopIcons, .showDesktopIcons,
                                                  .toggleDesktopIcons]
        for kind in URLCommand.Kind.allCases {
            #expect(kind.isCapture == !capturesNothing.contains(kind), "\(kind)")
            #expect(kind.takesAction == (!capturesNothing.contains(kind) && kind != .captureText), "\(kind)")
        }
        #expect(URLCommand.Kind.captureText.rawValue == "capture-text")
        #expect(URLCommand.Kind.captureText.takesArea)
    }

    /// CleanShot's names (spec 2.10). They capture nothing and take no parameters, so an action, a
    /// rect or a display is ignored, even a malformed or repeated one.
    @Test func theDesktopIconCommandsParseAndIgnoreParameters() throws {
        let kinds: [(String, URLCommand.Kind)] = [("hide-desktop-icons", .hideDesktopIcons),
                                                  ("show-desktop-icons", .showDesktopIcons),
                                                  ("toggle-desktop-icons", .toggleDesktopIcons)]
        for (name, kind) in kinds {
            #expect(kind.rawValue == name)
            #expect(!kind.isCapture && !kind.takesAction && !kind.takesArea, "\(kind)")
            #expect(try parse("tidyshot://\(name)") == .success(URLCommand(kind: kind)))
            #expect(try parse("tidyshot://\(name.uppercased())") == .success(URLCommand(kind: kind)))
            #expect(try parse("tidyshot://\(name)?action=bogus&action=pin&x=1&y=2&width=-3&display=0&display=0")
                    == .success(URLCommand(kind: kind)))
            #expect(try parse("tidyshot://\(name)").get().capturesWithoutSelection == false, "\(name)")
        }
    }

    @Test func theFourRectValuesAndTheDisplayParse() throws {
        #expect(try parse("tidyshot://capture-area?x=10&y=20.5&width=640&height=480&display=2")
                == .success(URLCommand(kind: .captureArea, area: .init(x: 10, y: 20.5, width: 640, height: 480), display: 2)))
        // Negative x and y are allowed: the geometry clips the rect to its display.
        #expect(try parse("tidyshot://all-in-one?x=-100&y=-0.5&width=1&height=0.25")
                == .success(URLCommand(kind: .allInOne, area: .init(x: -100, y: -0.5, width: 1, height: 0.25))))
    }

    @Test func theRectValuesComeTogetherOrNotAtAll() throws {
        let all = [("x", "1"), ("y", "2"), ("width", "30"), ("height", "40")]
        for skipped in all.indices {
            var items = all
            items.remove(at: skipped)
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea))
        }
        #expect(try parse("tidyshot://capture-scrolling?x=1&y=2") == .failure(.badArea))
    }

    @Test func widthAndHeightMustBeAboveZero() throws {
        for (width, height) in [("0", "10"), ("10", "0"), ("-10", "10"), ("10", "-0.5"), ("-0", "5"), ("0.0", "5")] {
            let items = [("x", "0"), ("y", "0"), ("width", width), ("height", height)]
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea), "width \(width), height \(height)")
        }
    }

    /// `Double(_:)` takes `nan`, `inf`, `1e3`, `0x10` and `+5`; a URL number is a plain decimal.
    @Test func onlyPlainDecimalsAreNumbers() throws {
        let bad = ["abc", "nan", "NaN", "inf", "-inf", "infinity", "1e3", "0x10", "+5", " 5", "5 ", "5.", ".5",
                   "1.2.3", "--5", "-", "%", "1_000", "١٢", "", "5,5", "%@%s"]
        for value in bad {
            let items = [("x", "0"), ("y", "0"), ("width", value), ("height", "10")]
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea), "width=\(value)")
        }
        #expect(URLCommand.number("12.5") == 12.5)
        #expect(URLCommand.number("-0.25") == -0.25)
        #expect(URLCommand.number("007") == 7)
    }

    /// No arrangement of displays reaches 100,000 points; a larger or longer number is refused
    /// before any arithmetic sees it.
    @Test func hugeAndOverlongNumbersAreRefused() throws {
        for value in ["100001", "-100001", "99999999999999999999", "1000000000000000", "0.00000000000000001"] {
            let items = [("x", value), ("y", "0"), ("width", "10"), ("height", "10")]
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea), "x=\(value)")
        }
        #expect(URLCommand.number("100000") == 100_000)
        #expect(URLCommand.number("-100000") == -100_000)
        // 16 characters, the longest accepted.
        #expect(URLCommand.number("0.00000000000001") == 0.00000000000001)
    }

    @Test func aRepeatedParameterIsAnError() throws {
        #expect(try parse("tidyshot://capture-area?action=upload&action=copy") == .failure(.repeatedParameter("action")))
        #expect(try parse("tidyshot://capture-area?action=copy&action=copy") == .failure(.repeatedParameter("action")))
        #expect(try parse("tidyshot://capture-area?action=copy&ACTION=upload") == .failure(.repeatedParameter("action")))
        #expect(try parse("tidyshot://capture-area?x=1&y=1&width=5&height=5&x=2") == .failure(.repeatedParameter("x")))
        #expect(try parse("tidyshot://all-in-one?display=1&display=1") == .failure(.repeatedParameter("display")))
        // Found while the query is read, before any value is checked.
        #expect(try parse("tidyshot://capture-area?action=bogus&action=copy") == .failure(.repeatedParameter("action")))
    }

    @Test func parametersACommandDoesNotTakeAreIgnored() throws {
        #expect(try parse("tidyshot://capture-fullscreen?x=1&x=2&width=-5&display=abc&foo=bar&foo=baz")
                == .success(URLCommand(kind: .captureFullscreen)))
        #expect(try parse("tidyshot://capture-window?x=1&y=1&width=1&height=1&display=2")
                == .success(URLCommand(kind: .captureWindow)))
        #expect(try parse("tidyshot://restore-recently-closed?action=bogus&action=pin")
                == .success(URLCommand(kind: .restoreRecentlyClosed)))
        #expect(try parse("tidyshot://capture-text?action=bogus&action=pin")
                == .success(URLCommand(kind: .captureText)))
        #expect(try parse("tidyshot://capture-text?action=copy&x=1&y=2&width=3&height=4")
                == .success(URLCommand(kind: .captureText, area: .init(x: 1, y: 2, width: 3, height: 4))))
        #expect(try parse("tidyshot://capture-area?=5&&filepath=/etc/passwd") == .success(URLCommand(kind: .captureArea)))
    }

    @Test func theDisplayIsAWholeNumberFromOne() throws {
        #expect(try parse("tidyshot://capture-area?display=12") == .success(URLCommand(kind: .captureArea, display: 12)))
        for value in ["0", "-1", "abc", "1.5", "100", "", "+2", " 1"] {
            #expect(URLCommand.parse(try url("capture-area", [("display", value)])) == .failure(.noDisplay(value)), "display=\(value)")
        }
    }

    @Test func onlyFullscreenPreviousAreaAndARectAreaOrTextCaptureWithoutASelection() throws {
        let rect = "x=0&y=0&width=10&height=10"
        let silent = ["capture-fullscreen", "capture-previous-area", "capture-area?\(rect)", "capture-fullscreen?action=copy",
                      "capture-text?\(rect)"]
        let selecting = ["capture-area", "capture-area?action=copy", "capture-text", "capture-window", "all-in-one", "all-in-one?\(rect)",
                         "self-timer", "capture-scrolling", "capture-scrolling?\(rect)", "scrolling-capture?\(rect)",
                         "restore-recently-closed", "hide-desktop-icons", "show-desktop-icons", "toggle-desktop-icons"]
        for string in silent {
            #expect(try parse("tidyshot://\(string)").get().capturesWithoutSelection == true, "\(string)")
        }
        for string in selecting {
            #expect(try parse("tidyshot://\(string)").get().capturesWithoutSelection == false, "\(string)")
        }
    }

    @Test func valuesInMessagesAreCleanedAndShortened() throws {
        #expect(URLCommand.displayed("up\u{0}load") == "upload")
        #expect(URLCommand.displayed("\u{202E}gnp.exe") == "gnp.exe")
        #expect(URLCommand.displayed("a\u{2028}b\nc") == "abc")
        #expect(URLCommand.displayed(String(repeating: "x", count: 60)) == String(repeating: "x", count: 40) + "…")
        #expect(URLCommand.displayed(String(repeating: "x", count: 40)) == String(repeating: "x", count: 40))
        #expect(try parse("tidyshot://capture-area?action=%E2%80%AEdaolpu") == .failure(.unknownAction("\u{202E}daolpu")))
        #expect(URLCommandError.unknownAction("\u{202E}daolpu").message == "Unknown action “daolpu”. Use upload, save, copy, annotate or pin.")
    }

    @Test func errorMessagesAreTheSpecStrings() {
        #expect(URLCommandError.unknownCommand("capture-everything").message == "Unknown command “capture-everything”.")
        #expect(URLCommandError.unknownAction("print").message == "Unknown action “print”. Use upload, save, copy, annotate or pin.")
        #expect(URLCommandError.badArea.message
                == "x, y, width and height must be given together, as numbers, with width and height above 0.")
        #expect(URLCommandError.noDisplay("3").message == "There is no display 3.")
        #expect(URLCommandError.noDisplay("0").message == "There is no display 0.")
        #expect(URLCommandError.repeatedParameter("action").message == "“action” is given more than once.")
    }

    /// `xcodegen generate` writes `CFBundleURLTypes` from `project.yml` into the app's Info.plist.
    /// The tests run inside the app, so `Bundle.main` is TidyShot.app.
    @Test func theAppRegistersTheTidyShotScheme() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        #expect(types.count == 1)
        #expect(types.first?["CFBundleURLName"] as? String == "io.tky.tidyshot")
        #expect(types.first?["CFBundleURLSchemes"] as? [String] == ["tidyshot"])
    }
}
